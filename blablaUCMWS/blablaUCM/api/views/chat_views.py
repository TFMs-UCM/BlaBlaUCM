import logging

from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from django.db.models import Q
from django.utils import timezone

from travels.models import Travel, RequestTravels
from chats.models import Chat, ChatMembership, CHAT_MEMBER_REQUEST_STATES, user_is_member, get_or_create_membership, chat_display_name
from api.serializers.chat_serializer import ChatMessageSerializer
from api.errors import ErrorCodes

logger = logging.getLogger(__name__)

# Codigo del estado finalizado de un viaje, ya que en este estado no se pueden enviar mensajes en los chats
FINISHED_TRAVEL_STATE = 'fnd'

# Endpoints de los chats
class ChatViewSet(viewsets.ViewSet):
    permission_classes = [IsAuthenticated]

    def list(self, request):
        """
        Endpoint GET /chats/
        Se le pasa como parametro opcional archived=true para obtener solo los chats archivados.
        Devuelve los chats de los viajes en los que participa el usuario
        """
        user = request.user
        logger.info(f"User {user.username} requested chat list")
        # Se mira si quiere los archivados o no
        want_archived = str(request.query_params.get('archived', 'false')).lower() == 'true'

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

            # Se  escogen solo los chats que el usuario quiere
            if want_archived != is_archived:
                continue
             
            # Se obtiene el ultimo mensaje del chat que no este eliminado
            last_message = chat.messages.filter(is_deleted=False).order_by('-created_at').first()

            is_driver = travel.creation_user_id == user.id
            # El conductor solo puede salir del chat cuando el viaje ha finalizado
            can_leave = (not is_driver) or (travel.state.code == FINISHED_TRAVEL_STATE)

            # Se añade el chat a la lista de resultados
            results.append({
                'id': str(travel.id_travel),
                'chat_id': str(chat.id),
                'name': chat_display_name(travel),
                'travel_date': travel.travel_date,
                'last_message': last_message.content if last_message else None,
                'last_message_time': last_message.created_at if last_message else None,
                'is_muted': membership.is_muted if membership else False,
                'can_leave': can_leave,
            })
        
        # Se ordenan los resultados por la fecha del ultimo mensaje, si no hay mensajes, se ordena por la fecha del viaje
        results.sort(
            key=lambda item: (
                1 if item['last_message_time'] else 0,
                item['last_message_time'] or item['travel_date'],
            ),
            reverse=True,
        )

        logger.info(f"User {user.username} retrieved {len(results)} chats (archived={want_archived})")
        
        return Response({'results': results}, status=status.HTTP_200_OK)

    @action(
        detail=True, 
        methods=['get'], 
        url_path='messages'
    )
    def messages(self, request, pk=None):
        """
        Endpoint GET /chats/{travel_id}/messages/
        Devuelve el historial de mensajes del chat del viaje indicado y si se pueden enviar mensajes
        """
        travel = self._get_travel(pk)
        logger.info(f"User {request.user.username} requested messages for travel {travel.id_travel if travel else None}")
        if travel is None: # Si el viaje no existe, se devuelve un error
            return self._not_found()

        # Si el usuario no es miembro del chat, se devuelve un error
        if not user_is_member(travel, request.user):
            return self._forbidden()

        # Se obtiene el chat y los mensajes del chat que no esten eliminados
        chat = Chat.get_or_create_for_travel(travel)
        messages = chat.messages.filter(is_deleted=False).select_related('user').order_by('created_at')
        serializer = ChatMessageSerializer(messages, many=True)
        logger.info(f"User {request.user.username} retrieved {len(serializer.data)} messages for travel {travel.id_travel}")
        return Response({
            'chat_name': chat_display_name(travel),
            'can_send': travel.state.code != FINISHED_TRAVEL_STATE,
            'results': serializer.data,
        }, status=status.HTTP_200_OK)

    @action(
        detail=True, 
        methods=['post'], 
        url_path='mute'
    )
    def mute(self, request, pk=None):
        """
        Endpoint POST /chats/{travel_id}/mute/  
        Se pasa en el body el parametro: {"muted": true|false} para indicar si se quiere silenciar o reactivar las notificaciones
        """
        # Si el viaje no existe o el usuario no es miembro del chat, se devuelve un error
        logger.info(f"User {request.user.username} requested to mute/unmute travel {pk}")
        travel = self._get_travel(pk)
        if travel is None:
            return self._not_found()
        if not user_is_member(travel, request.user):
            return self._forbidden()

        # Se saca si el usuario queria silenciar o reactivar las notificaciones
        muted = bool(request.data.get('muted', True))
        # Se obtiene el chat y la membresia del usuario en el chat
        chat = Chat.get_or_create_for_travel(travel)
        membership = get_or_create_membership(chat, request.user)
        membership.is_muted = muted # Se mutea o desmutea el chat para el usuario
        membership.save(update_fields=['is_muted', 'updated_at'])

        logger.info(f"User {request.user.username} updated mute status for travel {pk}")
        return Response({'status': 'ok', 'is_muted': muted}, status=status.HTTP_200_OK)

    @action(
        detail=True, 
        methods=['post'], 
        url_path='archive'
    )
    def archive(self, request, pk=None):
        """
        Endpoint POST /chats/{travel_id}/archive/
        Archiva el chat que mueve a la seccion de archivados
        """
        # Si el viaje no existe o el usuario no es miembro del chat, se devuelve un error
        logger.info(f"User {request.user.username} requested to archive travel {pk}")
        travel = self._get_travel(pk)
        if travel is None:
            return self._not_found()
        if not user_is_member(travel, request.user):
            return self._forbidden()

        chat = Chat.get_or_create_for_travel(travel)
        membership = get_or_create_membership(chat, request.user)
        # Se archiva poniendo fecha a archived_at
        membership.archived_at = timezone.now()
        membership.save(update_fields=['archived_at', 'updated_at'])

        logger.info(f"User {request.user.username} archived travel {pk}")
        return Response({'status': 'ok'}, status=status.HTTP_200_OK)

    @action(
        detail=True, 
        methods=['post'], 
        url_path='unarchive'
    )
    def unarchive(self, request, pk=None):
        """
        Endpoint POST /chats/{travel_id}/unarchive/
        Desarchiva el chat que lo devuelve a la lista principal.
        """
        # Si el viaje no existe o el usuario no es miembro del chat, se devuelve un error
        logger.info(f"User {request.user.username} requested to unarchive travel {pk}")
        travel = self._get_travel(pk)
        if travel is None:
            return self._not_found()
        if not user_is_member(travel, request.user):
            return self._forbidden()

        chat = Chat.get_or_create_for_travel(travel)
        membership = get_or_create_membership(chat, request.user)
        # Se desarchiva poniendo archived_at a None
        membership.archived_at = None
        membership.save(update_fields=['archived_at', 'updated_at'])

        logger.info(f"User {request.user.username} unarchived travel {pk}")
        return Response({'status': 'ok'}, status=status.HTTP_200_OK)

    @action(
        detail=True, 
        methods=['delete'], 
        url_path='destroy'
    )
    def destroy(self, request, pk=None):
        """
        Endpoint DELETE /chats/{travel_id}/
        El usuario sale del chat de forma permanente.
        El conductor solo puede salir del chat cuando el viaje ha finalizado.
        """
        # Si el viaje no existe o el usuario no es miembro del chat, se devuelve un error
        logger.info(f"User {request.user.username} requested to destroy chat for travel {pk}")
        travel = self._get_travel(pk)
        if travel is None:
            return self._not_found()
        if not user_is_member(travel, request.user):
            return self._forbidden()

        # El conductor no puede abandonar el chat de un viaje que aun no ha finalizado
        is_driver = travel.creation_user_id == request.user.id
        if is_driver and travel.state.code != FINISHED_TRAVEL_STATE:
            logger.warning(f"User {request.user.username} attempted to leave chat for travel {pk} before it finished")
            return Response({
                'status': 'error',
                'message': 'No puedes salir del chat de tu viaje hasta que haya finalizado.',
                'error_code': ErrorCodes.TRAVEL_ALREADY_STARTED,
            }, status=status.HTTP_400_BAD_REQUEST)

        chat = Chat.get_or_create_for_travel(travel)
        membership = get_or_create_membership(chat, request.user)
        membership.is_removed = True
        membership.save(update_fields=['is_removed', 'updated_at'])

        logger.info(f"User {request.user.username} left the chat of travel {pk}")
        return Response({'status': 'ok'}, status=status.HTTP_200_OK)

    # Funcion para obtener un viaje por su id
    def _get_travel(self, pk):
        try:
            return Travel.objects.select_related('creation_user', 'state').get(pk=pk, is_deleted=False)
        except (Travel.DoesNotExist, ValueError):
            return None

    # Respuesta de error para los viajes no encontrados
    def _not_found(self):
        return Response({
            'status': 'error',
            'message': 'Viaje no encontrado.',
            'error_code': ErrorCodes.TRAVEL_DONT_EXIST,
        }, status=status.HTTP_404_NOT_FOUND)

    # Respuesta de error para los usuarios que no son miembros del chat
    def _forbidden(self):
        return Response({
            'status': 'error',
            'message': 'No tienes acceso al chat de este viaje.',
            'error_code': ErrorCodes.INSUFICIENT_CREDENTIALS,
        }, status=status.HTTP_403_FORBIDDEN)
