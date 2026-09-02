import logging

from django.db import connection, transaction
from django.db.models import Q
from django.utils import timezone

from travels.models import RequestTravels, Travel
from users.models import Criteria, Device, DriverRatings, Preferences, PrefTypes
from users.services.auth_service import AuthService
from users.services.exceptions import (IncorrectPasswordError, NoUpcomingTravelsError, RequestStatusMissingError,
    RequestTravelNotValidatedError, UserNotFoundError, VehicleHasActiveTravelsError, VehicleSeatsInsufficientError)

# Logger para ir almacenando los logs
logger = logging.getLogger(__name__)

# Numero maximo de viajes que devuelve la pantalla de inicio
MAX_NEXT_TRAVELS = 3

# Numero minimo de asientos que puede tener un vehiculo
MIN_VEHICLE_SEATS = 2

# Servicio con la logica de negocio del subsistema de usuarios
class UserService:
    """
    Centraliza las reglas de negocio de los usuarios: perfil, preferencias, 
    listados propios (vehiculos, notificaciones, viajes, solicitudes), valoraciones y vehiculos.
    """
    
    # Busca un usuario activo por nombre de usuario o por correo
    @staticmethod
    def find_by_username_or_email(identifier):
        """
        El cliente manda un unico campo en el que se verifican ambas cosas, si trae
        una arroba se busca por correo y si no por nombre de usuario, el nombre de usuario no admite arrobas
        """
        from users.models import Users, normalize_email
        active = Users.objects.filter(is_deleted=False)
        if '@' in identifier:
            user = active.filter(email=normalize_email(identifier)).first()
        else:
            user = active.filter(username=identifier).first()
        if user is None:
            raise UserNotFoundError(identifier)
        return user

    # Guarda la imagen de perfil del usuario y devuelve el nombre del archivo
    @staticmethod
    def update_profile_picture(user, picture):
        user.profile_picture = picture
        user.save()
        logger.info(f"Profile picture updated for user ID: {user.id}")
        return user.profile_picture.name.split('/')[-1]

    # Borra la imagen de perfil. Devuelve False si no habia ninguna que borrar
    @staticmethod
    def delete_profile_picture(user):
        if not user.profile_picture:
            return False
        # Se borra el archivo del almacenamiento y despues la referencia
        user.profile_picture.delete(save=False)
        user.profile_picture = None
        user.save()
        logger.info(f"Profile picture deleted for user ID: {user.id}")
        return True

    # Cambia la contraseña del usuario comprobando antes la actual
    @staticmethod
    def change_password(user, current_password, new_password):
        if not user.check_password(current_password):
            logger.warning(f"Incorrect current password provided for user ID: {user.id}")
            raise IncorrectPasswordError(user.id)
        AuthService.assert_password_is_acceptable(new_password, user=user)

        user.set_password(new_password)
        user.save()

        # Al cambiar la contraseña se revocan todas las sesiones
        AuthService.revoke_all_sessions(user)
        logger.info(f"Password changed successfully for user ID: {user.id}")
        return user

    # Devuelve las preferencias activas del usuario
    @staticmethod
    def list_preferences(user):
        return user.preferences.filter(is_deleted=False).order_by('pref_type')

    # Deja las preferencias del usuario en exactamente las que le pasen
    @staticmethod
    def update_preferences(user, pref_codes):
        """
        Sustituye las preferencias del usuario por las de la lista de codigos
        Los codigos que no existan en el catalogo se ignoran sin fallar
        Devuelve el numero de preferencias activas resultante
        """
        with transaction.atomic():
            # Solo se tienen en cuenta los codigos que existen en el catalogo
            wanted = set(
                PrefTypes.objects.filter(
                    code__in=pref_codes, is_deleted=False
                ).values_list('code', flat=True)
            )

            # Todas las filas del usuario, incluidas las ya marcadas como borradas
            existing = {pref.pref_type_id: pref for pref in user.preferences.all()}

            for code in wanted:
                pref = existing.get(code)
                if pref is None:
                    Preferences.objects.create(id_user=user, pref_type_id=code)
                elif pref.is_deleted:
                    # Se revive la fila que ya existia en vez de crear otra
                    pref.is_deleted = False
                    pref.deleted_at = None
                    pref.save()

            # Lo que ya no esta en la lista se marca como borrado
            for code, pref in existing.items():
                if code not in wanted and not pref.is_deleted:
                    pref.is_deleted = True
                    pref.deleted_at = timezone.now()
                    pref.save()

            logger.info(f"Preferences updated successfully for user ID: {user.id}")
            return len(wanted)

    # Marca como borradas todas las preferencias activas del usuario
    @staticmethod
    def clear_preferences(user):
        """
        Devuelve cuantas preferencias se han quitado.
        """
        cleared = user.preferences.filter(is_deleted=False).update(
            is_deleted=True, deleted_at=timezone.now()
        )
        logger.info(f"Cleared {cleared} preferences for user ID: {user.id}")
        return cleared

    # Devuelve los vehiculos activos del usuario
    @staticmethod
    def list_vehicles(user):
        return user.vehicles.filter(is_deleted=False)

    # Devuelve las notificaciones del usuario ordenadas por fecha
    @staticmethod
    def list_notifications(user, ordering='desc'):
        order_field = 'date' if ordering == 'asc' else '-date'
        return user.notifications.filter(is_deleted=False).order_by(order_field)

    # Cuenta las notificaciones que el usuario aun no ha leido
    @staticmethod
    def count_unread_notifications(user):
        return user.notifications.filter(is_deleted=False, read=False).count()

    # Devuelve la media por criterio y el total de valoraciones de un conductor
    @staticmethod
    def get_driver_ratings(user):
        """
        Las medias las calcula el procedimiento almacenado getdriverratings, la llamada se realiza aqui
        """
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT code, avg_score, num_ratings FROM public.getdriverratings(%s)",
                [str(user.id)],
            )
            results = cursor.fetchall()

        # Sin valoraciones se devuelve la forma vacia que espera la app
        if not results:
            return {"results": {"none": 0}, "count": 0}

        return {
            "results": {
                row[0]: float(row[1]) if row[1] is not None else None
                for row in results
            },
            "count": float(results[0][2]) if results[0][2] is not None else None,
        }

    # Registra la valoracion de un conductor tras un viaje validado
    @staticmethod
    def rate_driver(user, request_travel_id, results):
        """
        results es un diccionario {codigo_de_criterio: nota}, los criterios que no existan se ignoran sin fallar
        Al terminar, la solicitud pasa a unvalidated para que no se pueda valorar dos veces el mismo viaje.
        """
        # El usuario tiene que tener esa solicitud y estar validada
        request_travel = RequestTravels.objects.filter(
            id=request_travel_id, user=user, status__code='validated'
        ).first()
        if not request_travel:
            logger.error("The specified request_travel is not found or not in the correct status")
            raise RequestTravelNotValidatedError(request_travel_id)

        driver = request_travel.id_travel.creation_user

        with transaction.atomic():
            for criteria_code, score in results.items():
                # Se va puntuando por cada criterio
                criteria_obj = Criteria.objects.filter(code=criteria_code).first()
                if not criteria_obj:
                    logger.error(f"Criteria '{criteria_code}' not found, skipping.")
                    continue
                DriverRatings.objects.create(
                    id_user=user,
                    id_driver=driver,
                    criteria=criteria_obj,
                    score=score,
                )

            # Se cambia el estado a invalidado para que ya no se pueda valorar de nuevo ese viaje
            unvalidated_status = request_travel.status.__class__.objects.filter(
                code='unvalidated'
            ).first()
            if not unvalidated_status:
                logger.error("Unvalidated status not found, unable to update request_travel status.")
                raise RequestStatusMissingError('unvalidated')

            request_travel.status = unvalidated_status
            request_travel.save()

        logger.info(
            f"Driver ratings saved successfully for user ID: {user.id} and driver ID: {driver.id}"
        )
        return driver

    # Devuelve los viajes creados por el usuario, filtrados por tipo
    @staticmethod
    def list_created_travels(user, travel_type='all'):
        """
        travel_type acepta pending (futuros o en curso), past (finalizados) 
        y all, que devuelve todos.
        """
        today = timezone.now().date()
        qs = user.created_travels.filter(is_deleted=False)

        if travel_type == 'pending':
            return qs.filter(
                Q(travel_date__gte=today, state__code='active') | Q(state__code='started')
            ).order_by('travel_date')

        if travel_type == 'past':
            return qs.filter(
                Q(travel_date__lt=today) | Q(state__code='fnd')
            ).order_by('-travel_date')

        return qs

    # Devuelve las solicitudes que ha hecho el usuario, filtradas por tipo
    @staticmethod
    def list_own_requests(user, request_type='all'):
        """
        request_type acepta 'pending' (aun sin responder o rechazadas),
        active (aceptadas), past (ya viajadas) y all, que devuelve todas.
        """
        today = timezone.now().date()
        qs = user.requested_travels.filter(is_deleted=False)

        if request_type == 'pending':
            return qs.filter(
                status__code__in=['pending', 'rejected'],
                id_travel__travel_date__gte=today,
            ).order_by('id_travel__travel_date')

        if request_type == 'active':
            return qs.filter(status__code='accepted').order_by('id_travel__travel_date')

        if request_type == 'past':
            return qs.filter(
                status__code__in=['validated', 'unvalidated']
            ).order_by('-id_travel__travel_date')

        return qs

    # Devuelve las solicitudes pendientes de aprobar que ha recibido el usuario
    @staticmethod
    def list_received_requests(user):
        return RequestTravels.objects.filter(
            id_travel__creation_user=user,
            status__code='pending',
            is_deleted=False,
        ).order_by('-created_at')

    # Devuelve los proximos viajes del usuario, como conductor y como pasajero
    @staticmethod
    def get_next_travels(user, max_travels=MAX_NEXT_TRAVELS):
        """
        Mezcla los viajes que ha creado con aquellos en los que va de pasajero,
        ordenados por fecha. Primero se ponen los viajes en curso, y despues por fecha
        Devuelve una lista de diccionarios lista para serializar.
        """
        from api.serializers.travel_serializer import TravelSerializer

        today = timezone.now().date()

        started_travel = user.created_travels.filter(state='started', is_deleted=False).order_by('travel_date').first()

        # El viaje en curso ocupa una de las plazas del maximo
        remaining = max_travels - (1 if started_travel else 0)

        created_travels = list(
            user.created_travels.filter(
                state='active', is_deleted=False
            ).order_by('travel_date')[:remaining]
        )

        requested_reqs = list(
            RequestTravels.objects.filter(
                user=user,
                status__code='accepted',
                id_travel__travel_date__gte=today,
                id_travel__state='active',
                id_travel__is_deleted=False,
                is_deleted=False,
            ).order_by('id_travel__travel_date').select_related('id_travel', 'status')[:remaining]
        )

        # Se combinan los viajes creados y solicitados, para sacar los siguientes 3 viajes
        candidates = (
            [(t, False, None) for t in created_travels] + [(req.id_travel, True, req) for req in requested_reqs]
        )
        candidates.sort(key=lambda x: x[0].travel_date)
        candidates = candidates[:remaining]

        if started_travel:
            candidates = [(started_travel, False, None)] + candidates

        if not candidates:
            logger.info(f"No travels found for user ID: {user.id}")
            raise NoUpcomingTravelsError(user.id)

        result = []
        for travel, is_request, req_obj in candidates:
            result.append({
                "id": req_obj.id if is_request else travel.id_travel,
                "data": TravelSerializer(travel).data,
                "is_request": is_request,
                "code": req_obj.validation_code if is_request else None,
                "status": req_obj.status.code if is_request else travel.state.code,
            })

        logger.info(f"Next travels retrieved successfully for user ID: {user.id}")
        return result
    
    # Comprueba que el vehiculo puede pasar a tener ese numero de asientos
    @staticmethod
    def check_new_seats(user, vehicle, new_seats):
        """
        Un vehiculo no puede quedarse con menos plazas de las que ya ha publicado
        en alguno de sus viajes activos, ni bajar del minimo.
        """
        if new_seats < MIN_VEHICLE_SEATS:
            logger.error("Number of seats cannot be less than 2")
            raise VehicleSeatsInsufficientError(new_seats)

        # El viaje no cuenta al conductor, por eso se compara con new_seats - 1
        if Travel.objects.filter(
            creation_user=user,
            vehicle_id=vehicle.id_vehicle,
            num_seats__gt=(new_seats - 1),
            state='active',
            is_deleted=False,
        ).exists():
            logger.error("Number of seats is insufficient for associated travels")
            raise VehicleHasActiveTravelsError(vehicle.id_vehicle)

    # Comprueba que el vehiculo se puede borrar
    @staticmethod
    def check_vehicle_is_free(user, vehicle):
        if Travel.objects.filter(
            creation_user=user,
            vehicle_id=vehicle.id_vehicle,
            state='active',
            is_deleted=False,
        ).exists():
            logger.error(f"Vehicle {vehicle.id_vehicle} has active travels associated")
            raise VehicleHasActiveTravelsError(vehicle.id_vehicle)


    # Registra el dispositivo del usuario, o lo actualiza si el token ya existia
    @staticmethod
    def register_device(user, fcm_token, platform=''):
        """
        El token de FCM identifica al dispositivo, no al usuario, si alguien
        inicia sesion en un movil donde ya habia otra cuenta, el token cambia de
        dueño en lugar de duplicarse.
        """
        device, created = Device.objects.update_or_create(
            fcm_token=fcm_token,
            defaults={
                'id_user': user,
                'platform': platform,
                'is_deleted': False,
            },
        )
        logger.info(
            f"Device {'registered' if created else 'updated'} for user ID: {user.id}"
        )
        return device
