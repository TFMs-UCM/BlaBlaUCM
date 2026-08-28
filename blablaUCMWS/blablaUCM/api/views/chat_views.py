import logging

from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from travels.models import Travel
from chats.models import user_is_member
from chats.services.chat_service import ChatService
from chats.services.exceptions import DriverCannotLeaveError
from api.serializers.chat_serializer import ChatMessageSerializer
from api.errors import ErrorCodes

logger = logging.getLogger(__name__)

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

        results = ChatService.list_chats(user, want_archived)

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

        chat_name, can_send, messages = ChatService.get_conversation(travel)
        serializer = ChatMessageSerializer(messages, many=True)

        logger.info(f"User {request.user.username} retrieved {len(serializer.data)} messages for travel {travel.id_travel}")
        return Response({
            'chat_name': chat_name,
            'can_send': can_send,
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
        ChatService.set_muted(travel, request.user, muted)

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

        ChatService.archive(travel, request.user)

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

        ChatService.unarchive(travel, request.user)

        logger.info(f"User {request.user.username} unarchived travel {pk}")
        return Response({'status': 'ok'}, status=status.HTTP_200_OK)

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

        try:
            ChatService.leave_chat(travel, request.user)
        except DriverCannotLeaveError:
            # El conductor no puede abandonar el chat de un viaje que aun no ha finalizado
            return Response({
                'status': 'error',
                'message': 'No puedes salir del chat de tu viaje hasta que haya finalizado.',
                'error_code': ErrorCodes.TRAVEL_ALREADY_STARTED,
            }, status=status.HTTP_400_BAD_REQUEST)

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
