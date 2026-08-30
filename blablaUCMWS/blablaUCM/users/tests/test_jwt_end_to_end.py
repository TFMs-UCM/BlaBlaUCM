"""
Pruebas de extremo a extremo de la autenticacion JWT
"""
from rest_framework import status
from rest_framework.test import APITestCase

from travels.tests.factories import create_user
from users.services.auth_service import AuthService


class JwtAuthenticationTest(APITestCase):

    def setUp(self):
        self.user = create_user("piloto")
        self.user.set_password("contrasena")
        self.user.has_2FA = False
        self.user.save()

    def obtain_token(self):
        response = self.client.post(
            "/api/v1/login/", {'username': "piloto", 'password': "contrasena"}, format='json'
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        return response.data['access']

    def authorize(self, token):
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")

    def test_a_token_from_login_grants_access_to_a_protected_endpoint(self):
        self.authorize(self.obtain_token())

        response = self.client.get("/api/v1/chats/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_the_authenticated_user_is_the_one_who_logged_in(self):
        self.authorize(self.obtain_token())

        response = self.client.get(f"/api/v1/users/{self.user.id}/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['username'], "piloto")

    def test_without_a_token_the_request_is_rejected(self):
        response = self.client.get("/api/v1/chats/")

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_a_malformed_token_is_rejected(self):
        self.authorize("esto-no-es-un-token")

        response = self.client.get("/api/v1/chats/")

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_a_token_of_a_user_deleted_afterwards_stops_working(self):
        """
        El soft delete revoca el acceso al instante, sin lista negra de tokens:
        `Users.is_authenticated` devuelve False en cuanto `is_deleted` es True,
        asi que `IsAuthenticated` rechaza la peticion aunque el JWT siga siendo
        criptograficamente valido
        """
        token = self.obtain_token()
        self.user.is_deleted = True
        self.user.save()

        self.authorize(token)
        response = self.client.get("/api/v1/chats/")

        self.assertIn(
            response.status_code,
            [status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN],
        )

    def test_a_token_of_a_user_unverified_afterwards_stops_working(self):
        """Mismo mecanismo, aplicado a la verificacion de la cuenta."""
        token = self.obtain_token()
        self.user.is_verify = False
        self.user.save()

        self.authorize(token)
        response = self.client.get("/api/v1/chats/")

        self.assertIn(
            response.status_code,
            [status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN],
        )


class SessionRevocationTest(APITestCase):
    def setUp(self):
        self.user = create_user("piloto")
        self.user.set_password("contrasena-buena")
        self.user.has_2FA = False
        self.user.save()

    def login(self):
        response = self.client.post(
            "/api/v1/login/",
            {'username': "piloto", 'password': "contrasena-buena"},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        return response.data

    def authorize(self, token):
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")

    def protected(self):
        return self.client.get("/api/v1/chats/").status_code

    def test_a_token_stops_working_after_a_password_change(self):

        tokens = self.login()
        self.authorize(tokens['access'])
        self.assertEqual(self.protected(), status.HTTP_200_OK)

        self.client.post(
            f"/api/v1/users/{self.user.id}/change_password/",
            {'current_password': "contrasena-buena", 'new_password': "contrasena-nueva"},
            format='json',
        )

        self.authorize(tokens['access'])
        self.assertEqual(self.protected(), status.HTTP_401_UNAUTHORIZED)

    def test_the_device_that_changed_the_password_gets_fresh_tokens(self):
        """
        Contrapartida imprescindible de la anterior: revocar echa TAMBIEN al
        dispositivo que acaba de cambiar la contraseña, que es quien tiene todo
        el derecho a seguir dentro. Por eso el endpoint devuelve un par nuevo.

        Sin esto, la aplicacion recibiria un 200 y acto seguido un 401 en la
        siguiente peticion, que es la peor forma de "funcionar".
        """
        tokens = self.login()
        self.authorize(tokens['access'])

        response = self.client.post(
            f"/api/v1/users/{self.user.id}/change_password/",
            {'current_password': "contrasena-buena", 'new_password': "contrasena-nueva"},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('access', response.data)
        self.assertIn('refresh', response.data)

        self.authorize(response.data['access'])
        self.assertEqual(self.protected(), status.HTTP_200_OK)

    def test_changing_the_second_factor_revokes_the_other_sessions(self):
        old_token = self.login()['access']
        self.authorize(self.login()['access'])

        response = self.client.post(
            f"/api/v1/users/{self.user.id}/two_factor/",
            {'enabled': True, 'password': "contrasena-buena"},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)

        self.authorize(old_token)
        self.assertEqual(self.protected(), status.HTTP_401_UNAUTHORIZED)

    def test_the_device_that_changed_the_second_factor_gets_fresh_tokens(self):
        """
        Contrapartida: quien lo cambia no puede quedarse fuera de su cuenta
        """
        self.authorize(self.login()['access'])

        response = self.client.post(
            f"/api/v1/users/{self.user.id}/two_factor/",
            {'enabled': True, 'password': "contrasena-buena"},
            format='json',
        )

        self.assertIn('access', response.data)

        self.authorize(response.data['access'])
        self.assertEqual(self.protected(), status.HTTP_200_OK)

    def test_a_token_stops_working_after_logout(self):

        tokens = self.login()
        self.authorize(tokens['access'])

        response = self.client.post(f"/api/v1/users/{self.user.id}/logout/", {}, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)

        self.authorize(tokens['access'])
        self.assertEqual(self.protected(), status.HTTP_401_UNAUTHORIZED)

    def test_the_refresh_token_is_also_dead_after_logout(self):
        """
        Revocar solo el access no serviria de nada: el refresh dura 7 dias y
        permite emitir accesos nuevos en bucle. Los dos llevan `iat`, asi que el
        mismo sello los mata a la vez.
        """
        tokens = self.login()
        self.authorize(tokens['access'])
        self.client.post(f"/api/v1/users/{self.user.id}/logout/", {}, format='json')

        self.client.credentials()
        response = self.client.post(
            "/api/v1/auth/refresh/", {'refresh': tokens['refresh']}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_nobody_can_close_someone_elses_session(self):
        """
        El endpoint es de detalle, asi que hereda el filtrado por dueño de
        `OwnedQuerysetMixin` y la URL de otra cuenta no resuelve. Sin eso,
        cerrar la sesion ajena seria una denegacion de servicio de una linea.
        """
        victim_user = create_user("victima")
        self.authorize(self.login()['access'])

        response = self.client.post(f"/api/v1/users/{victim_user.id}/logout/", {}, format='json')

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_an_ordinary_session_still_works(self):
        """
        La contrapartida de todas las anteriores: sin esta, el arreglo se aprueba
        revocandoselo a todo el mundo.
        """
        self.authorize(self.login()['access'])

        self.assertEqual(self.protected(), status.HTTP_200_OK)

    def test_an_account_that_never_revoked_anything_is_untouched(self):
        """
        Las cuentas empiezan en la generacion 0 y los tokens sin el claim se leen
        como 0, asi que al desplegar esto no se cierra ninguna sesion existente.
        """
        self.assertEqual(self.user.sessions_epoch, 0)

        self.authorize(self.login()['access'])
        self.assertEqual(self.protected(), status.HTTP_200_OK)

    def test_a_token_without_the_claim_still_works(self):
        """
        Un token emitido ANTES de que existiera la generacion de sesiones no
        lleva el claim `sv`. Tiene que seguir valiendo mientras no se revoque
        nada, o el despliegue echaria a todos los usuarios conectados.
        """
        from rest_framework_simplejwt.tokens import RefreshToken

        old_token = str(RefreshToken.for_user(self.user).access_token)

        self.authorize(old_token)
        self.assertEqual(self.protected(), status.HTTP_200_OK)

    def test_a_token_without_the_claim_is_revoked_by_a_logout(self):
        """Y en cuanto se revoca una vez, ese token de la generacion 0 cae."""
        from rest_framework_simplejwt.tokens import RefreshToken

        old_token = str(RefreshToken.for_user(self.user).access_token)
        AuthService.revoke_all_sessions(self.user)

        self.authorize(old_token)
        self.assertEqual(self.protected(), status.HTTP_401_UNAUTHORIZED)

    def test_revoking_twice_in_the_same_second_still_works(self):
        """
        El motivo por el que esto es un contador y no un sello temporal
        El primer intento uso `tokens_valid_from` y el
        claim `iat`, que se emite en SEGUNDOS ENTEROS: dentro del mismo segundo
        no habia forma de distinguir un token emitido justo antes de la
        revocacion de uno emitido justo despues.

        Con un contador el problema no existe, y esta prueba lo fija: dos
        revocaciones seguidas —tan rapidas como corra la maquina— dejan sin valor
        los tokens de cada una.
        """
        first_tokens = self.login()
        AuthService.revoke_all_sessions(self.user)

        second_tokens = self.login()
        AuthService.revoke_all_sessions(self.user)

        self.authorize(first_tokens['access'])
        self.assertEqual(self.protected(), status.HTTP_401_UNAUTHORIZED)

        self.authorize(second_tokens['access'])
        self.assertEqual(self.protected(), status.HTTP_401_UNAUTHORIZED)

    def test_the_service_moves_the_generation_forward(self):
        """La prueba unitaria del servicio, sin pasar por HTTP."""
        self.assertEqual(self.user.sessions_epoch, 0)

        AuthService.revoke_all_sessions(self.user)

        self.user.refresh_from_db()
        self.assertEqual(self.user.sessions_epoch, 1)

    def test_the_service_leaves_the_instance_usable_after_revoking(self):
        """
        `save()` con un `F()` deja el atributo como una expresion sin resolver. Si
        no se recargara, quien llame despues emitiria un token con un `sv` que es
        un objeto de Django en vez de un numero — y `change_password`, que hace
        justo eso, devolveria un par de tokens invalido.
        """
        AuthService.revoke_all_sessions(self.user)

        self.assertIsInstance(self.user.sessions_epoch, int)
