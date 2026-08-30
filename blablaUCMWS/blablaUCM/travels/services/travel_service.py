import logging
import random
import string
from datetime import datetime, timedelta

from django.contrib.gis.db.models.functions import Distance
from django.contrib.gis.geos import Point
from django.contrib.gis.measure import D
from django.db import transaction
from django.db.models import (Count, DateTimeField, Exists, ExpressionWrapper, F, Max, Min, OuterRef, Q)
from django.template.defaultfilters import date as django_date
from django.utils import timezone
from django.utils.dateparse import parse_date, parse_datetime
from django.utils.timezone import is_naive, make_aware

from travels.models import (PickUpPoints, RequestStates, RequestTravels, Travel, TravelStates, UsersDenied)
from travels.services.exceptions import (AlreadyRequestedError, DateChangeWithOccupiedSeatsError, EndDateRequiredError, 
                                        InvalidPeriodicIntervalError, InvalidRequestStatusError, InvalidStatusTransitionError, 
                                        StatusNotRequestableError, InvalidValidationCodeError, NotTravelOwnerError,
                                        PassengerAlreadyValidatedError, PassengerNotAcceptedError, PassengerNotFoundError, 
                                        PassengerNotInTravelError, PeriodicDeniedUsersError, PeriodicSeatsReductionError,
                                        PickUpPointNotFoundError, RequestOwnTravelError, SeatsBelowOccupiedError, SeatsFullError,
                                        SeriesVehicleSeatsInsufficientError, TravelIsNotPunctualError, VehicleNotFoundError, VehicleSeatsInsufficientError)
from users.models import Notifications, UserType, Users, Vehicles

# Logger para ir almacenando los logs
logger = logging.getLogger(__name__)

# Estados de solicitud que impiden volver a solicitar plaza en un viaje
ACTIVE_REQUEST_STATES = ['accepted', 'pending', 'validated', 'unvalidated']

# Servicio con la logica de negocio del agregado Travel
class TravelService:
    """
    Centraliza las reglas de negocio de los viajes y de sus entidades
    dependientes (RequestTravels, PickUpPoints, UsersDenied)
    No conoce HTTP, solo recibe datos ya validados, devuelve datos o lanza
    excepciones de dominio, y es el view quien las traduce a Response.
    """

    # Margen tras la hora de llegada prevista antes de dar un viaje por finalizado
    EXPIRATION_MARGIN = timedelta(hours=2)

    # Ocupa un asiento del viaje
    @staticmethod
    def reserve_seat(travel_id):
        """
        Descuenta un asiento del viaje indicado y bloquea la fila del viaje con select_for_update para que dos solicitudes
        aceptadas a la vez no puedan provocar overbooking. Lanza SeatsFullError si el viaje ya esta completo
        Devuelve el viaje actualizado
        """
        with transaction.atomic():
            travel = Travel.objects.select_for_update().get(pk=travel_id)

            # Solo se puede ocupar si quedan espacios disponibles
            if travel.remaining_seats <= 0:
                logger.warning(f"Travel {travel.id_travel} is full, the seat cannot be reserved.")
                raise SeatsFullError(travel_id)

            travel.remaining_seats -= 1
            travel.save()

            logger.info(f"Seat reserved for travel {travel.id_travel}. Remaining seats updated to {travel.remaining_seats}.")
            return travel

    # Devuelve un asiento al viaje
    @staticmethod
    def release_seat(travel_id):
        """
        Suma un asiento al viaje indicado, bloquea la fila igual que reserve_seat, y aplica el guard de no superar
        el maximo de asientos del viaje. 
        Devuelve la tupla (viaje, liberado), liberado es False cuando el viaje ya estaba al maximo y por tanto no 
        habia nada que devolver, para que el view pueda decidir si notifica o no.
        """
        with transaction.atomic():
            travel = Travel.objects.select_for_update().get(pk=travel_id)

            # Solo se aumenta si no esta al maximo
            if travel.remaining_seats >= travel.num_seats:
                logger.warning(f"Travel {travel.id_travel} is already at its maximum of {travel.num_seats} seats, no seat released.")
                return travel, False

            travel.remaining_seats += 1
            travel.save()

            logger.info(f"Seat released for travel {travel.id_travel}. Remaining seats updated to {travel.remaining_seats}.")
            return travel, True

    # Solicita una plaza en uno o varios viajes
    @staticmethod
    def request_seat(user, travel_ids):
        """
        Crea una solicitud pendiente por cada viaje indicado y avisa a su conductor
        Lanza RequestOwnTravelError si alguno de los viajes es del propio usuario,
        y AlreadyRequestedError si ya tiene una solicitud en alguno de ellos
        Devuelve el numero de solicitudes creadas
        """
        with transaction.atomic():
            # No se debe permitir que el usuario solicite una plaza para su propio viaje
            if Travel.objects.filter(id_travel__in=travel_ids, creation_user=user, is_deleted=False).exists():
                logger.warning(f"User {user.username} tried to request their own travel {travel_ids}")
                raise RequestOwnTravelError()

            # No se debe permitir solicitar plaza en un viaje en el que ya tiene una plaza aceptada o pendiente
            if RequestTravels.objects.filter(id_travel__in=travel_ids, user=user, status__in=ACTIVE_REQUEST_STATES, is_deleted=False).exists():
                logger.warning(f"User {user.username} tried to request an already accepted travel {travel_ids}")
                raise AlreadyRequestedError()

            travel_list = Travel.objects.filter(id_travel__in=travel_ids, is_deleted=False)

            # Se saca el estado pending para asignarlo a las nuevas solicitudes
            pending_state = RequestStates.objects.get(code='pending')

            requests_created = 0
            # Se crea la solicitud por cada uno de los viajes
            for travel in travel_list:
                RequestTravels.objects.create(
                    id_travel=travel,
                    user=user,
                    status=pending_state
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

            return requests_created

    # Genera un codigo de validacion unico dentro del viaje
    @staticmethod
    def _generate_validation_code(travel):
        validation_code = ''.join(random.choices(string.ascii_uppercase + string.digits, k=8))
        # Se asegura que el codigo sea unico
        while RequestTravels.objects.filter(id_travel=travel.id_travel, validation_code=validation_code, is_deleted=False).exists():
            validation_code = ''.join(random.choices(string.ascii_uppercase + string.digits, k=8))
        return validation_code

    # Transiciones permitidas en el ciclo de vida de una solicitud
    ALLOW_TRANSITIONS = {
        'pending': {'accepted', 'rejected'},
        'accepted': {'validated', 'unvalidated', 'rejected'},
        'validated': {'unvalidated'},
        # Estados finales: de aqui no se sale
        'rejected': set(),
        'unvalidated': set(),
    }

    # Estados que un cliente puede pedir por la API
    API_REQUESTABLE_STATES = {'accepted', 'rejected'}

    # Cambia el estado de una solicitud aplicando sus efectos sobre el viaje
    @staticmethod
    def change_request_status(request_travel, new_status_code, from_api=True):
        """
        Aplica la transicion de estado de una solicitud y sus efectos:

            pending  -> accepted : ocupa asiento, genera codigo y notifica
            pending  -> rejected : solo notifica el rechazo
            accepted -> rejected : libera asiento y notifica la expulsion
            accepted -> validated / unvalidated : notifica al pasajero
            validated -> unvalidated : notifica al pasajero
        """
        with transaction.atomic():
            current_status = request_travel.status.code
            travel = request_travel.id_travel

            try:
                new_status_obj = RequestStates.objects.get(code=new_status_code)
            except RequestStates.DoesNotExist:
                logger.error(f"Error Status code {new_status_code} invalid")
                raise InvalidRequestStatusError(new_status_code)

            # Si no se puede pedir el estado, debe lanzar una excepcion
            if from_api and new_status_code not in TravelService.API_REQUESTABLE_STATES:
                logger.warning(
                    f"Rejected API request for status {new_status_code} on request {request_travel.id}"
                )
                raise StatusNotRequestableError(new_status_code)

            # Pedir el estado que ya tiene no es un salto imposible, es no hacer nada
            if current_status == new_status_code:
                logger.info(
                    f"Request {request_travel.id} already in status {new_status_code}, nothing to do"
                )
                return request_travel
            # Si solicita un salto imposible, se lanza una excepcion
            if new_status_code not in TravelService.ALLOW_TRANSITIONS.get(current_status, set()):
                logger.warning(
                    f"Rejected transition {current_status} -> {new_status_code} for request {request_travel.id}"
                )
                raise InvalidStatusTransitionError(current_status, new_status_code)

            # En caso de que se apruebe la solicitud
            if current_status == 'pending' and new_status_code == 'accepted':
                # Solo se puede aceptar si quedan espacios disponibles
                TravelService.reserve_seat(travel.pk)

                # Se genera un codigo de validacion para el pasajero
                validation_code = TravelService._generate_validation_code(travel)
                request_travel.validation_code = validation_code
                # Se le notifica al usuario
                Notifications.objects.create(
                    id_user=request_travel.user,
                    content=f"Tu solicitud para el viaje {travel.origin} - {travel.destination} ha sido aceptada. Tu código de validación es: {validation_code}"
                )

            # Si la solicitud estaba aceptada, pero se elimina
            elif current_status == 'accepted' and new_status_code in ['rejected']:

                TravelService.release_seat(travel.pk)

                # Eliminan al pasajero, por lo que se le notifica
                Notifications.objects.create(
                    id_user=request_travel.user,
                    content=f"El creador del viaje {travel.origin} - {travel.destination} te ha eliminado del viaje."
                )

            # Si estaba pendiente y se rechaza
            elif current_status == 'pending' and new_status_code == 'rejected':
                # Se notifica al usuario de que le han rechazado la solicitud
                Notifications.objects.create(
                    id_user=request_travel.user,
                    content=f"Tu solicitud para el viaje {travel.origin} - {travel.destination} ha sido rechazada."
                )

            request_travel.status = new_status_obj
            request_travel.save()
            return request_travel

    # Efectos de cancelar una solicitud antes de borrarla
    @staticmethod
    def cancel_request(request_travel):
        """
        Si la solicitud estaba aceptada, libera el asiento y avisa al conductor
        Devuelve True si se llego a liberar un asiento
        """
        with transaction.atomic():
            if request_travel.status.code != 'accepted':
                return False

            # Si la solicitud estaba aceptada, se debe liberar un asiento en el viaje
            travel, released = TravelService.release_seat(request_travel.id_travel_id)
            if released: # Solo se avisa al conductor si realmente se ha liberado
                logger.info(f"Seat released for travel {travel.id_travel} due to deletion of accepted request.")
                Notifications.objects.create(
                    id_user=travel.creation_user,
                    content=f"Un pasajero ha cancelado su solicitud para el viaje {travel.origin} - {travel.destination}. Se ha liberado un asiento."
                )
            return released

    # Expulsa a un pasajero del viaje y libera su asiento
    @staticmethod
    def remove_passenger(travel, passenger_username):
        """
        Rechaza la solicitud aceptada del pasajero, libera su asiento y le notifica
        Lanza PassengerNotFoundError si no existe el usuario y PassengerNotInTravelError si no tenia una solicitud aceptada
        Devuelve la tupla (viaje actualizado, pasajero)
        """
        passenger = Users.objects.filter(username=passenger_username).first()
        # Si no existe el pasajero con ese nombre de usuario, se devuelve error
        if not passenger:
            logger.error(f"Passenger with username {passenger_username} not found")
            raise PassengerNotFoundError(passenger_username)

        with transaction.atomic():
            # Se saca la solicitud del pasajero para ese viaje
            try:
                request_to_remove = RequestTravels.objects.get(id_travel=travel, user__id=passenger.id, status__code='accepted')
            except RequestTravels.DoesNotExist:
                raise PassengerNotInTravelError(passenger_username)

            request_to_remove.status = RequestStates.objects.get(code='rejected')
            request_to_remove.save()

            # El asiento se libera con el metodo que lo centraliza
            travel, _ = TravelService.release_seat(travel.pk)

            # Se notifica al pasajero que ha sido eliminado del viaje
            date = travel.travel_date.strftime("%d/%m/%Y %H:%M")
            Notifications.objects.create(
                id_user=passenger,
                content=f"Has sido eliminado del viaje {travel.origin} - {travel.destination} del dia {date}."
            )
            logger.info(f"Passenger with ID {passenger} removed from travel {travel.id_travel}. Remaining seats updated to {travel.remaining_seats}. Notification sent.")

        return travel, passenger

    # Valida a un pasajero mediante su codigo de validacion
    @staticmethod
    def validate_passenger(travel, code):
        """
        Marca como validated la solicitud del viaje que tenga ese codigo
        Lanza InvalidValidationCodeError, PassengerAlreadyValidatedError o PassengerNotAcceptedError segun el caso.
        Devuelve la solicitud validada
        """
        # Se busca la solicitud con ese codigo de validacion que pertenezca a este viaje
        try:
            request_travel = RequestTravels.objects.get(
                id_travel=travel,
                validation_code=code,
                is_deleted=False
            )
        except RequestTravels.DoesNotExist:
            logger.warning(f"Validation code {code} not found for travel {travel.id_travel}")
            raise InvalidValidationCodeError(code)

        if request_travel.status.code == 'validated':
            # Si ya esta validado, se informa al usuario que ya ha sido validado
            logger.warning(f"Passenger {request_travel.user.username} already validated for travel {travel.id_travel}")
            raise PassengerAlreadyValidatedError(request_travel.user.username)

        # Si la solicitud no esta aceptada, no se puede validar
        if request_travel.status.code != 'accepted':
            logger.warning(f"Passenger {request_travel.user.username} has status {request_travel.status.code} and cannot be validated for travel {travel.id_travel}")
            raise PassengerNotAcceptedError(request_travel.user.username)

        # Se actualiza el estado a validado
        request_travel.status = RequestStates.objects.get(code='validated')
        request_travel.save()

        logger.info(f"Passenger {request_travel.user.username} validated for travel {travel.id_travel} with code {code}")
        return request_travel

    # Finaliza el viaje y actualiza el estado de sus pasajeros
    @staticmethod
    def finish_travel(travel):
        """
        Pasa el viaje a finalizado, marca como unvalidated a los pasajeros que no
        se validaron y como validated a los que si, y los notifica a ambos.
        Devuelve el numero de pasajeros marcados como no validados.
        """
        parsed_date = django_date(travel.travel_date, r"j \d\e F \d\e Y")
        travel_label = f"El viaje de {travel.origin} a {travel.destination} del día {parsed_date}"

        with transaction.atomic():
            # Se cambia el estado del viaje a finalizado
            travel.state = TravelStates.objects.get(code='fnd')
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
                    content=f"{travel_label} ha finalizado, NO has sido validado en él."
                )

            logger.info(f"Travel {travel.id_travel} finished. {unvalidated_count} passengers marked as unvalidated.")

            # Se buscan las solicitudes validadas para enviarles la notificacion de que su viaje ha terminado y pueden puntuar al conductor
            validated_requests = RequestTravels.objects.filter(
                id_travel=travel,
                status__code='validated',
                is_deleted=False
            )

            for req in validated_requests:
                # Se notifica a los pasajeros validados
                Notifications.objects.create(
                    id_user=req.user,
                    content=f"{travel_label} ha finalizado. Puedes puntuar al conductor."
                )

            logger.info(f"Notifications sent to {validated_requests.count()} validated passengers for travel {travel.id_travel}.")
            return unvalidated_count

    # Viajes cuyo plazo para validar pasajeros ya ha vencido
    @staticmethod
    def find_expired_travels(now=None):
        """
        Viajes activos cuya hora de llegada prevista (salida + duracion) lleva mas de EXPIRATION_MARGIN pasada
        """
        now = now or timezone.now()

        return Travel.objects.annotate(
            expiration_date=ExpressionWrapper(
                F('travel_date') + (timedelta(minutes=1) * F('duration_minutes')) + TravelService.EXPIRATION_MARGIN,
                output_field=DateTimeField()
            )
        ).filter(
            state='active',
            expiration_date__lte=now,
            is_deleted=False
        )

    # Cierre automatico de los viajes caducados (lo usa el comando programado)
    @staticmethod
    def finish_expired_travels(now=None):
        """
        Finaliza todos los viajes caducados aplicando la misma regla que cuando el conductor finaliza a mano
        Devuelve la tupla (viajes finalizados, pasajeros marcados como no validados).
        """
        expired_travels = list(TravelService.find_expired_travels(now))

        finished_count = 0
        unvalidated_count = 0
        for travel in expired_travels:
            unvalidated_count += TravelService.finish_travel(travel)
            finished_count += 1

        return finished_count, unvalidated_count

    # Efectos de eliminar un viaje sobre sus solicitudes
    @staticmethod
    def delete_travel(travel):
        """
        Notifica la cancelacion a todos los solicitantes y marca como borradas sus
        solicitudes, solo actua si el viaje sigue activo
        Devuelve el numero de notificaciones enviadas
        """
        # Solo se borran las solicitudes si el viaje esta activo, si ya ha pasado, no se borran
        if travel.state.code != 'active':
            return 0

        # Se sacan las solicitudes del viaje
        request_travels = travel.requested_travels.filter(is_deleted=False)

        notifications = []
        # Se crea el mensaje generico que se le envia a cada usuario
        parsed_date = django_date(travel.travel_date, r"j \d\e F \d\e Y")
        msg = f"El viaje de {travel.origin} a {travel.destination} del día {parsed_date} ha sido cancelado."

        # Se guardan las notificaciones para insertarlas en bbdd
        for rt in request_travels: # Se notifica a todos los usuarios con una solicitud, aunque estuviera pendiente
            notifications.append(
                Notifications(
                    id_user=rt.user,
                    content=msg
                )
            )
        # Se insertan las notificaciones en bbdd
        if notifications:
            Notifications.objects.bulk_create(notifications)
        logger.info(f"Sent {len(notifications)} notifications for the deleted travel {travel.id_travel}.")

        logger.info(f"Soft-deleting requests associated with travel {travel.id_travel}.")
        travel.requested_travels.filter(is_deleted=False).update(
            is_deleted=True,
            deleted_at=timezone.now()
        )

        return len(notifications)

    # Modifica los datos de un viaje
    @staticmethod
    def edit_travel(travel, data):
        """
        Aplica la edicion de un viaje. El tratamiento es distinto segun el viaje
        sea periodico o puntual, asi que se delega en los dos metodos privados
        """
        with transaction.atomic():
            seats = data.get('seats')

            if seats and seats < travel.num_seats and travel.is_periodic:
                # No se puede reducir el numero de asientos si el viaje es periodico
                raise PeriodicSeatsReductionError()

            # Se sacan el numero de asientos ocupados
            if seats and seats != travel.num_seats:
                occupied_seats = travel.num_seats - travel.remaining_seats
                travel.num_seats = seats
                if occupied_seats > seats: # Si intenta poner menos asientos que los ocupados, se devuelve error
                    raise SeatsBelowOccupiedError(seats, occupied_seats)
                # Se actualizan los nuevos asientos
                travel.remaining_seats = seats - occupied_seats
                travel.save()

            # Se debe tratar distinto si el viaje era periodico que si es puntual
            if travel.is_periodic:
                TravelService._edit_periodic_travel(travel, data)
            else:
                TravelService._edit_punctual_travel(travel, data)

            return travel

    # Edicion de un viaje que era periodico
    @staticmethod
    def _edit_periodic_travel(travel, data):
        only_this_travel = data.get('only_this_travel', False)
        users_deny = data.get('users_deny', [])
        vehicle_id = data.get('vehicle_id')
        is_periodic = data.get('is_periodic')

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
            raise PeriodicDeniedUsersError()

        # Si se ha cambiado de vehiculo, se busca el nuevo y se añade a los viajes futuros
        if vehicle_id and vehicle_id != str(travel.vehicle.id_vehicle):
            vehicle = Vehicles.objects.filter(id_vehicle=vehicle_id, is_deleted=False)
            if not vehicle: # Si no se encuentra se lanza error
                raise VehicleNotFoundError()

            # Se comprueba que no se pueda cambiar a un vehiculo con menos asientos que el actual
            if vehicle.first().seats - 1 < travel.num_seats:
                raise VehicleSeatsInsufficientError()

            travel.vehicle = vehicle.first()
            travel.save()

            if not only_this_travel:
                has_invalid_travels = travels_to_update.filter(num_seats__gt=vehicle.first().seats - 1).exists()
                if has_invalid_travels:
                    raise SeriesVehicleSeatsInsufficientError()

            # Se actualiza el vehiculo en cada uno de los viajes hijos
            travels_to_update.update(vehicle=travel.vehicle)
            # Se notifica a los pasajeros de que ha cambiado su vehiculo
            TravelService._notify_vehicle_change(
                RequestTravels.objects.filter(
                    id_travel__in=travels_to_update.values_list('id_travel', flat=True),
                    status='accepted',
                    is_deleted=False
                )
            )
            logger.info(f"Changed vehicle for travel {travel.id_travel} and futures. Notified the passengers of the change.")

        # Se desea cambiarlo a puntual
        if is_periodic is False:
            travels_to_update.update(is_periodic=False, periodic_interval=None, end_periodic_date=None, id_origin_travel=None)
            logger.info(f"Changed travels {travels_to_update.values_list('id_travel', flat=True)} to punctual.")

    # Edicion de un viaje que era puntual
    @staticmethod
    def _edit_punctual_travel(travel, data):
        # Hay que checkear si vienen las coordenadoas en el JSON, (si no ha cambiado de lugares no vienen)
        orig_lat = data.get('origin_lat')
        orig_lng = data.get('origin_lng')
        dest_lat = data.get('destination_lat')
        dest_lng = data.get('destination_lng')

        # El origen y el destino siempre vienen, aunque no cambien
        origin = data.get('origin')
        destination = data.get('destination')

        date_raw = data.get('travel_date')
        if date_raw:
            _parsed = parse_datetime(date_raw)
            date = make_aware(_parsed) if (_parsed and is_naive(_parsed)) else _parsed
        else:
            date = None

        users_deny = data.get('users_deny', [])
        vehicle_id = data.get('vehicle_id')
        duration = data.get('duration')
        is_periodic = data.get('is_periodic')

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
                raise VehicleNotFoundError()
            travel.vehicle = vehicle.first()
            travel.save()
            TravelService._notify_vehicle_change(
                RequestTravels.objects.filter(id_travel=travel.id_travel, status='accepted', is_deleted=False)
            )

        # Se actualiza la fecha del viaje si no hay plazas ocupadas.
        if date is not None and date != travel.travel_date:
            if travel.remaining_seats < travel.num_seats:
                raise DateChangeWithOccupiedSeatsError()
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
            TravelService._make_periodic(travel, data)

    # Convierte un viaje puntual en periodico y genera sus viajes hijos
    @staticmethod
    def _make_periodic(travel, data):
        interval = data.get('periodic_interval') # Dias entre los viajes
        interval_days = int(interval) if interval else 0
        end_date_str = data.get('end_periodic_date')

        # Si uno de los parametros no viene se devuelve error
        if not end_date_str:
            logger.error("End date is required to change to periodic")
            raise EndDateRequiredError()

        if not interval_days or interval_days <= 0 or interval_days > 31:
            logger.error("Interval days is required and must be between 1 and 31")
            raise InvalidPeriodicIntervalError()

        end_date = parse_datetime(end_date_str) or parse_date(end_date_str)
        # Si es un datetime, extraemos solo el date para que el bucle while no falle
        if hasattr(end_date, 'date'):
            end_date = end_date.date()

        # Cambiar el viaje a periódico
        travel.is_periodic = True
        travel.periodic_interval = interval_days
        travel.end_periodic_date = end_date
        travel.save()

        active_state = TravelStates.objects.get(code='active')

        # Generar las fechas para los nuevos viajes hijos
        current_date = travel.travel_date + timedelta(days=interval_days)
        new_travels = []

        while current_date.date() <= end_date:
            if timezone.is_naive(current_date):
                current_date = timezone.make_aware(current_date)
            # Se crean los hijos copiando al padre
            new_travels.append(Travel(
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
            ))
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

    # Avisa a los pasajeros aceptados de que su viaje ha cambiado de vehiculo
    @staticmethod
    def _notify_vehicle_change(request_travels):
        for r in request_travels:
            Notifications.objects.create(
                id_user=r.user,
                content=f"Se ha cambiado de vehiculo en el viaje {r.id_travel.origin} - {r.id_travel.destination} del dia {r.id_travel.travel_date.strftime('%d/%m/%Y')} revisa el viaje para ver los cambios"
            )

    # Sustituye los puntos de recogida de un viaje puntual
    @staticmethod
    def change_pickup_points(travel, pickup_points):
        """
        Marca como borrados los puntos de recogida actuales y crea los nuevos.
        Lanza TravelIsNotPunctualError en viajes periodicos
        """
        with transaction.atomic():
            if travel.is_periodic: # En un viaje periodico no se pueden modificar los puntos de recogida
                logger.error(f"Error changing pickup points for periodic travel {travel.id_travel}.")
                raise TravelIsNotPunctualError()

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

    # Marca un punto de recogida como alcanzado
    @staticmethod
    def reach_pickup_point(travel, point_id):
        """
        Marca como alcanzado el punto de recogida indicado del viaje.
        Lanza PickUpPointNotFoundError si no pertenece a ese viaje.
        """
        try:
            point = PickUpPoints.objects.get(id_point=point_id, id_travel=travel)
        except (PickUpPoints.DoesNotExist, ValueError):
            raise PickUpPointNotFoundError(point_id)

        point.is_reached = True
        point.save()
        return point

    # Comprueba que todos los viajes indicados los haya creado el usuario
    @staticmethod
    def assert_travels_belong_to(user, travels):
        """
        Se usa antes de crear o modificar lo que dependa de un viaje (paradas, tipos de usuario denegados)
        Lanza NotTravelOwnerError si alguno de los viajes no pertenece al usuario
        """
        for travel in travels:
            if travel is None:
                continue
            if travel.creation_user_id != user.pk:
                logger.warning(
                    f"User {user.pk} tried to modify data of travel {travel.pk}, which is not theirs."
                )
                raise NotTravelOwnerError(travel.pk)


    # Aplica todos los filtros de busqueda de viajes
    @staticmethod
    def search_travels(queryset, user, data):
        """
        Construye la consulta de busqueda de viajes a partir de los filtros
        recibidos: origen/destino con radio, fechas, preferencias del conductor, 
        distintivo ambiental, tipo de viaje y tipos de usuario denegados.
        Recibe el queryset base del view (ya sin borrados) y devuelve el queryset filtrado y ordenado, sin paginar
        """
        # Ordenacion (Por defecto recent)
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

        # Crear los puntos espaciales
        orig_pt = Point(orig_lng, orig_lat, srid=4326)
        dest_pt = Point(dest_lng, dest_lat, srid=4326)

        has_origin = orig_lat != 0 or orig_lng != 0
        has_dest = dest_lat != 0 or dest_lng != 0

        # Se sacan los viajes que no son del usuario, que tengan asientos disponibles y esten activos
        travels = queryset.exclude(creation_user=user).exclude(remaining_seats__lt=1).filter(state='active')

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
            user_type__code=user.user_type.code,
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
                matching_denies=len(set(users_deny))
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
            travels = travels.filter(
                creation_user__preferences__pref_type__in=preferences,
                creation_user__preferences__is_deleted=False
            ).annotate(
                matching_preferences=Count('creation_user__preferences', distinct=True)
            ).filter(
                matching_preferences=len(set(preferences))
            )
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

        return travels