"""
Pruebas del MIDDLEWARE DE AUTENTICACION del WebSocket
    chats/middleware.py::JWTAuthMiddleware
Es la unica puerta de entrada al chat en tiempo real
El navegador no puede mandar cabeceras en un WebSocket, asi que el token viaja en
la query string (`?token=...`), y este middleware lo canjea por el usuario
"""
from channels.routing import URLRouter
from channels.testing import WebsocketCommunicator
from django.test import TransactionTestCase
from rest_framework_simplejwt.tokens import AccessToken, RefreshToken

from chats.consumers import _chat_presence
from chats.middleware import JWTAuthMiddleware
from chats.routing import websocket_urlpatterns
from travels.tests.factories import create_travel, create_user

application = JWTAuthMiddleware(URLRouter(websocket_urlpatterns))

class BaseMiddlewareTest(TransactionTestCase):
    serialized_rollback = True

    def setUp(self):
        self.driver = create_user("driver")
        self.travel = create_travel(self.driver)
        # Los datos se crean aqui, en contexto sincrono: dentro de un test
        # asincrono el ORM lanza SynchronousOnlyOperation
        self.ghost = create_user("fantasma")
        _chat_presence.clear()

    def tearDown(self):
        _chat_presence.clear()

    def token_for(self, user):
        return str(RefreshToken.for_user(user).access_token)

    async def try_connect(self, token=None):
        url = f"/ws/chat/{self.travel.pk}/"
        if token is not None:
            url = f"{url}?token={token}"

        communicator = WebsocketCommunicator(application, url)
        connected, _ = await communicator.connect()
        if connected:
            await communicator.disconnect()
        return connected


class JWTAuthMiddlewareTest(BaseMiddlewareTest):

    async def test_a_valid_token_authenticates_the_user(self):
        connected = await self.try_connect(self.token_for(self.driver))

        self.assertTrue(connected)

    async def test_without_a_token_the_connection_is_refused(self):
        self.assertFalse(await self.try_connect())

    async def test_an_empty_token_is_refused(self):
        self.assertFalse(await self.try_connect(""))

    async def test_a_garbage_token_is_refused(self):
        """Un token que ni siquiera es un JWT: lo recoge TokenError."""
        self.assertFalse(await self.try_connect("esto-no-es-un-token"))

    async def test_a_tampered_token_is_refused(self):
        """
        Un JWT bien formado pero con la firma rota. Es el caso que de verdad
        importa: comprueba que se valida la firma y no solo el formato.
        """
        valid = self.token_for(self.driver)
        tampered = valid[:-4] + ("aaaa" if not valid.endswith("aaaa") else "bbbb")

        self.assertFalse(await self.try_connect(tampered))

    async def test_an_expired_token_is_refused(self):
        from datetime import timedelta

        token = AccessToken.for_user(self.driver)
        token.set_exp(lifetime=-timedelta(minutes=1))

        self.assertFalse(await self.try_connect(str(token)))

    async def test_a_token_of_an_unknown_user_is_refused(self):
        """
        La firma es valida —mismo SECRET_KEY— pero el usuario ya no esta en esta
        base de datos. Es el mismo caso que cubre `CustomTokenRefreshSerializer`
        para el refresh: como el id es un UUID, aisla de facto los tokens entre
        instancias distintas
        """
        token = self.token_for(self.ghost)

        await self.delete_user(self.ghost.pk)

        self.assertFalse(await self.try_connect(token))

    @staticmethod
    async def delete_user(user_pk):
        from channels.db import database_sync_to_async

        from users.models import Users

        @database_sync_to_async
        def _delete():
            Users.objects.filter(pk=user_pk).delete()

        await _delete()


class DeletedAndUnverifiedUsersTest(BaseMiddlewareTest):
    async def test_a_soft_deleted_user_loses_access_to_the_chat(self):
        """
        Con la cuenta marcada como borrada la API HTTP responde 403 a todo, y el
        WebSocket seguia aceptando la conexion mientras el token no caducara.
        """
        token = self.token_for(self.driver)

        await self.mark_deleted(self.driver.pk)

        self.assertFalse(await self.try_connect(token))

    async def test_an_unverified_user_cannot_connect(self):
        """Una cuenta registrada pero sin verificar el correo tampoco entra ya."""
        token = self.token_for(self.driver)

        await self.mark_unverified(self.driver.pk)

        self.assertFalse(await self.try_connect(token))

    async def test_an_ordinary_account_still_connects(self):
        """
        Contrapartida obligatoria: sin ella, el arreglo se podria "aprobar"
        cerrando el chat a todo el mundo.
        """
        token = self.token_for(self.driver)

        self.assertTrue(await self.try_connect(token))

    @staticmethod
    async def mark_deleted(user_pk):
        from channels.db import database_sync_to_async

        from users.models import Users

        @database_sync_to_async
        def _mark():
            Users.objects.filter(pk=user_pk).update(is_deleted=True)

        await _mark()

    @staticmethod
    async def mark_unverified(user_pk):
        from channels.db import database_sync_to_async

        from users.models import Users

        @database_sync_to_async
        def _mark():
            Users.objects.filter(pk=user_pk).update(is_verify=False)

        await _mark()


class RevokedSessionsTest(BaseMiddlewareTest):
    """
    La revocacion de sesiones llegua tambien al chat.
    """

    async def test_a_revoked_token_cannot_connect(self):
        token = self.token_for(self.driver)

        await self.revoke(self.driver.pk)

        self.assertFalse(await self.try_connect(token))

    async def test_a_token_issued_after_the_revocation_connects(self):
        """
        Contrapartida: revocar no puede dejar la cuenta sin chat para siempre. El
        token que se emite despues lleva la generacion nueva y entra.
        """
        await self.revoke(self.driver.pk)

        token = await self.fresh_token(self.driver.pk)

        self.assertTrue(await self.try_connect(token))

    @staticmethod
    async def revoke(user_pk):
        from channels.db import database_sync_to_async

        from users.models import Users
        from users.services.auth_service import AuthService

        @database_sync_to_async
        def _revoke():
            AuthService.revoke_all_sessions(Users.objects.get(pk=user_pk))

        await _revoke()

    @staticmethod
    async def fresh_token(user_pk):
        from channels.db import database_sync_to_async

        from users.models import Users
        from users.services.auth_service import AuthService

        @database_sync_to_async
        def _issue():
            return AuthService.build_auth_payload(Users.objects.get(pk=user_pk))['access']

        return await _issue()
