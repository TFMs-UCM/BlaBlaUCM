"""
Pruebas de extremo a extremo del CONSUMER DE WEBSOCKET del chat.
ws/chat/{travel_id}/   ->  chats/consumers.py::ChatConsumer
"""
import json
from unittest.mock import patch

from channels.layers import get_channel_layer
from channels.routing import URLRouter
from channels.testing import WebsocketCommunicator
from django.test import TransactionTestCase

from chats.consumers import _chat_presence
from chats.models import Chat
from chats.routing import websocket_urlpatterns
from travels.models import Travel, TravelStates
from travels.tests.factories import create_request, create_travel, create_user
from users.models import Device

# Se enruta igual que en produccion, pero sin el middleware de JWT: el usuario se
# inyecta en el scope a mano. El middleware tiene sus propias pruebas en test_chat_middleware.py.
application = URLRouter(websocket_urlpatterns)

class BaseConsumerTest(TransactionTestCase):
    serialized_rollback = True

    def setUp(self):
        self.driver = create_user("driver")
        self.passenger = create_user("passenger")
        self.stranger = create_user("stranger")
        self.travel = create_travel(self.driver, num_seats=3, remaining_seats=2)
        create_request(self.travel, self.passenger, 'accepted')
        self.chat = Chat.get_or_create_for_travel(self.travel)

        # _chat_presence es un diccionario de modulo: sin limpiarlo, una prueba
        # arrastra los usuarios conectados de la anterior
        _chat_presence.clear()

    def tearDown(self):
        _chat_presence.clear()

    async def connect_as(self, user, travel=None):
        """Abre la conexion como user, saltandose el middleware."""
        travel = travel or self.travel
        communicator = WebsocketCommunicator(application, f"/ws/chat/{travel.pk}/")
        communicator.scope['user'] = user
        connected, subprotocol = await communicator.connect()
        return communicator, connected


class ConnectionTest(BaseConsumerTest):

    async def test_the_driver_can_connect(self):
        communicator, connected = await self.connect_as(self.driver)

        self.assertTrue(connected)
        await communicator.disconnect()

    async def test_an_accepted_passenger_can_connect(self):
        communicator, connected = await self.connect_as(self.passenger)

        self.assertTrue(connected)
        await communicator.disconnect()

    async def test_without_a_user_the_connection_is_refused(self):
        """
        Codigo 4001: no hay nadie autenticado. Es lo que pasa cuando el middleware
        no ha podido resolver el token.
        """
        communicator = WebsocketCommunicator(application, f"/ws/chat/{self.travel.pk}/")
        communicator.scope['user'] = None

        connected, code = await communicator.connect()

        self.assertFalse(connected)
        self.assertEqual(code, 4001)

    async def test_someone_who_is_not_a_member_is_refused(self):
        """Codigo 4003: hay usuario, pero no pinta nada en este viaje."""
        communicator, connected = await self.connect_as(self.stranger)

        self.assertFalse(connected)

    async def test_an_unknown_travel_is_refused(self):
        import uuid

        communicator = WebsocketCommunicator(application, f"/ws/chat/{uuid.uuid4()}/")
        communicator.scope['user'] = self.driver

        connected, code = await communicator.connect()

        self.assertFalse(connected)

    async def test_connecting_marks_the_user_as_present(self):
        communicator, _ = await self.connect_as(self.driver)

        self.assertIn(str(self.driver.id), _chat_presence[str(self.chat.id)])

        await communicator.disconnect()

    async def test_disconnecting_removes_the_presence(self):
        communicator, _ = await self.connect_as(self.driver)
        await communicator.disconnect()

        self.assertNotIn(str(self.driver.id), _chat_presence[str(self.chat.id)])


class MessageBroadcastTest(BaseConsumerTest):

    async def test_a_message_reaches_the_other_member(self):
        """El camino completo: se envia, se guarda y se difunde al grupo."""
        sender_user, _ = await self.connect_as(self.driver)
        receiver, _ = await self.connect_as(self.passenger)

        await sender_user.send_to(text_data=json.dumps({'content': "Salgo en cinco minutos"}))

        received = await receiver.receive_from()
        message = json.loads(received)

        self.assertEqual(message['content'], "Salgo en cinco minutos")
        self.assertEqual(message['username'], "driver")
        self.assertEqual(message['user_id'], str(self.driver.id))
        self.assertIn('timestamp', message)

        await sender_user.disconnect()
        await receiver.disconnect()

    async def test_the_sender_also_receives_their_own_message(self):
        """
        Se difunde al grupo entero, emisor incluido. La app lo aprovecha para
        confirmar que el mensaje llego en vez de pintarlo de forma optimista.
        """
        sender_user, _ = await self.connect_as(self.driver)

        await sender_user.send_to(text_data=json.dumps({'content': "Hola"}))

        message = json.loads(await sender_user.receive_from())
        self.assertEqual(message['content'], "Hola")

        await sender_user.disconnect()

    async def test_an_empty_message_is_ignored(self):
        sender_user, _ = await self.connect_as(self.driver)

        await sender_user.send_to(text_data=json.dumps({'content': "   "}))

        self.assertTrue(await sender_user.receive_nothing())
        await sender_user.disconnect()

    async def test_a_malformed_payload_is_ignored_without_closing(self):
        """
        Un JSON invalido no puede tirar la conexion: se ignora y el socket sigue
        vivo para el siguiente mensaje.
        """
        sender_user, _ = await self.connect_as(self.driver)

        await sender_user.send_to(text_data="esto no es json")

        self.assertTrue(await sender_user.receive_nothing())

        await sender_user.send_to(text_data=json.dumps({'content': "Ahora si"}))
        message = json.loads(await sender_user.receive_from())
        self.assertEqual(message['content'], "Ahora si")

        await sender_user.disconnect()

    async def test_a_payload_without_content_is_ignored(self):
        sender_user, _ = await self.connect_as(self.driver)

        await sender_user.send_to(text_data=json.dumps({'otra_cosa': "x"}))

        self.assertTrue(await sender_user.receive_nothing())
        await sender_user.disconnect()


class FinishedTravelTest(BaseConsumerTest):

    async def test_a_message_on_a_finished_travel_is_not_broadcast(self):
        """
        ChatService.save_message devuelve None cuando el viaje esta finalizado, y
        esa es la señal para que el consumer no difunda nada. El socket sigue
        abierto: el chat pasa a ser de solo lectura, no desaparece.
        """
        sender_user, _ = await self.connect_as(self.driver)

        await self.finish_travel()

        await sender_user.send_to(text_data=json.dumps({'content': "Ya hemos llegado"}))

        self.assertTrue(await sender_user.receive_nothing())
        await sender_user.disconnect()

    @staticmethod
    async def finish_travel_async(travel_pk):
        from channels.db import database_sync_to_async

        @database_sync_to_async
        def _finish():
            Travel.objects.filter(pk=travel_pk).update(
                state=TravelStates.objects.get(code='fnd')
            )

        await _finish()

    async def finish_travel(self):
        await self.finish_travel_async(self.travel.pk)


class RemovedFromChatTest(BaseConsumerTest):

    async def test_the_removed_user_is_warned_and_disconnected(self):
        """
        Cuando el conductor expulsa a un pasajero, la vista manda un mensaje al
        grupo individual de ese usuario. El consumer se lo entrega y cierra.
        """
        communicator, _ = await self.connect_as(self.passenger)

        channel_layer = get_channel_layer()
        await channel_layer.group_send(
            f"chat_{self.chat.id}_user_{self.passenger.id}",
            {'type': 'chat.removed', 'message': "Te han eliminado del viaje."},
        )

        notification = json.loads(await communicator.receive_from())

        self.assertEqual(notification['type'], 'removed')
        self.assertEqual(notification['message'], "Te han eliminado del viaje.")

        await communicator.disconnect()

    async def test_the_message_only_reaches_the_removed_user(self):
        """
        El grupo individual existe justo para esto: expulsar a uno no puede
        avisar a todo el chat.
        """
        removed_user, _ = await self.connect_as(self.passenger)
        driver_user, _ = await self.connect_as(self.driver)

        channel_layer = get_channel_layer()
        await channel_layer.group_send(
            f"chat_{self.chat.id}_user_{self.passenger.id}",
            {'type': 'chat.removed', 'message': "Fuera."},
        )

        await removed_user.receive_from()
        self.assertTrue(await driver_user.receive_nothing())

        await removed_user.disconnect()
        await driver_user.disconnect()


class PushOnAbsentMembersTest(BaseConsumerTest):
    """
    La decision de a quien avisar es de `ChatService.members_to_notify`
    Aqui se comprueba el cableado: que el consumer usa la
    presencia real de las conexiones abiertas
    """

    def setUp(self):
        super().setUp()
        # Sin dispositivo, PushNotification.send_to_user sale antes de intentar
        # nada, asi que el doble no llegaria a distinguir los casos
        Device.objects.create(
            id_user=self.passenger, fcm_token="token-pasajero", platform="android"
        )

    @patch('chats.consumers.PushNotification.send_to_user')
    async def test_a_member_with_the_chat_open_is_not_pushed(self, send_push):
        sender_user, _ = await self.connect_as(self.driver)
        receiver, _ = await self.connect_as(self.passenger)

        await sender_user.send_to(text_data=json.dumps({'content': "Hola"}))
        await receiver.receive_from()

        send_push.assert_not_called()

        await sender_user.disconnect()
        await receiver.disconnect()

    @patch('chats.consumers.PushNotification.send_to_user')
    async def test_a_member_without_the_chat_open_is_pushed(self, send_push):
        sender_user, _ = await self.connect_as(self.driver)

        await sender_user.send_to(text_data=json.dumps({'content': "Hola"}))
        await sender_user.receive_from()

        send_push.assert_called_once()
        self.assertEqual(send_push.call_args.kwargs['user'], self.passenger)
        self.assertIn("driver", send_push.call_args.kwargs['body'])

        await sender_user.disconnect()