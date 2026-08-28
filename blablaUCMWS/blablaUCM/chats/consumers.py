import json
import logging
from collections import defaultdict

from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async
from django.core.exceptions import ValidationError

from travels.models import Travel
from chats.models import Chat, user_is_member, chat_display_name
from chats.services.chat_service import ChatService
from services.push.push_service import PushNotification

logger = logging.getLogger(__name__)


_chat_presence = defaultdict(set)

# Consumer que gestiona el chat en tiempo real de un viaje.

class ChatConsumer(AsyncWebsocketConsumer):

    # Funcion para conectarse al webSocket
    async def connect(self):
        self.user = self.scope.get('user')
        self.travel_id = self.scope['url_route']['kwargs']['travel_id']

        # Si no hay usuario autenticado, se cierra la conexion
        if self.user is None:
            await self.close(code=4001)
            return

        # Se comprueba que el usuario pertenezca al chat del viaje
        self.chat = await self.get_chat_if_member(self.travel_id, self.user)
        if self.chat is None:
            await self.close(code=4003)
            return

        # Todos los miembros del viaje comparten el mismo grupo del channel layer
        self.group_name = f"chat_{self.chat.id}"
        # Se asigna un nombre de grupo adicional para cada usuario, que permite enviarle mensajes de manera individual
        self.user_group_name = f"chat_{self.chat.id}_user_{self.user.id}"
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.channel_layer.group_add(self.user_group_name, self.channel_name)
        await self.accept()

        # Se marca al usuario como presente en este chat
        _chat_presence[str(self.chat.id)].add(str(self.user.id))
        logger.info(f"User {self.user.username} connected to chat of travel {self.travel_id}")

    # Funcion para desconectarse del webSocket
    async def disconnect(self, code):
        # Se retira al usuario de la presencia del chat
        if getattr(self, 'chat', None) is not None:
            _chat_presence[str(self.chat.id)].discard(str(self.user.id))

        # Se le elimina de los grupos del channel layer
        if getattr(self, 'group_name', None):
            await self.channel_layer.group_discard(self.group_name, self.channel_name)

        if getattr(self, 'user_group_name', None):
            await self.channel_layer.group_discard(self.user_group_name, self.channel_name)

    # Funcion para recibir mensajes, se guarda y se reenvia al resto del grupo
    async def receive(self, text_data=None, bytes_data=None):
        try:
            # Se parsea el JSON recibido
            data = json.loads(text_data)
        except (TypeError, ValueError): # Si es invalido, se ignora el mensaje
            return

        content = (data.get('content') or '').strip()
        if not content: # Si el mensaje esta vacio, se ignora
            return

        # Se guarda el mensaje en la base de datos y se reenvia al resto del grupo
        message = await self.save_message(content)
        # save_message devuelve None si el viaje ha finalizado
        if message is None:
            return # No se envian mensajes en viajes finalizsados
        self.last_message_created_at = message.created_at.isoformat()

        # Se envia el mensaje a todos los miembros del grupo
        await self.channel_layer.group_send(self.group_name, {
            'type': 'chat.message',
            'message': {
                'id': str(message.id),
                'user_id': str(self.user.id),
                'username': self.user.username,
                'content': message.content,
                'timestamp': self.last_message_created_at,
            }
        })

        # Se avisa por push a los miembros que no tienen el chat abierto
        await self.notify_absent_members(content)

    # Handler que reenvia a cada miembro del chat el mensaje difundido
    async def chat_message(self, event):
        await self.send(text_data=json.dumps(event['message']))

    # Handler dirigido a un usuario al que se le ha expulsado del viaje, se le avisa y se cierra su conexion
    async def chat_removed(self, event):
        await self.send(text_data=json.dumps({
            'type': 'removed',
            'message': event.get(
                'message',
                'El creador del viaje te ha eliminado, ya no tienes acceso a este chat.',
            ),
        }))
        await self.close(code=4003)

    # Funcion para recuperar el chat del viaje, solo si el usuario es miembro
    @database_sync_to_async
    def get_chat_if_member(self, travel_id, user):
        try:
            travel = Travel.objects.select_related('creation_user').get(pk=travel_id, is_deleted=False)
        except (Travel.DoesNotExist, ValueError, ValidationError): # Si el viaje no existe o el id es invalido, devuelve None
            return None
        # Se comprueba que el usuario sea miembro del viaje
        if not user_is_member(travel, user):
            return None

        # Se guardan datos del viaje para no volver a consultarlos al enviar los push
        self.travel = travel
        self.chat_name = chat_display_name(travel)
        return Chat.get_or_create_for_travel(travel)

    # Funcion para guardar un mensaje en la base de datos
    @database_sync_to_async
    def save_message(self, content):
        return ChatService.save_message(self.travel_id, self.chat, self.user, content)

    # Envia una notificacion push del mensaje a los miembros del chat que no lo tienen abierto
    @database_sync_to_async
    def notify_absent_members(self, content):
        present = set(_chat_presence.get(str(self.chat.id), set()))

        # El servicio decide a quien hay que avisar, aqui solo se envia
        for member in ChatService.members_to_notify(self.chat, self.travel, self.user, present):
            member_id = str(member.id)
            try:
                PushNotification.send_to_user(
                    user=member,
                    title=self.chat_name,
                    body=f"{self.user.username}: {content}",
                    notification_type="chat_message",
                    data={
                        'travel_id': str(self.travel_id),
                        'chat_name': self.chat_name,
                        'sender': self.user.username,
                        'content': content,
                        'timestamp': self.last_message_created_at,
                    },
                )
            except Exception as e:
                logger.error(f"Error enviando push de chat a {member_id}: {str(e)}")
