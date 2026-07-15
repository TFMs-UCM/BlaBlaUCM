from warnings import deprecated
from users.models import Vehicles
import logging
from api.serializers.user_serializer import PreferencesSerializer
from users.models import Preferences
from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework import status
from django.contrib.gis.geos import Point
from django.contrib.gis.db.models.functions import Distance
from django.db.models import Count, Exists, OuterRef
from django.contrib.gis.measure import D
from travels.models import Travel, TravelStates, RequestStates, RequestTravels, PickUpPoints, UsersDenied
from api.serializers.travel_serializer import TravelStatesSerializer, TravelSerializer, \
    RequestStatesSerializer, RequestTravelsSerializer, PickUpPointSerializer, UsersDeniedSerializer

from django.template.defaultfilters import date as django_date

from users.models import Notifications, Users, UserType
from api.serializers.user_serializer import NotificationsSerializer
from django.core.paginator import Paginator, EmptyPage
from rest_framework.decorators import action
from rest_framework.parsers import MultiPartParser, FormParser
from django.utils.dateparse import parse_datetime
from django.db import connection
import logging
from django.utils import timezone
from django.utils.timezone import make_aware, is_naive
from django.db import transaction
from django.db.models import Q, F, Min, Max
from datetime import datetime, timedelta
from channels.layers import get_channel_layer
from asgiref.sync import async_to_sync
from chats.models import Chat
import string
import random
from django.utils.dateparse import parse_datetime, parse_date
from api.soft_delete import SoftDeleteQuerysetMixin
from api.errors import ErrorCodes

# Logger para ir almacenando los logs
logger = logging.getLogger(__name__)

# Cierra la conexion WebSocket del chat de un usuario al que se acaba de expulsar del viaje
def _notify_chat_removed(travel, user):
    logger.info(f"Notifying user {user.username} about removal from chat of travel {travel.id_travel}")
    try:
        channel_layer = get_channel_layer() # Se obtiene el canal para enviar los mensajes del websocket
        if channel_layer is None: # Si no existe, no se hace nada
            return
        chat = Chat.get_or_create_for_travel(travel)
        async_to_sync(channel_layer.group_send)( # Se envia un mensaje indicando que el usuario ha sido expulsado del chat
            f"chat_{chat.id}_user_{user.id}",
            {
                'type': 'chat.removed',
                'message': 'El creador del viaje te ha eliminado, ya no tienes acceso a este chat.',
            },
        )
        logger.info(f"Successfully notified user {user.username} about removal from chat of travel {travel.id_travel}")
    except Exception as e:
        logger.error(f"Error occurred while notifying user {user.username} about removal from chat of travel {travel.id_travel}: {str(e)}")

# Endpoint para los estados de los viajes
class TravelStatesViewSet(SoftDeleteQuerysetMixin, viewsets.ModelViewSet):
    queryset = TravelStates.objects.all()
    serializer_class = TravelStatesSerializer
    permission_classes = [IsAuthenticated]

# Endpoints de los viajes
class TravelViewSet(SoftDeleteQuerysetMixin, viewsets.ModelViewSet):
    queryset = Travel.objects.all()
    serializer_class = TravelSerializer
    permission_classes = [IsAuthenticated]
    
    # Se sobreescribe el metodo partial_update para evitar que se puedan comenzar dos viajes a la vez
    def partial_update(self, request, *args, **kwargs):
        travel = self.get_object()

        logger.info(f"Request to update travel {travel.id_travel} by user {request.user.username}")

        # Solo el creador del viaje puede editarlo
        if travel.creation_user != request.user:
            return Response({
                "status": "error",
                "message": "No tienes permiso para actualizar este viaje.",
                "error_code": ErrorCodes.INSUFICIENT_CREDENTIALS
            }, status=status.HTTP_403_FORBIDDEN)

        started_state = TravelStates.objects.get(code='started')

        if Travel.objects.filter(creation_user=request.user, is_deleted=False, state=started_state).exclude(pk=travel.pk).count() >= 1:
            return Response({
                "status": "error",
                "message": "No puedes iniciar un nuevo viaje mientras tengas otro en curso.",
                "error_code": ErrorCodes.TRAVEL_ALREADY_STARTED
            }, status=status.HTTP_400_BAD_REQUEST)

        return super().partial_update(request, *args, **kwargs)

    # Se sobreescribe el metodo destroy para eliminar el viaje, las solicitudes asociadas y notificar a los usuarios afectados
    def destroy(self, request, *args, **kwargs):
        """
        Endpoint DELETE /travels/{id_travel}/
        Elimina el viaje indicado, y las solicitudes asociadas a este
        """
        travel = self.get_object()

        logger.info(f"Request to delete travel {travel.id_travel} by user {request.user.username}")

        # Solo el creador del viaje puede eliminarlo
        if travel.creation_user != request.user:
            return Response({
                "status": "error",
                "message": "No tienes permiso para eliminar este viaje.",
                "error_code": ErrorCodes.INSUFICIENT_CREDENTIALS
            }, status=status.HTTP_403_FORBIDDEN)

        # Se sacan las solicitudes del viaje
        request_travels = travel.requested_travels.filter(is_deleted=False)
        try:
            with transaction.atomic():
                if travel.state.code == 'active': # Solo se borran las solicitudes si el viaje esta activo, si ya ha pasado, no se borran
                    notificaciones = []
                    # Se crea el mensaje generico que se le envia a cada usuario
                    parsed_date = django_date(travel.travel_date, r"j \d\e F \d\e Y")

                    msg = f"El viaje de {travel.origin} a {travel.destination} del día {parsed_date} ha sido cancelado."

                    # Se guardan las notificaciones para insertarlas en bbdd
                    for rt in request_travels: # Se notifica a todos los usuarios con una solicitud, aunque estuviera pendiente
                        notificaciones.append(
                            Notifications(
                                id_user=rt.user,
                                content=msg
                            )
                        )
                    # Se insertan las notificaciones en bbdd
                    if notificaciones:
                        Notifications.objects.bulk_create(notificaciones)
                    logger.info(f"Sent {len(notificaciones)} notifications for the deleted travel {travel.id_travel}.")

                    logger.info(f"Soft-deleting requests associated with travel {travel.id_travel}.")
                    travel.requested_travels.filter(is_deleted=False).update(
                        is_deleted=True,
                        deleted_at=timezone.now()
                    )

                logger.info(f"Soft-deleting travel {travel.id_travel}.")
                return super().destroy(request, *args, **kwargs)
        except Exception as e:
            logger.error(f"Error deleting travel {travel.id_travel}: {str(e)}")
            return Response({
                "status": "error",
                "message": "Error interno del servidor, vuelve a intentarlo más tarde.",
                "error_code": ErrorCodes.INTERNAL_SERVER_ERROR
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    @action(
        detail=False,
        methods=['post'],
        url_path='search-travels',
        permission_classes=[IsAuthenticated]
    )
    def search_travels(self, request, *args, **kwargs):
        """
        Endpoint POST /travel/search-travels/
        Realiza la busqueda de los viajes segun los filtros, las respuestas estan paginadas
        Devuelve un diccionario con los datos de los viajes y la url de la siguiente pagina (si existe)
        """
        data = request.data

        # Paginacion
        page_number = int(data.get('page', 1))
        page_size = 10

        # Ordenacion (Por defecto 'recent')
        sort_by = data.get('sort_by', 'recent')

        # Se sacan las coordenadas y radios, si no vienen se pone 0 para que no se filtre
        orig_lat = data.get('origin', {}).get('lat', 0)
        orig_lng = data.get('origin', {}).get('lng', 0)
        dest_lat = data.get('destination', {}).get('lat', 0)
        dest_lng = data.get('destination', {}).get('lng', 0)

        # Se sacan los radios de busqueda, por defecto se pone a 10km para que salgan algunos resultados relevantes
        rad_orig_raw = float(data.get('radius_origin_km', 0.0))
        rad_orig = rad_orig_raw if rad_orig_raw > 0 else 10.0

        rad_dest_raw = float(data.get('radius_dest_km', 0.0))
        rad_dest = rad_dest_raw if rad_dest_raw > 0 else 10.0

        # Fechas y sus parseos para poder filtrar por ellas
        date_from_raw = data.get('date_from')
        date_until_raw = data.get('date_until')

        date_from = None
        date_until = None

        if date_from_raw:
            parsed_from = parse_datetime(date_from_raw)
            if parsed_from:
                date_from = make_aware(parsed_from) if is_naive(parsed_from) else parsed_from

        if date_until_raw:
            naive_until = datetime.strptime(date_until_raw[:10], '%Y-%m-%d') + timedelta(days=1)
            date_until = make_aware(naive_until)

        # preferencias, tipo de viaje, usuarios denegados y distintivo ambiental
        preferences = data.get('preferences', [])
        env_sticker = data.get('env_sticker')
        travel_type = data.get('travel_type')
        users_deny = data.get('users_deny', [])

        logger.debug(f"Received search parameters: Origin({orig_lat}, {orig_lng}, {rad_orig}km), "
                     f"Destination({dest_lat}, {dest_lng}, {rad_dest}km), "
                     f"Preferences({preferences}), EnvSticker({env_sticker}), TravelType({travel_type}), "
                     f"DateFrom({data.get('date_from')}), DateUntil({data.get('date_until')})")
        try:
           # Crear los puntos espaciales
            orig_pt = Point(orig_lng, orig_lat, srid=4326)
            dest_pt = Point(dest_lng, dest_lat, srid=4326)

            has_origin = orig_lat != 0 or orig_lng != 0
            has_dest = dest_lat != 0 or dest_lng != 0

            # Se sacan los viajes que no son del usuario, que tengan asientos disponibles y esten activos
            travels = self.get_queryset().exclude(creation_user=request.user).exclude(remaining_seats__lt=1).filter(state='active')

            if has_origin and has_dest:
                # Anotamos el orden usando los radios
                travels = travels.annotate(
                    min_orig_stop_order=Min(
                        'pickup_points__order_in_travel',
                        filter=Q(pickup_points__point__distance_lte=(orig_pt, D(km=rad_orig))) & Q(pickup_points__is_deleted=False)
                    ),
                    max_dest_stop_order=Max(
                        'pickup_points__order_in_travel',
                        filter=Q(pickup_points__point__distance_lte=(dest_pt, D(km=rad_dest))) & Q(pickup_points__is_deleted=False)
                    )
                )

                # El origen principal cuadra
                cond_main_origin = Q(origin_point__distance_lte=(orig_pt, D(km=rad_orig))) & (
                    Q(destination_point__distance_lte=(dest_pt, D(km=rad_dest))) |
                    Q(max_dest_stop_order__isnull=False)
                )

                # El destino principal cuadra
                cond_main_dest = Q(destination_point__distance_lte=(dest_pt, D(km=rad_dest))) & (
                    Q(origin_point__distance_lte=(orig_pt, D(km=rad_orig))) |
                    Q(min_orig_stop_order__isnull=False)
                )

                # Coincide con las paradas intermedias
                cond_stops = (
                    Q(min_orig_stop_order__isnull=False) &
                    Q(max_dest_stop_order__isnull=False) &
                    Q(min_orig_stop_order__lt=F('max_dest_stop_order'))
                )

                travels = travels.filter(cond_main_origin | cond_main_dest | cond_stops).distinct()

            elif has_origin:
                # Solo se relleno el origen en el buscador
                travels = travels.filter(
                    Q(origin_point__distance_lte=(orig_pt, D(km=rad_orig))) |
                    (Q(pickup_points__point__distance_lte=(orig_pt, D(km=rad_orig))) & Q(pickup_points__is_deleted=False))
                ).distinct()

            elif has_dest:
                # Solo se relleno el destino en el buscador
                travels = travels.filter(
                    Q(destination_point__distance_lte=(dest_pt, D(km=rad_dest))) |
                    (Q(pickup_points__point__distance_lte=(dest_pt, D(km=rad_dest))) & Q(pickup_points__is_deleted=False))
                ).distinct()

            # Anotaciones de distancia para ordenar despues
            if has_origin:
                travels = travels.annotate(dist_origin=Distance('origin_point', orig_pt))
            if has_dest:
                travels = travels.annotate(dist_dest=Distance('destination_point', dest_pt))


            active_block_for_me = UsersDenied.objects.filter(
                id_travel=OuterRef('pk'),
                user_type__code=self.request.user.user_type.code,
                is_deleted=False
            )

            travels = travels.annotate(
                is_blocked_for_me=Exists(active_block_for_me)
            ).filter(is_blocked_for_me=False)

            # Si se especifican usuarios que deben ser excluidos, se filtran los viajes que los cumplan
            if users_deny:
                travels = travels.exclude(
                    creation_user__user_type__code__in=users_deny
                )
                travels = travels.filter(
                    users_denied__user_type__code__in=users_deny,
                    users_denied__is_deleted=False
                ).annotate(
                    matching_denies=Count('users_denied', distinct=True)
                ).filter(
                    matching_denies=len(users_deny)
                )

            logger.debug(f"Travel IDs after excluding user type: {[str(t.id_travel) for t in travels]}")
            # Se filtra por la fecha de inicio de busqueda
            if date_from:
                travels = travels.filter(travel_date__gte=date_from)

            # Se filtra por la fecha de fin
            if date_until:
                travels = travels.filter(travel_date__lt=date_until)
            # Se filtra por las preferencias del conductor, si se han especificado
            if preferences:
                travels = travels.filter(driver__preferences__name__in=preferences).distinct()
            # Se filtra por el distintivo ambiental, si se ha especificado
            if env_sticker and env_sticker != 'all':
                travels = travels.filter(vehicle__env_sticker=env_sticker)

            logger.debug(f"Travel IDs after excluding for preferences, env_sticker and users_deny: {[str(t.id_travel) for t in travels]}")

            if travel_type and travel_type != 'all': # Se filtra por el tipo de viaje
                if travel_type == 'periodic':
                    travels = travels.filter(is_periodic=True)
                elif travel_type == 'punctual':
                    travels = travels.filter(is_periodic=False)

           # Se ordena segun el criterio seleccionado
            if sort_by == 'origin' and has_origin:
                travels = travels.order_by('dist_origin')
            elif sort_by == 'destination' and has_dest:
                travels = travels.order_by('dist_dest')
            elif sort_by == 'late':
                travels = travels.order_by('-travel_date')
            else: # recent
                travels = travels.order_by('travel_date')

            # Se paginan los resultados
            paginator = Paginator(travels, page_size)
            page_obj = paginator.get_page(page_number)

            # Serializamos solo los viajes de esta página
            serializer = self.get_serializer(page_obj, many=True)
            final_data = list(serializer.data)

            return Response({
                'status': 'ok',
                'data': final_data,
                'has_next': page_obj.has_next() if hasattr(page_obj, 'has_next') else False
            })

        except Exception as e:
            logger.error(f"Error in search_travels: {str(e)}")
            return Response({'status': 'error', 'message': str(e), 'error_code': ErrorCodes.INTERNAL_SERVER_ERROR}, status=500)

    @action(
        detail=False,
        methods=['post'],
        url_path='request-travel',
        permission_classes=[IsAuthenticated]
    )
    def request_travel(self, request):
        """
        Endpoint POST /travel/request-travel/
        Solicita una plaza en uno o varios viajes.
        Recibe una lista de ids de los viajes que se quiere solicitar.
        Devuelve un menssaje de exito o error
        """
        travel_ids = request.data.get('travel_ids', [])  # La lista de viajes, deben ser los UUID de los viajes
        user = request.user

        logger.info(f"User {user.username} is requesting travel {travel_ids}")

        try:
            with transaction.atomic():
                # No se debe permitir que el usuario solicite una plaza para su propio viaje
                if Travel.objects.filter(id_travel__in=travel_ids, creation_user=user, is_deleted=False).exists():
                    logger.warning(f"User {user.username} tried to request their own travel {travel_ids}")
                    return Response({
                        "status": "error",
                        "message": "No puedes solicitar una plaza en tu propio viaje.",
                        "error_code": ErrorCodes.REQUEST_OWN_TRAVEL
                    }, status=status.HTTP_400_BAD_REQUEST)
                # No se debe permitir solicitar plaza en un viaje en el que ya tiene una plaza aceptada o pendiente
                if RequestTravels.objects.filter(id_travel__in=travel_ids, user=user, status__in=['accepted', 'pending', 'validated', 'unvalidated'], is_deleted=False).exists():
                    logger.warning(f"User {user.username} tried to request an already accepted travel {travel_ids}")
                    return Response({
                        "status": "error",
                        "message": "Ya has solicitado una plaza en alguno de uno estos viajes." if len(travel_ids) > 1 else "Ya has solicitado una plaza en este viaje.",
                        "error_code": ErrorCodes.ALREADY_REQUESTED
                    }, status=status.HTTP_400_BAD_REQUEST)

                travel_list = Travel.objects.filter(id_travel__in=travel_ids, is_deleted=False)

                # Se saca el estado pending para asignarlo a las nuevas solicitudes
                pending_state = RequestStates.objects.get(code='pending')

                requests_created = 0
                # Se crea la solicitud por cada uno de los viajes
                for travel in travel_list:
                    RequestTravels.objects.create(
                        id_travel=travel,
                        user=user,
                        status = pending_state
                    )
                    requests_created += 1
                    # Mensaje que se envia al dueño del viaje para notifiacarle que acaban de solicitar plaza en uno de sus viajes
                    msg = f"Tienes una nueva solicitud en el viaje {travel.origin} - {travel.destination}"

                    # Se crea la notificacion
                    Notifications.objects.create(
                        id_user=travel.creation_user,
                        content=msg,
                        is_deleted=False
                    )

                return Response({
                    "status": "ok",
                    "requests_created": requests_created,
                    "message": f"Se han creado {requests_created} solicitudes."
                }, status=status.HTTP_200_OK)

        except Travel.DoesNotExist: # Si no existe el viaje, se devuelve un error
            return Response({"status": "error", "message": "Viaje no encontrado", "error_code": ErrorCodes.TRAVEL_DONT_EXIST}, status=status.HTTP_404_NOT_FOUND)
        except Exception as e:
            logger.error(f"Error in request_travel: {str(e)}")
            return Response({"status": "error", "message": "Error interno del servidor, vuelve a intentarlo más tarde", "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


    @action(
        detail=True,
        methods=['patch'],
        url_path='change_pickup_points',
        permission_classes=[IsAuthenticated]
    )
    def change_pickup_points(self, request, *args, **kwargs):
        """
        Endpoint POST /travel/{id}/change_pickup_points/
        Cambia los puntos de recogida del viaje
        Recibe una lista de los puntos intermedios con su direccion, coordenadas, fecha y el orden en el viaje
        Devuelve un mensaje de exito o error
        """
        travel = self.get_object()

        logger.info(f"Request to change pickup points for travel {travel.id_travel} by user {request.user.username}")

        # Solo el creador del viaje puede modificar
        if travel.creation_user != request.user:
            return Response({
                "status": "error",
                "message": "No tienes permiso para modificar este viaje.",
                "error_code": ErrorCodes.INSUFICIENT_CREDENTIALS
            }, status=status.HTTP_403_FORBIDDEN)

        pickup_points = request.data.get('pickup_points', []) # Lista de puntos de recogida

        if not pickup_points:
            return Response({
                "status": "error",
                "message": "Se requiere una lista de puntos de recogida.",
                "error_code": ErrorCodes.MISSING_REQUIRED_FIELD
            }, status=status.HTTP_400_BAD_REQUEST)

        try:
            with transaction.atomic():

                if travel.is_periodic: # En un viaje periodico no se pueden modificar los puntos de recogida
                    logger.error(f"Error changing pickup points for periodic travel {travel.id_travel}.")
                    return Response({
                        "status": "error",
                        "message": "No se pueden modificar los puntos de recogida en un viaje periodico.",
                        "error_code": ErrorCodes.TRAVEL_IS_NOT_PUNCTUAL
                    }, status=status.HTTP_400_BAD_REQUEST)
                    # Tal y como se especifica en los requisitos de la memoria, actualmente no se puede modificar las paradas en los viajes periodicos
                    # @ TODO Si se deseara en un futuro, se podria hacer con el siguiente codigo

                    # Si es periodico, hay que hacerlo por cada uno de los viajes hijos
                    # Se saca el id del viaje padre, si es periodico
                    father_travel_id = travel.id_origin_travel.id_travel if travel.id_origin_travel else travel.id_travel
                    travels_to_update = Travel.objects.filter(id_origin_travel=father_travel_id, is_deleted=False)
                    # Se borran los que habia
                    PickUpPoints.objects.filter(id_travel__in=travels_to_update, is_deleted=False).update(is_deleted=True, deleted_at=timezone.now())

                    #Se añaden los nuevos puntos a cada uno de los viajes
                    for t in travels_to_update:
                        PickUpPoints.objects.bulk_create([
                            PickUpPoints(
                                id_travel=t,
                                direction=pp['direction'],
                                date= pp.get('date').date() if pp.get('date') and hasattr(pp.get('date'), 'date') else None,
                                order_in_travel=pp['order_in_travel'],
                                point=Point(float(pp['lng']), float(pp['lat']), srid=4326)
                            ) for pp in pickup_points
                        ])
                    logger.info(f"Changed pickup points for travel {travel.id_travel} and its periodic travels.")

                else: # Si no es periodico, solo se cambia en ese viaje
                # Se buscan los puntos de recogida antiguos y se marcan como borrados
                    PickUpPoints.objects.filter(id_travel=travel, is_deleted=False).update(is_deleted=True, deleted_at=timezone.now())
                    # Se crean los nuevos puntos de recogida
                    for pp in pickup_points:
                        PickUpPoints.objects.create(
                            id_travel=travel,
                            direction=pp.get('direction'),
                            date=pp.get('date'),
                            order_in_travel=pp.get('order_in_travel'),
                            point=Point(float(pp.get('lng')), float(pp.get('lat')), srid=4326)
                        )
                    logger.info(f"Changed pickup points for travel {travel.id_travel}.")

                return Response({
                    "status": "ok",
                    "message": "Los puntos de recogida se han actualizado correctamente."
                }, status=status.HTTP_200_OK)
        except Exception as e:
            logger.error(f"Error changing pickup points for travel {travel.id_travel}: {str(e)}")
            return Response({
                "status": "error",
                "message": "Error en el servidor, vuelve a intentarlo más tarde.",
                "error_code": ErrorCodes.INTERNAL_SERVER_ERROR
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    @action(
        detail=True,
        methods=['patch'],
        url_path='edit',
        permission_classes=[IsAuthenticated]
    )
    def edit(self, request, *args, **kwargs):
        """
        Endpoint POST /travel/{id}/edit/
        Modifica los datos del viaje
        Para cambiar de periódico a puntual, se requiere un parámetro 'delete_date' con la fecha a partir de la cual eliminar los viajes periódicos futuros.
        Para cambiar de puntual a periódico, se requieren los parámetros 'interval_days' (días entre viajes) y 'end_date' (fecha final de periodicidad).
        Devuelve un mensaje de exito o error
        """
        travel = self.get_object()
        # Hay que checkear si vienen las coordenadoas en el JSON, (si no ha cambiado de lugares no vienen)
        orig_lat = request.data.get('origin_lat')
        orig_lng = request.data.get('origin_lng')
        dest_lat = request.data.get('destination_lat')
        dest_lng = request.data.get('destination_lng')

        # El origen y el destino siempre vienen, aunque no cambien
        origin = request.data.get('origin')
        destination = request.data.get('destination')

        date_raw = request.data.get('travel_date')
        if date_raw:
            _parsed = parse_datetime(date_raw)
            date = make_aware(_parsed) if (_parsed and is_naive(_parsed)) else _parsed
        else:
            date = None

        # Indica el nuevo tipo de viaje (puede no haber cambiado)
        is_periodic = request.data.get('is_periodic')

        users_deny = request.data.get('users_deny', [])
        vehicle_id = request.data.get('vehicle_id')
        seats = request.data.get('seats')
        duration = request.data.get('duration')
        only_this_travel = request.data.get('only_this_travel', False)  # Indica si solo se quiere modificar este viaje o todos los futuros (en caso de ser periodico)

        logger.info(f"Request to edit travel {travel.id_travel} by user {request.user.username}")

        # Solo el creador del viaje puede modificar
        if travel.creation_user != request.user:
            return Response({
                "status": "error",
                "message": "No tienes permiso para modificar este viaje.",
                "error_code": ErrorCodes.INSUFICIENT_CREDENTIALS
            }, status=status.HTTP_403_FORBIDDEN)

        try:
            with transaction.atomic():
                if seats and seats < travel.num_seats and travel.is_periodic:
                    # No se puede reducir el numero de asientos si el viaje es periodico,
                    return Response({
                        "status": "error",
                        "message": f"No se puede reducir el número de asientos en un viaje periódico.",
                        "error_code": ErrorCodes.TRAVEL_IS_NOT_PUNCTUAL
                    }, status=status.HTTP_400_BAD_REQUEST)

                # Se sacan el numero de asientos ocupados
                if seats and seats != travel.num_seats:
                    ocupied_seats = travel.num_seats - travel.remaining_seats
                    travel.num_seats = seats if seats else travel.num_seats
                    if seats and ocupied_seats > seats: # Si intenta poner menos asientos que los ocupados, se devuelve error
                        return Response({
                            "status": "error",
                            "message": f"No se puede reducir el número de asientos a {seats} porque ya hay {ocupied_seats} plazas ocupadas.",
                            "error_code": ErrorCodes.SEATS_BELOW_OCCUPIED
                        }, status=status.HTTP_400_BAD_REQUEST)
                    # Se actualizan los nuevos asientos
                    travel.remaining_seats = seats - ocupied_seats if seats else travel.remaining_seats
                    travel.save()

                # Se debe tratar distinto si el viaje era periodico que si es puntual

                if travel.is_periodic:
                    # El viaje era periodico
                    # Se saca el id del padre, si el es el padre, es su propio id
                    father_travel_id = travel.id_origin_travel.id_travel if travel.id_origin_travel else travel.id_travel
                    
                    if only_this_travel:
                            # Solo aplica los cambios al viaje actual
                            travels_to_update = Travel.objects.filter(pk=travel.pk)
                    else:
                        # Aplica al viaje actual y a todos los futuros de su misma serie periodica
                        travels_to_update = Travel.objects.filter(
                            Q(id_origin_travel=father_travel_id) | Q(pk=father_travel_id),
                            travel_date__gte=travel.travel_date,
                            is_deleted=False
                        )
                    
                    # En los viajes periodicos, no se puede cambiar los usuarios denegados
                    if users_deny and users_deny != list(travel.users_denied.filter(is_deleted=False).values_list('user_type__code', flat=True)):
                        return Response({
                            "status": "error",
                            "message": f"No se puede cambiar los usuarios denegados en un viaje periódico.",
                            "error_code": ErrorCodes.TRAVEL_IS_NOT_PUNCTUAL
                        }, status=status.HTTP_400_BAD_REQUEST)


                    # Si se ha cambiado de vehiculo, se busca el nuevo y se añade a los viajes futuros
                    if vehicle_id and vehicle_id != str(travel.vehicle.id_vehicle):
                        vehicle = Vehicles.objects.filter(id_vehicle=vehicle_id, is_deleted=False)
                        if not vehicle: # Si no se encuentra se lanza error
                            return Response({
                                "status": "error",
                                "message": "Vehículo no encontrado.",
                                "error_code": ErrorCodes.VEHICLE_DONT_EXIST
                            }, status=status.HTTP_404_NOT_FOUND)

                        # Se comprueba que no se pueda cambiar a un vehiculo con menos asientos que el actual
                        if vehicle.first().seats - 1 < travel.num_seats:
                            return Response({
                                "status": "error",
                                "message": f"No se puede cambiar a este vehículo porque tiene menos asientos que el viaje actual.",
                                "error_code": ErrorCodes.VEHICLE_SEATS_INSUFFICIENT
                            }, status=status.HTTP_400_BAD_REQUEST)

                        travel.vehicle = vehicle.first()
                        travel.save()

                        if not only_this_travel:
                            has_invalid_travels = travels_to_update.filter(num_seats__gt=vehicle.first().seats - 1).exists()
                            if has_invalid_travels:
                                return Response({
                                    "status": "error",
                                    "message": f"No se puede cambiar a este vehículo en toda la serie periódica porque un viaje futuro tiene más asientos que el vehículo seleccionado.",
                                    "error_code": ErrorCodes.VEHICLE_SEATS_INSUFFICIENT
                                }, status=status.HTTP_400_BAD_REQUEST)

                        # Se actualiza el vehiculo en cada uno de los viajes hijos
                        travels_to_update.update(vehicle=travel.vehicle)
                        #Se notifica a los pasajeros de que ha cambiado su vehiculo
                        request_travels = RequestTravels.objects.filter(id_travel__in=travels_to_update.values_list('id_travel', flat=True), status='accepted', is_deleted=False)
                        for r in request_travels:
                            Notifications.objects.create(
                                id_user=r.user,
                                content=f"Se ha cambiado de vehiculo en el viaje {r.id_travel.origin} - {r.id_travel.destination} del dia {r.id_travel.travel_date.strftime('%d/%m/%Y')} revisa el viaje para ver los cambios"
                            )
                        logging.info(f"User {request.user.username} changed vehicle for travel {travel.id_travel} and futures. Notified the passengers of the change.")

                    # Se desea cambiarlo a puntual
                    if not is_periodic:
                        travels_to_update.update(is_periodic=False, periodic_interval=None, end_periodic_date=None, id_origin_travel=None)
                        logger.info(f"Changed travels {travels_to_update.values_list('id_travel', flat=True)} to punctual.")

                    return Response({
                        "status": "ok",
                        "message": "La modificación se ha realizado correctamente."
                    }, status=status.HTTP_200_OK)

                else: # El viaje era puntual

                    # Cambios de origen y destino (junto con sus coordenadas) Esto solo se permite en viajes puntuales
                    if (origin and origin != travel.origin) or (destination and destination != travel.destination):
                        travel.origin = origin if origin else travel.origin
                        travel.destination = destination if destination else travel.destination

                        if orig_lat and orig_lng:
                            travel.origin_point = Point(float(orig_lng), float(orig_lat), srid=4326)

                        if dest_lat and dest_lng:
                            travel.destination_point = Point(float(dest_lng), float(dest_lat), srid=4326)
                        # Se cambia la fecha del viaje
                        travel.travel_date = date if date else travel.travel_date
                        travel.save()

                    if duration and duration != travel.duration_minutes:
                        travel.duration_minutes = duration
                        travel.save()

                    if vehicle_id and vehicle_id != str(travel.vehicle.id_vehicle):
                    # Se cambia el vehiculo y se notifica a los pasajeros
                        vehicle = Vehicles.objects.filter(id_vehicle=vehicle_id, is_deleted=False)
                        if not vehicle:
                            return Response({
                                "status": "error",
                                "message": "Vehículo no encontrado.",
                                "error_code": ErrorCodes.VEHICLE_DONT_EXIST
                            }, status=status.HTTP_404_NOT_FOUND)
                        travel.vehicle = vehicle.first()
                        travel.save()
                        request_travels = RequestTravels.objects.filter(id_travel=travel.id_travel, status='accepted', is_deleted=False)
                        for r in request_travels:
                            Notifications.objects.create(
                                id_user=r.user,
                                content=f"Se ha cambiado de vehiculo en el viaje {r.id_travel.origin} - {r.id_travel.destination} del dia {r.id_travel.travel_date.strftime('%d/%m/%Y')} revisa el viaje para ver los cambios"
                            )
                    # Se actualiza la fecha del viaje si no hay plazas ocupadas
                    if date != travel.travel_date:
                        if travel.remaining_seats < travel.num_seats:
                            return Response({
                                "status": "error",
                                "message": f"No se puede cambiar la fecha del viaje porque ya hay plazas ocupadas.",
                                "error_code": ErrorCodes.SEATS_BELOW_OCCUPIED
                            }, status=status.HTTP_400_BAD_REQUEST)
                        travel.travel_date = date
                        travel.save()

                    # Si se desea cambiar los usuarios denegados, se borran los antiguos y se crean nuevos
                    if users_deny:
                        # Se busca los antiguos y se borran
                        users_deny_objs = UsersDenied.objects.filter(id_travel=travel, is_deleted=False)
                        for ud in users_deny_objs:
                            ud.is_deleted = True
                            ud.deleted_at = timezone.now()
                            ud.save()
                        # Se insertan los nuevos
                        for ud in users_deny:
                            UsersDenied.objects.create(
                                id_travel=travel,
                                user_type=UserType.objects.filter(code=ud).first()
                            )

                    # De puntual a periódico
                    if is_periodic:
                        interval = request.data.get('periodic_interval') # Dias entre los viajes
                        interval_days = int(interval) if interval else 0
                        end_date_str = request.data.get('end_periodic_date')
                        # Si uno de los parametros no viene se devuelve error
                        if not end_date_str:
                            logger.error("End date is required to change to periodic")
                            return Response({
                                "status": "error",
                                "message": "Se requiere fecha de finalización de periodicidad para cambiar a periódico.",
                                "error_code": ErrorCodes.TO_DATE_REQUIRED
                            }, status=status.HTTP_400_BAD_REQUEST)

                        if not interval_days or interval_days <= 0 or interval_days > 31:
                            logger.error("Interval days is required and must be between 1 and 31")
                            return Response({
                                "status": "error",
                                "message": "El intervalo de periodicidad es requerido y debe ser un número entre 1 y 31.",
                                "error_code": ErrorCodes.INVALID_PERIODIC_INTERVAL
                            }, status=status.HTTP_400_BAD_REQUEST)

                        end_date = parse_datetime(end_date_str) or parse_date(end_date_str)
                        # Si es un datetime, extraemos solo el date para que el bucle while no falle
                        if hasattr(end_date, 'date'):
                            end_date = end_date.date()

                        # Cambiar el viaje a periódico
                        travel.is_periodic = True
                        travel.periodic_interval = interval_days
                        travel.end_periodic_date = end_date
                        travel.save()

                        try:
                            active_state = TravelStates.objects.get(code='active')
                        except TravelStates.DoesNotExist:
                            logger.error("Active state with code 'active' not found in TravelStates")
                            return Response({
                                "status": "error",
                                "message": "Error al cargar el estado.",
                                "error_code": ErrorCodes.INTERNAL_SERVER_ERROR
                            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

                        # Generar las fechas para los nuevos viajes hijos
                        current_date = travel.travel_date + timedelta(days=interval_days)
                        new_travels = []

                        while current_date.date() <= end_date:
                            if timezone.is_naive(current_date):
                                current_date = timezone.make_aware(current_date)
                            # Se crean los hijos copiando al padre
                            new_travel = Travel(
                                id_origin_travel=travel,
                                travel_date=current_date,
                                origin=travel.origin,
                                destination=travel.destination,
                                origin_point=travel.origin_point,
                                duration_minutes=travel.duration_minutes,
                                destination_point=travel.destination_point,
                                num_seats=travel.num_seats,
                                remaining_seats=travel.num_seats,
                                creation_user=travel.creation_user,
                                vehicle=travel.vehicle,
                                state=active_state,
                                is_periodic=True,
                                periodic_interval=travel.periodic_interval,
                                end_periodic_date=travel.end_periodic_date
                            )
                            new_travels.append(new_travel)
                            current_date += timedelta(days=interval_days)

                        # Se guardan los viajes hijos
                        created_travels = Travel.objects.bulk_create(new_travels)

                        # Se copian los PickUpPoints y UsersDenied a los nuevos hijos generados
                        parent_pickups = PickUpPoints.objects.filter(id_travel=travel, is_deleted=False)
                        parent_denied = UsersDenied.objects.filter(id_travel=travel, is_deleted=False)

                        child_pickups = []
                        child_denied = []

                        for ct in created_travels:
                            for pp in parent_pickups:
                                child_pickups.append(PickUpPoints(
                                    id_travel=ct,
                                    direction=pp.direction,
                                    date=pp.date,
                                    order_in_travel=pp.order_in_travel,
                                    point=pp.point
                                ))

                            for du in parent_denied:
                                child_denied.append(UsersDenied(
                                    id_travel=ct,
                                    user_type=du.user_type
                                ))

                        if child_pickups:
                            PickUpPoints.objects.bulk_create(child_pickups)
                        if child_denied:
                            UsersDenied.objects.bulk_create(child_denied)

                        logger.info(f"Changed travel {travel.id_travel} to periodic. Created {len(created_travels)} new travels.")
                    return Response({
                        "status": "ok",
                        "message": f"La modificación se ha realizado correctamente."
                    }, status=status.HTTP_200_OK)
        except Exception as e:
            logger.error(f"Error changing the type of travel: {str(e)}")
            return Response({
                "status": "error",
                "message": "Error en el servidor, vuelve a intentarlo más tarde.",
                "error_code": ErrorCodes.INTERNAL_SERVER_ERROR
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


    @action(
        detail=True,
        methods=['get'],
        url_path='get_travel_details',
        permission_classes=[IsAuthenticated]
    )
    def get_travel_details(self, request, *args, **kwargs):
        """
        Endpoint GET /travel/{id}/get_travel_details/
        Obtiene los detalles de un viaje especificado por su id
        Devuelve un mapa con los datos del viaje
        """
        try:
            travel = Travel.objects.get(pk=self.kwargs['pk'])

            logger.info(f"Requesting details for travel {travel.id_travel}")
            want_travels = request.query_params.get("future_travels", "false").lower() == "true"
            user = travel.creation_user
            
            is_finished = travel.state.code == 'fnd'

            try:
                # Las valoraciones se obtienen mediante un stored procedure
                with connection.cursor() as cursor:
                    cursor.execute("SELECT code, avg_score, num_ratings FROM public.getdriverratings(%s)", [str(user.id)])
                    results = cursor.fetchall()

                next_travels = []
                requested_travel_ids = set()
                # Se sacan los puntos de recogida del viaje, ordenados por el orden establecido en el viaje
                pickup_popints = PickUpPoints.objects.filter(id_travel=travel, is_deleted=False).order_by('order_in_travel')
                pickup_serializer = PickUpPointSerializer(pickup_popints, many=True)
                preferences = PreferencesSerializer(user.preferences.all(), many=True)
                # Solo se deben sacar las solicitudes acepatadas (no borradas) o realizadas
                travel_requests = RequestTravels.objects.filter(
                    Q(status__code='accepted', is_deleted=False) |
                    Q(status__code__in=['validated', 'unvalidated']),
                    id_travel=travel
                ).select_related('user')
                # Se saca tambien el nombre de usuario de los pasajeros que han sido aceptados
                passengers_data = [
                    {
                        "username": req.user.username,
                        "profile_picture": req.user.profile_picture.name.split('/')[-1] if req.user.profile_picture else None
                    }
                    for req in travel_requests
                ]

                if want_travels: # Si se desea consultar tambien los proximos 5 viajes
                    id_origin = travel.id_origin_travel if travel.id_origin_travel else travel.id_travel
                    next_travels = Travel.objects.filter(id_origin_travel=id_origin, travel_date__gt=travel.travel_date, is_deleted=False).order_by('travel_date')[:5]
                    requested_travel_ids = set(
                        RequestTravels.objects.filter(
                            id_travel__in=next_travels,
                            user=request.user,
                            status__code__in=['accepted', 'pending', 'validated', 'unvalidated'],
                            is_deleted=False
                        ).values_list('id_travel', flat=True)
                    )

                # Se muestra que tipos de usuarios denegados tiene el viaje asociados
                users_denied = UsersDenied.objects.filter(id_travel=travel, is_deleted=False).select_related('user_type')
                denied_user_types = [ud.user_type.code for ud in users_denied]

                data = { # Se construye el mapa con los datos de los viajes
                    "ratings":{
                        "results": {
                            row[0]: float(row[1]) if row[1] is not None else None
                            for row in results
                        } if results else {},
                        "count": float(results[0][2]) if results and results[0][2] is not None else None,
                    },
                    "pickup_points": pickup_serializer.data,
                    "preferences": [pref["pref_type"] for pref in preferences.data],
                    "driver": {
                        "username": user.username,
                        "profile_picture": user.profile_picture.name.split('/')[-1] if user.profile_picture else None,
                    },
                    "passengers": passengers_data,
                    "is_requested" : RequestTravels.objects.filter(id_travel=travel.id_travel, user=request.user, status__code__in=['accepted', 'pending', 'validated', 'unvalidated'], is_deleted=False).exists(),
                    "denied_roles": denied_user_types,
                    "origin_lat": travel.origin_point.y if travel.origin_point else None,
                    "origin_lng": travel.origin_point.x if travel.origin_point else None,
                    "destination_lat": travel.destination_point.y if travel.destination_point else None,
                    "destination_lng": travel.destination_point.x if travel.destination_point else None,
                    "next_travels": {
                        str(t.id_travel): {
                            "id" : str(t.id_travel),
                            "travel_date": t.travel_date,
                            "remaining_seats": t.remaining_seats,
                            "is_requested": t.id_travel in requested_travel_ids,
                        } for t in next_travels
                    } if next_travels else {}
                }

                return Response(data, status=status.HTTP_200_OK)

            except Exception as e:
                logger.error(f"Error getting travel details: {str(e)}")
                return Response({"error": "Error retrieving travel details", "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=500)
        except Exception as e:
            logger.error(f"Error in get_travel_details: {str(e)}")
            return Response({"error": "Error retrieving travel details", "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=500)

    @action(
        detail=True,
        methods=['post'],
        url_path='remove_passenger',
        permission_classes=[IsAuthenticated]
    )
    def remove_passenger(self, request, *args, **kwargs):
        """
        Endpoint POST /travel/{id}/remove_passenger/
        Elimina un pasajero de un viaje especificado por su nombre de usuario
        Recibe el nombre de usuario del pasajero a eliminar y el id del usuario que hace la petición (debe ser el creador del viaje)
        Devuelve un mensaje de exito o error
        """
        travel = self.get_object()

        logger.info(f"Requesting to remove passenger from travel {travel.id_travel}")

        user_id = request.data.get('user_id')
        passenger_username = request.data.get('passenger')
        user = travel.creation_user

        # Los datos del id y el nombre de usuario son necesarios
        if not user_id or not passenger_username:
            logger.error("Missing user_id or passenger username in request data")
            return Response({
                "status": "error",
                "message": "Faltan parámetros necesarios.",
                "error_code": ErrorCodes.MISSING_REQUIRED_FIELD
            }, status=status.HTTP_400_BAD_REQUEST)

        # Solo el creador del viaje puede eliminar pasajeros
        if str(user.id) != str(user_id):
            logger.warning(f"User {request.user.username} tried to remove a passenger from travel {travel.id_travel} without being the creator")
            return Response({
                "status": "error",
                "message": "No tienes permiso para eliminar pasajeros de este viaje.",
                "error_code": ErrorCodes.INSUFICIENT_CREDENTIALS
            }, status=status.HTTP_403_FORBIDDEN)

        passenger = Users.objects.filter(username=passenger_username).first()
        # Si no existe el pasajero con ese nombre de usuario, se devuelve error
        if not passenger:
            logger.error(f"Passenger with username {passenger_username} not found")
            return Response({
                "status": "error",
                "message": "Pasajero no encontrado.",
                "error_code": ErrorCodes.USER_DONT_EXIST
            }, status=status.HTTP_400_BAD_REQUEST)

        try:
            with transaction.atomic():
                # Se saca l asolicitud del pasajero para ese viaje
                request_to_remove = RequestTravels.objects.get(id_travel=travel, user__id=passenger.id, status__code='accepted')
                request_to_remove.status = RequestStates.objects.get(code='rejected')
                request_to_remove.save()

                if travel.remaining_seats < travel.num_seats: #Solo se aumenta si no esta al maximo
                    travel.remaining_seats += 1
                travel.save()

                # Se notifica al pasajero que ha sido eliminado del viaje
                date = travel.travel_date.strftime("%d/%m/%Y %H:%M")
                Notifications.objects.create(
                    id_user=passenger,
                    content=f"Has sido eliminado del viaje {travel.origin} - {travel.destination} del dia {date}."
                )
                logger.info(f"Passenger with ID {passenger} removed from travel {travel.id_travel}. Remaining seats updated to {travel.remaining_seats}. Notification sent.")

            # Se le notifica que el chat del viaje ha sido eliminado para ese pasajero
            _notify_chat_removed(travel, passenger)

            return Response({
                    "status": "ok",
                    "message": "Pasajero eliminado del viaje. Asiento liberado."
                }, status=status.HTTP_200_OK)

        except Exception as e:
            logger.error(f"Error removing passenger from travel: {str(e)}")
            return Response({"error": "Error removing passenger from travel", "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=500)

    @action(
        detail=True,
        methods=['post'],
        url_path='validate_passenger',
        permission_classes=[IsAuthenticated]
    )
    def validate_passenger(self, request, *args, **kwargs):
        """
        Endpoint POST /travel/{id}/validate_passenger/
        Valida un pasajero del viaje mediante su codigo de validacion.
        Recibe el codigo del pasajero y actualiza su estado a 'validated'.
        """
        travel = self.get_object()
        code = request.data.get('code', '').strip()

        if not code:
            return Response({
                "status": "error",
                "message": "Se requiere un código de validación.",
                "error_code": ErrorCodes.MISSING_REQUIRED_FIELD
            }, status=status.HTTP_400_BAD_REQUEST)

        # Solo el creador del viaje puede validar pasajeros
        if travel.creation_user != request.user:
            return Response({
                "status": "error",
                "message": "No tienes permiso para validar pasajeros en este viaje.",
                "error_code": ErrorCodes.INSUFICIENT_CREDENTIALS
            }, status=status.HTTP_403_FORBIDDEN)

        try:
            # Se busca la solicitud con ese codigo de validacion que pertenezca a este viaje y este aceptada
            request_travel = RequestTravels.objects.get(
                id_travel=travel,
                validation_code=code,
                is_deleted=False
            )
            
            if request_travel.status.code == 'validated':
                # Si ya esta validado, se informa al usuario que ya ha sido validado
                logger.warning(f"Passenger {request_travel.user.username} already validated for travel {travel.id_travel}")
                return Response({
                    "status": "error",
                    "message": f"Pasajero {request_travel.user.username} ya ha sido validado.",
                    "error_code": ErrorCodes.PASSENGER_ALREADY_VALIDATED
                }, status=status.HTTP_400_BAD_REQUEST)
            # Si la solicitud no esta aceptada, no se puede validar
            if request_travel.status.code != 'accepted':
                logger.warning(f"Passenger {request_travel.user.username} has status {request_travel.status.code} and cannot be validated for travel {travel.id_travel}")
                return Response({
                    "status": "error",
                    "message": f"Pasajero {request_travel.user.username} no está en estado aceptado y no puede ser validado.",
                    "error_code": ErrorCodes.PASSENGER_NOT_ACCEPTED
                }, status=status.HTTP_400_BAD_REQUEST)
            # Se actualiza el estado a validado
            validated_state = RequestStates.objects.get(code='validated')
            request_travel.status = validated_state
            request_travel.save()

            logger.info(f"Passenger {request_travel.user.username} validated for travel {travel.id_travel} with code {code}")

            return Response({
                "status": "ok",
                "message": f"Pasajero {request_travel.user.username} validado correctamente."
            }, status=status.HTTP_200_OK)

        except RequestTravels.DoesNotExist:
            logger.warning(f"Validation code {code} not found for travel {travel.id_travel}")
            return Response({
                "status": "error",
                "message": "Código de validación no válido o pasajero no encontrado.",
                "error_code": ErrorCodes.INVALID_VALIDATION_CODE
            }, status=status.HTTP_404_NOT_FOUND)
        except Exception as e:
            logger.error(f"Error validating passenger: {str(e)}")
            return Response({
                "status": "error",
                "message": "Error en el servidor, vuelve a intentarlo más tarde.",
                "error_code": ErrorCodes.INTERNAL_SERVER_ERROR
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    @action(
        detail=True,
        methods=['post'],
        url_path='finish_travel',
        permission_classes=[IsAuthenticated]
    )
    def finish_travel(self, request, *args, **kwargs):
        """
        Endpoint POST /travel/{id}/finish_travel/
        Finaliza el viaje: cambia el estado a 'fnd' y marca como 'unvalidated'
        a los pasajeros que no hayan sido validados durante el viaje.
        """
        travel = self.get_object()

        # Solo el creador del viaje puede finalizarlo
        if travel.creation_user != request.user:
            return Response({
                "status": "error",
                "message": "No tienes permiso para finalizar este viaje.",
                "error_code": ErrorCodes.INSUFICIENT_CREDENTIALS
            }, status=status.HTTP_403_FORBIDDEN)

        try:
            with transaction.atomic():
                # Se cambia el estado del viaje a finalizado
                fnd_state = TravelStates.objects.get(code='fnd')
                travel.state = fnd_state
                travel.save()

                # Se buscan las solicitudes aceptadas (no validadas) y se marcan como unvalidated
                unvalidated_state = RequestStates.objects.get(code='unvalidated')
                unvalidated_requests = RequestTravels.objects.filter(
                    id_travel=travel,
                    status__code='accepted',
                    is_deleted=False
                )

                unvalidated_count = 0
                for req in unvalidated_requests:
                    req.status = unvalidated_state
                    req.save()
                    unvalidated_count += 1
                    # Se notifica al pasajero que no fue validado
                    Notifications.objects.create(
                        id_user=req.user,
                        content=f"El viaje {travel.origin} - {travel.destination} ha finalizado. Tu asistencia no fue validada por el conductor."
                    )

                logger.info(f"Travel {travel.id_travel} finished. {unvalidated_count} passengers marked as unvalidated.")
                
                # Se buscan las solicitudes validadas para enviarles la notificacion de que su viaje ha terminado y pueden puntuar al conductor
                validated_requests = RequestTravels.objects.filter(
                    id_travel=travel,
                    status__code='validated',
                    is_deleted=False
                )
                
                for req in validated_requests:
                    Notifications.objects.create(
                        id_user=req.user,
                        content=f"El viaje {travel.origin} - {travel.destination} ha finalizado. Puedes puntuar al conductor."
                    )
                
                logger.info(f"Notifications sent to {validated_requests.count()} validated passengers for travel {travel.id_travel}.")

                return Response({
                    "status": "ok",
                    "message": f"Viaje finalizado. {unvalidated_count} pasajeros no validados."
                }, status=status.HTTP_200_OK)

        except Exception as e:
            logger.error(f"Error finishing travel: {str(e)}")
            return Response({
                "status": "error",
                "message": "Error en el servidor, vuelve a intentarlo más tarde.",
                "error_code": ErrorCodes.INTERNAL_SERVER_ERROR
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    @action(
        detail=True,
        methods=['post'],
        url_path='reached_pickup_point',
        permission_classes=[IsAuthenticated]
    )
    def reached_pickup_point(self, request, *args, **kwargs):
        """
        Endpoint POST /travel/{id}/reached_pickup_point/
        Marca un punto de recogida como pasado por el.
        """
        travel = self.get_object()
        point_id = request.data.get('id_point')

        try:
            point = PickUpPoints.objects.get(id_point=point_id, id_travel=travel)
            point.is_reached = True
            point.save()
            return Response({
                "status": "ok",
                "message": "Punto de recogida marcado como alcanzado."
            }, status=status.HTTP_200_OK)
        except PickUpPoints.DoesNotExist:
            return Response({
                "status": "error",
                "message": "Punto de recogida no encontrado.",
                "error_code": ErrorCodes.PICKUP_POINT_NOT_FOUND
            }, status=status.HTTP_400_BAD_REQUEST)

# Endpoint para gestionar los estados de las solicitudes
class RequestStatesViewSet(SoftDeleteQuerysetMixin, viewsets.ModelViewSet):
    queryset = RequestStates.objects.all()
    serializer_class = RequestStatesSerializer
    permission_classes = [IsAuthenticated]

# Endpoints para gestionar las solicitudes de los viajes
class RequestTravelsViewSet(SoftDeleteQuerysetMixin, viewsets.ModelViewSet):
    queryset = RequestTravels.objects.all()
    serializer_class = RequestTravelsSerializer
    permission_classes = [IsAuthenticated]
    
    def destroy(self, request, *args, **kwargs):
        """
        Endpoint DELETE /requesttravels/{id}/
        Elimina una solicitud de viaje especificada por su id
        """
        try:
            with transaction.atomic():
                instance = self.get_object()
                # Solo el usuario que hizo la solicitud o el creador del viaje puede eliminarla
                if instance.user != request.user and instance.id_travel.creation_user != request.user:
                    return Response({
                        "status": "error",
                        "message": "No tienes permiso para eliminar esta solicitud.",
                        "error_code": ErrorCodes.INSUFICIENT_CREDENTIALS
                    }, status=status.HTTP_403_FORBIDDEN)
                
                if instance.status.code == 'accepted':
                    # Si la solicitud estaba aceptada, se debe liberar un asiento en el viaje
                    travel = instance.id_travel
                    if travel.remaining_seats < travel.num_seats: #Solo se aumenta si no esta al maximo
                        travel.remaining_seats += 1
                        travel.save()
                        logger.info(f"Seat released for travel {travel.id_travel} due to deletion of accepted request.")
                        Notifications.objects.create(
                            id_user=travel.creation_user,
                            content=f"Un pasajero ha cancelado su solicitud para el viaje {travel.origin} - {travel.destination}. Se ha liberado un asiento."
                        )    
        
            self.perform_destroy(instance)
            return Response({
                "status": "ok",
                "message": "Solicitud eliminada correctamente."
            }, status=status.HTTP_200_OK)
        except Exception as e:
            logger.error(f"Error deleting request travel: {str(e)}")
            return Response({
                "status": "error",
                "message": "Error en el servidor, vuelve a intentarlo más tarde.",
                "error_code": ErrorCodes.INTERNAL_SERVER_ERROR
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    # Se sobreescribe el metodo PATCH para que se pueda gestionar bien la aprobacion y rechazo de las solicitudes
    def partial_update(self, request, *args, **kwargs):
        instance = self.get_object()
        new_status_code = request.data.get('status')
        
        if new_status_code: # Si se ha cambiado el estado de la solicitud
            
            try:
                travel = instance.id_travel
                
                with transaction.atomic():
                    current_status = instance.status.code
                    new_status_obj = RequestStates.objects.get(code=new_status_code)
                    
                    if request.user != travel.creation_user: # Solo el creador puede aceptar o rechazar una solicitud
                            logger.warning(f"User {request.user.username} tried to change status of request {instance.id} without proper credentials.")
                            return Response({
                                "status": "error",
                                "message": "No tienes permiso para cambiar el estado de esta solicitud.",
                                "error_code": ErrorCodes.INSUFICIENT_CREDENTIALS
                            }, status=status.HTTP_403_FORBIDDEN)

                    # En caso de que se apruebe la solicitud
                    if current_status == 'pending' and new_status_code == 'accepted':               
                        # Solo se puede aceptar si quedan espacios disponibles
                        if travel.remaining_seats > 0:
                            travel.remaining_seats -= 1
                            travel.save()

                            # Se genera un codigo de validacion para el pasajero
                            validation_code = ''.join(random.choices(string.ascii_uppercase + string.digits, k=8))
                            # Se asegura que el codigo sea unico
                            while RequestTravels.objects.filter(id_travel=travel.id_travel, validation_code=validation_code, is_deleted=False).exists():
                                validation_code = ''.join(random.choices(string.ascii_uppercase + string.digits, k=8))
                            instance.validation_code = validation_code

                            Notifications.objects.create(
                                id_user=instance.user,
                                content=f"Tu solicitud para el viaje {instance.id_travel.origin} - {instance.id_travel.destination} ha sido aceptada. Tu código de validación es: {validation_code}"
                            )
                        else:
                            return Response({
                                "status": "error",
                                "message": "El viaje ya está completo. No puedes aceptar más pasajeros.",
                                "error_code": ErrorCodes.TRAVEL_IS_FULL
                            }, status=status.HTTP_400_BAD_REQUEST)

                    # Si la solicitud estaba aceptada, pero se elimina
                    elif current_status == 'accepted' and new_status_code in ['rejected']:
                        
                        travel.remaining_seats += 1
                        travel.save()
                        
                        #Eliminan al pasajero, por lo que se le notifica
                        Notifications.objects.create(
                            id_user=instance.user,
                            content=f"El creador del viaje {instance.id_travel.origin} - {instance.id_travel.destination} te ha eliminado del viaje."
                        )
                    # Si estaba pendiente y se rechaza
                    elif current_status == 'pending' and new_status_code == 'rejected':
                        # Se notifica al usuario de que le han rechazado la solicitud
                        Notifications.objects.create(
                            id_user=instance.user,
                            content=f"Tu solicitud para el viaje {instance.id_travel.origin} - {instance.id_travel.destination} ha sido rechazada."
                        )

                    instance.status = new_status_obj
                    instance.save()

                    return Response({
                        "status": "ok",
                        "message": f"Solicitud marcada como {new_status_code}"
                    }, status=status.HTTP_200_OK)

            except RequestStates.DoesNotExist as e:
                logger.error(f"Error Status code {new_status_code} invalid: {str(e)}")
                return Response({"status": "error", "message": "Código de estado inválido.", "error_code": ErrorCodes.INVALID_REQUEST_STATUS}, status=status.HTTP_400_BAD_REQUEST)
            except Exception as e:
                logger.error(f"Error: {str(e)}")
                return Response({"status": "error", "message": str(e), "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

        return super().partial_update(request, *args, **kwargs)

# Endpoints para gestionar los puntos de recogida
class PickUpPointsViewSet(SoftDeleteQuerysetMixin, viewsets.ModelViewSet):
    queryset = PickUpPoints.objects.all()
    serializer_class = PickUpPointSerializer
    permission_classes = [IsAuthenticated]

    # Se sobreescribe el metodo POST para permitir la creacion de varios puntos de recogida
    def create(self, request, *args, **kwargs):

        # Se comprueba si se ha pasado una lista o un solo objeto para crear varios o solo uno
        is_many = isinstance(request.data, list)

        serializer = self.get_serializer(data=request.data, many=is_many)

        # Si es valido, se crea si no se debe lazar excepcion
        serializer.is_valid(raise_exception=True)

        self.perform_create(serializer)

        headers = self.get_success_headers(serializer.data)
        return Response(
            serializer.data,
            status=status.HTTP_201_CREATED,
            headers=headers
        )

# Endpoint para gestionar los usuarios denegados en los viajes
class UsersDeniedViewSet(SoftDeleteQuerysetMixin, viewsets.ModelViewSet):
    queryset = UsersDenied.objects.all()
    serializer_class = UsersDeniedSerializer
    permission_classes = [IsAuthenticated]

    # Se sobreescribe el metodo POST para permitir la creacion de varios usuarios denegados a la vez
    def create(self, request, *args, **kwargs):

       # Se comprueba si se ha pasado una lista o un solo objeto para crear varios o solo uno
        is_many = isinstance(request.data, list)

        serializer = self.get_serializer(data=request.data, many=is_many)

        # Se valida y si hay algun error, se lanza excepcion
        serializer.is_valid(raise_exception=True)

        self.perform_create(serializer)

        headers = self.get_success_headers(serializer.data)

        return Response(
            serializer.data,
            status=status.HTTP_201_CREATED,
            headers=headers
        )
