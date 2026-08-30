import logging

from django.db.models import Q
from django.utils import timezone

from chats.models import (
    CHAT_MEMBER_REQUEST_STATES, Chat, ChatMembership, ChatMessage, 
    chat_display_name, get_member_users, get_or_create_membership)
from chats.services.exceptions import DriverCannotLeaveError
from travels.models import RequestTravels, Travel

# Logger para ir almacenando los logs
logger = logging.getLogger(__name__)

# Codigo del estado finalizado de un viaje, ya que en este estado no se pueden enviar mensajes en los chats
FINISHED_TRAVEL_STATE = 'fnd'


# Servicio con la logica de negocio del subsistema de mensajeria
class ChatService:
    """
    Centraliza las reglas de negocio de los chats de viaje.
    Lo usan tanto el ViewSet HTTP (listado, silenciar, archivar, salir) como el consumer de WebSocket 
    """

    # Devuelve los chats de los viajes en los que participa el usuario
    @staticmethod
    def list_chats(user, want_archived=False):
        """
        Arma el listado de chats del usuario, ya ordenado
        want_archived decide si se devuelven los archivados o los activos
        Devuelve una lista de diccionarios lista para serializar
        """
        # Viajes donde el usuario es el conductor
        driver_travel_ids = Travel.objects.filter(
            creation_user=user, is_deleted=False
        ).values_list('pk', flat=True)

        # Viajes donde el usuario es pasajero
        passenger_travel_ids = RequestTravels.objects.filter(
            user=user,
            status__code__in=CHAT_MEMBER_REQUEST_STATES,
            is_deleted=False,
        ).values_list('id_travel', flat=True)

        # Se sacan los viajes en los que el usuario es conductor o pasajero
        travels = Travel.objects.filter(
            Q(pk__in=driver_travel_ids) | Q(pk__in=passenger_travel_ids),
            is_deleted=False,
        ).select_related('creation_user', 'state').distinct()

        results = []
        for travel in travels:
            # Se obtiene el chat
            chat = Chat.get_or_create_for_travel(travel)
            # Se obtiene la membresia del usuario en el chat, si existe
            membership = ChatMembership.objects.filter(chat=chat, user=user).first()

            # Si se le ha eliminado del chat, no se le devuelve
            if membership and membership.is_removed:
                continue

            # Se mira si el chat esta archivado o no para el usuario
            is_archived = membership is not None and membership.archived_at is not None

            # Se escogen solo los chats que el usuario quiere
            if want_archived != is_archived:
                continue

            # Se obtiene el ultimo mensaje del chat que no este eliminado
            last_message = chat.messages.filter(is_deleted=False).order_by('-created_at').first()

            # Se añade el chat a la lista de resultados
            results.append({
                'id': str(travel.id_travel),
                'chat_id': str(chat.id),
                'name': chat_display_name(travel),
                'travel_date': travel.travel_date,
                'last_message': last_message.content if last_message else None,
                'last_message_time': last_message.created_at if last_message else None,
                'is_muted': membership.is_muted if membership else False,
                'can_leave': ChatService.can_leave(travel, user),
            })

        # Se ordenan los resultados por la fecha del ultimo mensaje, si no hay mensajes, se ordena por la fecha del viaje
        results.sort(
            key=lambda item: (
                1 if item['last_message_time'] else 0,
                item['last_message_time'] or item['travel_date'],
            ),
            reverse=True,
        )

        return results

    # Indica si el usuario puede abandonar el chat del viaje
    @staticmethod
    def can_leave(travel, user):
        # El conductor solo puede salir del chat cuando el viaje ha finalizado
        is_driver = travel.creation_user_id == user.id
        return (not is_driver) or (travel.state.code == FINISHED_TRAVEL_STATE)

    # Devuelve el historial de mensajes del chat de un viaje
    @staticmethod
    def get_conversation(travel):
        """
        Devuelve la tupla (nombre del chat, se pueden enviar mensajes, mensajes)
        """
        chat = Chat.get_or_create_for_travel(travel)
        messages = chat.messages.filter(is_deleted=False).select_related('user').order_by('created_at')
        return chat_display_name(travel), ChatService.can_send_messages(travel), messages

    # Indica si en el chat del viaje todavia se pueden enviar mensajes
    @staticmethod
    def can_send_messages(travel):
        # Solo se pueden enviar mensajes mientras el viaje no haya finalizado
        return travel.state.code != FINISHED_TRAVEL_STATE

    # Silencia o reactiva las notificaciones del chat para un usuario
    @staticmethod
    def set_muted(travel, user, muted):
        chat = Chat.get_or_create_for_travel(travel)
        membership = get_or_create_membership(chat, user)
        membership.is_muted = muted # Se mutea o desmutea el chat para el usuario
        membership.save(update_fields=['is_muted', 'updated_at'])
        return membership

    # Archiva el chat, que lo mueve a la seccion de archivados
    @staticmethod
    def archive(travel, user):
        chat = Chat.get_or_create_for_travel(travel)
        membership = get_or_create_membership(chat, user)
        # Se archiva poniendo fecha a archived_at
        membership.archived_at = timezone.now()
        membership.save(update_fields=['archived_at', 'updated_at'])
        return membership

    # Desarchiva el chat, que lo devuelve a la lista principal
    @staticmethod
    def unarchive(travel, user):
        chat = Chat.get_or_create_for_travel(travel)
        membership = get_or_create_membership(chat, user)
        # Se desarchiva poniendo archived_at a None
        membership.archived_at = None
        membership.save(update_fields=['archived_at', 'updated_at'])
        return membership

    # El usuario sale del chat de forma permanente
    @staticmethod
    def leave_chat(travel, user):
        """
        Marca al usuario como eliminado del chat
        Lanza DriverCannotLeaveError si es el conductor y el viaje aun no ha finalizado
        """
        if not ChatService.can_leave(travel, user):
            logger.warning(f"User {user.username} attempted to leave chat for travel {travel.id_travel} before it finished")
            raise DriverCannotLeaveError()

        chat = Chat.get_or_create_for_travel(travel)
        membership = get_or_create_membership(chat, user)
        membership.is_removed = True
        membership.save(update_fields=['is_removed', 'updated_at'])

        logger.info(f"User {user.username} left the chat of travel {travel.id_travel}")
        return membership

    # Guarda un mensaje en el chat de un viaje
    @staticmethod
    def save_message(travel_id, chat, user, content):
        """
        Crea el mensaje, salvo que el viaje ya haya finalizado
        Devuelve None en ese caso, para que el consumer sepa que no debe difundirlo
        """
        state_code = Travel.objects.filter(pk=travel_id).values_list('state', flat=True).first()
        if state_code == FINISHED_TRAVEL_STATE: # Se valida que el viaje no haya finalizado
            return None
        return ChatMessage.objects.create(chat=chat, user=user, content=content)

    # Decide a que miembros del chat hay que enviarles la notificacion push
    @staticmethod
    def members_to_notify(chat, travel, sender, present_ids):
        """
        Devuelve los miembros que deben recibir el push de un mensaje nuevo
        Se excluye al que lo envia, a los que tienen el chat abierto en ese
        momento y a los que lo tienen silenciado o de los que se les ha eliminado.
        """
        sender_id = str(sender.id)

        excluded_ids = set(
            str(uid) for uid in ChatMembership.objects.filter(
                chat=chat,
            ).filter(
                Q(is_muted=True) | Q(is_removed=True)
            ).values_list('user_id', flat=True)
        )

        recipients = []
        for member in get_member_users(travel):
            member_id = str(member.id)
            if member_id == sender_id or member_id in present_ids or member_id in excluded_ids:
                continue
            recipients.append(member)

        return recipients
