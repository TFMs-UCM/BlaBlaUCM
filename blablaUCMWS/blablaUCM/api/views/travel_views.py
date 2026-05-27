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
from django.db.models import Q
from datetime import datetime, timedelta
from django.utils.dateparse import parse_datetime, parse_date
from api.soft_delete import SoftDeleteQuerysetMixin

# Logger para ir almacenando los logs
logger = logging.getLogger(__name__)
    
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
        rad_orig = data.get('radius_origin_km', 0.0)
        rad_dest = data.get('radius_dest_km', 0.0)
       
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
            # 1. Crear los puntos espaciales
            orig_pt = Point(orig_lng, orig_lat, srid=4326)
            dest_pt = Point(dest_lng, dest_lat, srid=4326)

            # 2. Iniciar el QuerySet base (excluyendo al usuario actual)
            travels = self.get_queryset().exclude(creation_user=request.user).exclude(remaining_seats__lt=1).filter(state='active')

            # Filtros de distancia
            if rad_orig > 0:
                travels = travels.filter(origin_point__distance_lte=(orig_pt, D(km=rad_orig)))
            if rad_dest > 0:
                travels = travels.filter(destination_point__distance_lte=(dest_pt, D(km=rad_dest)))

            travels = travels.annotate(
                dist_origin=Distance('origin_point', orig_pt),
                dist_dest=Distance('destination_point', dest_pt)
            )
            
            logger.debug(f"Travel IDs after excluding own travels: {[str(t.id_travel) for t in travels]}")
            
            # Se excluyen los viajes que deniegan el rol del usuario
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
            if sort_by == 'origin':
                travels = travels.order_by('dist_origin')
            elif sort_by == 'destination':
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
            return Response({'status': 'error', 'message': str(e)}, status=500)
        
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
                        "message": "No puedes solicitar una plaza en tu propio viaje."
                    }, status=status.HTTP_400_BAD_REQUEST)
                # No se debe permitir solicitar plaza en un viaje en el que ya tiene una plaza aceptada o pendiente
                if RequestTravels.objects.filter(id_travel__in=travel_ids, user=user, status__in=['accepted', 'pending', 'validated', 'unvalidated'], is_deleted=False).exists():
                    logger.warning(f"User {user.username} tried to request an already accepted travel {travel_ids}")
                    return Response({
                        "status": "error",
                        "message": "Ya has solicitado una plaza en alguno de uno estos viajes." if len(travel_ids) > 1 else "Ya has solicitado una plaza en este viaje."
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
            return Response({"status": "error", "message": "Viaje no encontrado"}, status=status.HTTP_404_NOT_FOUND)
        except Exception as e:
            logger.error(f"Error in request_travel: {str(e)}")
            return Response({"status": "error", "message": "Error interno del servidor, vuelve a intentarlo más tarde"}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
    
    
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
                "message": "No tienes permiso para modificar este viaje."
            }, status=status.HTTP_403_FORBIDDEN)
        
        pickup_points = request.data.get('pickup_points', []) # Lista de puntos de recogida
        
        if not pickup_points:
            return Response({
                "status": "error", 
                "message": "Se requiere una lista de puntos de recogida."
            }, status=status.HTTP_400_BAD_REQUEST)
        
        try:
            with transaction.atomic():
                
                if travel.is_periodic: # En un viaje periodico no se pueden modificar los puntos de recogida
                    logger.error(f"Error changing pickup points for periodic travel {travel.id_travel}.")
                    return Response({
                        "status": "error", 
                        "message": "No se pueden modificar los puntos de recogida en un viaje periodico."
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
                "message": "Error en el servidor, vuelve a intentarlo más tarde."
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
        if(request.data.get('origin_lat', {})):
            orig_lat = request.data.get('origin_lat', {})
        if(request.data.get('origin_lng', {})):
            orig_lng = request.data.get('origin_lng', {})
        
        # El origen y el destino siempre vienen, aunque no cambien
        origin = request.data.get('origin')
        destination = request.data.get('destination')
        
        if(request.data.get('destination_lat', {})):
            dest_lat = request.data.get('destination_lat', {})
        if(request.data.get('destination_lng', {})):
            dest_lng = request.data.get('destination_lng', {})
            
        date = request.data.get('travel_date')
        
        # Indica el nuevo tipo de viaje (puede no haber cambiado)
        is_periodic = request.data.get('is_periodic')
       
        users_deny = request.data.get('users_deny', [])
        vehicle_id = request.data.get('vehicle_id')
        seats = request.data.get('seats')
        duration = request.data.get('duration')
        
        logger.info(f"Request to edit travel {travel.id_travel} by user {request.user.username}")
        
        # Solo el creador del viaje puede modificar
        if travel.creation_user != request.user:
            return Response({
                "status": "error", 
                "message": "No tienes permiso para modificar este viaje."
            }, status=status.HTTP_403_FORBIDDEN)

        try: 
            with transaction.atomic():
                if seats and seats < travel.num_seats and travel.is_periodic: 
                    # No se puede reducir el numero de asientos si el viaje es periodico,
                    return Response({
                        "status": "error", 
                        "message": f"No se puede reducir el número de asientos en un viaje periódico."
                    }, status=status.HTTP_400_BAD_REQUEST)
                    
                # Se sacan el numero de asientos ocupados
                if seats and seats != travel.num_seats:
                    ocupied_seats = travel.num_seats - travel.remaining_seats
                    travel.num_seats = seats if seats else travel.num_seats
                    if seats and ocupied_seats > seats: # Si intenta poner menos asientos que los ocupados, se devuelve error
                        return Response({
                            "status": "error", 
                            "message": f"No se puede reducir el número de asientos a {seats} porque ya hay {ocupied_seats} plazas ocupadas."
                        }, status=status.HTTP_400_BAD_REQUEST)
                    # Se actualizan los nuevos asientos
                    travel.remaining_seats = seats - ocupied_seats if seats else travel.remaining_seats
                    travel.save()
                
                # Se debe tratar distinto si el viaje era periodico que si es puntual
                
                if travel.is_periodic:  
                    # El viaje era periodico
                    # En los viajes periodicos, no se puede cambiar los usuarios denegados
                    if users_deny:
                        return Response({
                            "status": "error", 
                            "message": f"No se puede cambiar los usuarios denegados en un viaje periódico."
                        }, status=status.HTTP_400_BAD_REQUEST)
                    
                    # Se saca el id del padre, si el es el padre, es su propio id
                    father_travel_id = travel.id_origin_travel.id_travel if travel.id_origin_travel else travel.id_travel
                    
                    # Si se ha cambiado de vehiculo, se busca el nuevo y se añade a los viajes futuros
                    if vehicle_id and vehicle_id != str(travel.vehicle.id_vehicle):
                        vehicle = Vehicles.objects.filter(id_vehicle=vehicle_id, is_deleted=False)
                        if not vehicle: # Si no se encuentra se lanza error
                            return Response({
                                "status": "error", 
                                "message": "Vehículo no encontrado."
                            }, status=status.HTTP_404_NOT_FOUND)
                            
                        travel.vehicle = vehicle.first()
                        travel.save()
                        # Se sacan los viajes hijos futuros
                        child_travels = Travel.objects.filter(
                            id_origin_travel=father_travel_id, 
                            travel_date__gte=travel.travel_date,
                            is_deleted=False
                        )
                        # Se actualiza el vehiculo en cada uno de los viajes hijos
                        for ct in child_travels:
                            ct.vehicle = travel.vehicle
                            ct.save()
                        #Se notifica a los pasajeros de que ha cambiado su vehiculo
                        request_travels = RequestTravels.objects.filter(id_travel__in=child_travels.values_list('id_travel', flat=True), status='accepted', is_deleted=False)
                        for r in request_travels:
                            Notifications.objects.create(
                                id_user=r.user,
                                content=f"Se ha cambiado de vehiculo en el viaje {r.id_travel.origin} - {r.id_travel.destination} del dia {r.id_travel.travel_date.strftime('%d/%m/%Y')} revisa el viaje para ver los cambios"
                            )
                        logging.info(f"User {request.user.username} changed vehicle for travel {travel.id_travel} and futures. Notified the passengers of the change.")
                    
                    # Se desea cambiarlo a puntual, por lo que se procede a cambiar a puntual el viaje y a eliminar los viajes que sean futuros a la fecha indicada
                    if not is_periodic:
                        # Si se pasa a puntual, es necesario pasarle la fecha de finalizacion de periodicidad
                        delete_from_date_str = request.data.get('periodic_remove_date')
                        if not delete_from_date_str: # Si no la tiene, se pone la fecha de fin de periodicidad (no se borrara ningun viaje, se pasan a periodico todos)
                            delete_from_date = travel.end_periodic_date if travel.end_periodic_date else travel.travel_date
                        
                        # Se parsea la fecha para que no de errores
                        delete_from_date = parse_datetime(delete_from_date_str) or parse_date(delete_from_date_str)
                        # Si es un datetime, se extrae solo el date
                        if hasattr(delete_from_date, 'date'):
                            delete_from_date = delete_from_date.date()

                        # Cambiar el viaje padre a puntual
                        #Se saca el viaje padre
                        father_travel = Travel.objects.filter(id_travel=father_travel_id).first()
                        
                        father_travel.is_periodic = False
                        father_travel.periodic_interval = None
                        father_travel.end_periodic_date = None
                        father_travel.save()
                        # Despeus de cambiar al padre, se cambia a todos sus hijos
                        # Buscar viajes hijos anteriores a la fecha para modificarlos
                        child_travels= Travel.objects.filter(
                            id_origin_travel=father_travel_id, 
                            travel_date__lt=delete_from_date,
                            is_periodic=True, # Solo afecta a los hijos periodicos, si uno es puntual no le afecta
                            is_deleted=False
                        )
                        
                        child_travels.update(
                            is_periodic=False,
                            periodic_interval=None,
                            end_periodic_date=None,
                            # Se mantiene la referencia del padre 
                            #id_origin_travel=None
                        )
                        
                        child_travels_to_delete = Travel.objects.filter(
                            id_origin_travel=father_travel_id, 
                            travel_date__gte=delete_from_date,
                            is_periodic=True, # Solo afecta a los hijos periodicos, si uno es puntual no le afecta
                            is_deleted=False
                        )
                        
                        # Se marcan como borrado los hijos futuros a la fecha indicada
                        child_travels_to_delete.update(
                            is_deleted=True, 
                            deleted_at=timezone.now()
                        )
                        
                        # Se sacan los ids de los viajes a borrar 
                        child_travels_to_delete_ids = child_travels_to_delete.values_list('id_travel', flat=True)
                        
                        # Se eliminan los puntos de recogida y usuario denegados asociados a esos viajes
                        # Se eliminan mediante un procedure en bbdd, (sp_delete_travels) si en un futuro se desea eliminar aqui, se descomenta estas lineas
                        # PickUpPoints.objects.filter(id_travel__in=child_travels_to_delete_ids, is_deleted=False).update(is_deleted=True, deleted_at=timezone.now())
                        # UsersDenied.objects.filter(id_travel__in=child_travels_to_delete_ids, is_deleted=False).update(is_deleted=True, deleted_at=timezone.now())
                        # logger.info(f"PickUpPoints and UsersDenied associated with the travels {child_travels_to_delete_ids} marked as deleted.")
                        
                        # Se eliminan las solicitudes asociadas a esos viajes
                        requests = RequestTravels.objects.filter(id_travel__in=child_travels_to_delete_ids, is_deleted=False)
                        for r in requests:
                            r.is_deleted = True
                            r.deleted_at = timezone.now()
                            r.save()   
                            Notifications.objects.create(
                                id_user=r.user,
                                content=f"El viaje {r.id_travel.origin} - {r.id_travel.destination} del dia {r.id_travel.travel_date.strftime('%d/%m/%Y')} ha sido eliminado"
                            )
                            
                        logger.info(f"Changed travel {travel.id_travel} to punctual. Soft-deleted {child_travels.count()} future periodic travels.")
                    
                    return Response({
                        "status": "ok", 
                        "message": "La modificación se ha realizado correctamente."
                    }, status=status.HTTP_200_OK)
                    
                else: # El viaje era puntual
                    
                    # Cambios de origen y destino (junto con sus coordenadas) Esto solo se permite en viajes puntuales
                    if (origin and origin != travel.origin) or (destination and destination != travel.destination):
                        travel.origin = origin if origin else travel.origin
                        travel.destination = destination if destination else travel.destination
                        
                        if(request.data.get('origin_lat') and request.data.get('origin_lng')):
                            travel.origin_point = Point(float(orig_lng), float(orig_lat), srid=4326)
                            
                        if(request.data.get('destination_lat') and request.data.get('destination_lng')):
                            travel.destination_point = Point(float(dest_lng), float(dest_lat), srid=4326)
                        # Cambio de la fecha del viaje
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
                                "message": "Vehículo no encontrado."
                            }, status=status.HTTP_404_NOT_FOUND)
                        travel.vehicle = vehicle.first()
                        travel.save()
                        request_travels = RequestTravels.objects.filter(id_travel=travel.id_travel, status='accepted', is_deleted=False)
                        for r in request_travels:
                            Notifications.objects.create(
                                id_user=r.user,
                                content=f"Se ha cambiado de vehiculo en el viaje {r.id_travel.origin} - {r.id_travel.destination} del dia {r.id_travel.travel_date.strftime('%d/%m/%Y')} revisa el viaje para ver los cambios"
                            )
                    
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
                        interval_days = int(request.data.get('periodic_interval'), 0) # Por defecto 0, si es 0 se lanza error 
                        end_date_str = request.data.get('end_periodic_date')
                        # Si uno de los parametros no viene se devuelve error
                        if not end_date_str:
                            logger.error("End date is required to change to periodic")
                            return Response({
                                "status": "error", 
                                "message": "Se requiere fecha de finalización de periodicidad para cambiar a periódico."
                            }, status=status.HTTP_400_BAD_REQUEST)
                            
                        if not interval_days or interval_days <= 0 or interval_days > 31:
                            logger.error("Interval days is required and must be between 1 and 31")
                            return Response({
                                "status": "error", 
                                "message": "El intervalo de periodicidad es requerido y debe ser un número entre 1 y 31."
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
                                "message": "Error al cargar el estado."
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
                "message": "Error en el servidor, vuelve a intentarlo más tarde."
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
        travel = self.get_object()
        
        logger.info(f"Requesting details for travel {travel.id_travel}")
        want_travels = request.query_params.get("future_travels", "false").lower() == "true"
        user = travel.creation_user
        
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
            # Solo se deben sacar las solicitudes acepatadas o realizadas
            requests = RequestTravels.objects.filter(id_travel=travel, status__code__in=['accepted', 'validated', 'unvalidated']).select_related('user')
            # Se saca tambien el nombre de usuario de los pasajeros que han sido aceptados
            passengers = [request.user.username for request in requests]
            
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
                "passengers": passengers,
                "is_requested" : request.user.username in passengers, 
                "denied_roles": denied_user_types,
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
            return Response({"error": "Error retrieving travel details"}, status=500)
        
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
                "message": "Faltan parámetros necesarios."
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Solo el creador del viaje puede eliminar pasajeros
        if str(user.id) != str(user_id):
            logger.warning(f"User {request.user.username} tried to remove a passenger from travel {travel.id_travel} without being the creator")
            return Response({
                "status": "error", 
                "message": "No tienes permiso para eliminar pasajeros de este viaje."
            }, status=status.HTTP_403_FORBIDDEN)
        
        passenger = Users.objects.filter(username=passenger_username).first()
        # Si no existe el pasajero con ese nombre de usuario, se devuelve error
        if not passenger:
            logger.error(f"Passenger with username {passenger_username} not found")
            return Response({
                "status": "error", 
                "message": "Pasajero no encontrado."
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
                return Response({
                        "status": "ok", 
                        "message": "Pasajero eliminado del viaje. Asiento liberado."
                    }, status=status.HTTP_200_OK)
        
        except Exception as e:
            logger.error(f"Error removing passenger from travel: {str(e)}")
            return Response({"error": "Error removing passenger from travel"}, status=500)
        

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
    
    # Se sobreescribe el metodo PATCH para que se pueda gestionar bien la aprobacion y rechazo de las solicitudes
    def partial_update(self, request, *args, **kwargs):
        instance = self.get_object()
        new_status_code = request.data.get('status')

        if new_status_code: # Si se ha cambiado el estado de la solicitud
            try:
                with transaction.atomic():
                    current_status = instance.status.code
                    new_status_obj = RequestStates.objects.get(code=new_status_code)

                    # En caso de que se apruebe la solicitud
                    if current_status == 'pending' and new_status_code == 'accepted':
                        travel = instance.id_travel
                        
                        # Solo se puede aceptar si quedan espacios disponibles
                        if travel.remaining_seats > 0:
                            travel.remaining_seats -= 1
                            Notifications.objects.create(
                                id_user=instance.user,
                                content=f"Tu solicitud para tu viaje {instance.id_travel.origin} - {instance.id_travel.destination} ha sido aceptada."
                            )
                            travel.save()
                        else:
                            return Response({
                                "status": "error", 
                                "message": "El viaje ya está completo. No puedes aceptar más pasajeros."
                            }, status=status.HTTP_400_BAD_REQUEST)

                    # Si la solicitud estaba aceptada, pero se elimina
                    elif current_status == 'accepted' and new_status_code in ['rejected']:
                        travel = instance.id_travel
                        travel.remaining_seats += 1
                        travel.save()
                        # Se notifica al creador del viaje de que uno de los pasajeros lo ha abandonado
                        Notifications.objects.create(
                            id_user=instance.id_travel.creation_user,
                            content=f"Un usuario ha abandorado tu viaje {instance.id_travel.origin} - {instance.id_travel.destination}."
                        )
                    # Si estaba pendiente y se rechaza
                    elif current_status == 'pending' and new_status_code == 'rejected':
                        # Se notifica al usuario de que le han rechazado la solicitud
                        Notifications.objects.create(
                            id_user=instance.user,
                            content=f"Tu solicitud para tu viaje {instance.id_travel.origin} - {instance.id_travel.destination} ha sido rechazada."
                        )
                       
                    instance.status = new_status_obj
                    instance.save()

                    return Response({
                        "status": "ok", 
                        "message": f"Solicitud marcada como {new_status_code}"
                    }, status=status.HTTP_200_OK)

            except RequestStates.DoesNotExist as e:
                logger.error(f"Error Status code {new_status_code} invalid: {str(e)}")
                return Response({"status": "error", "message": "Código de estado inválido."}, status=status.HTTP_400_BAD_REQUEST)
            except Exception as e:
                logger.error(f"Error: {str(e)}")
                return Response({"status": "error", "message": str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

        # Si no nos envían 'status', dejamos que Django siga su flujo normal
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