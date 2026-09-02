import logging

from rest_framework import viewsets
from rest_framework import status
from rest_framework.decorators import action
from django.core.exceptions import ValidationError as DjangoValidationError
from django.http import Http404
from rest_framework.exceptions import APIException
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from django.core.paginator import Paginator
from django.db import connection, transaction
from django.db.models import Q

from travels.models import Travel, TravelStates, RequestTravels, PickUpPoints, UsersDenied
from api.serializers.travel_serializer import TravelSerializer, \
    RequestTravelsSerializer, PickUpPointSerializer, UsersDeniedSerializer
from api.serializers.user_serializer import PreferencesSerializer

from channels.layers import get_channel_layer
from asgiref.sync import async_to_sync
from chats.models import Chat

from api.ownership import OwnedQuerysetMixin
from api.soft_delete import SoftDeleteQuerysetMixin
from api.errors import ErrorCodes
from travels.services.travel_service import TravelService
from travels.services.exceptions import (
    AlreadyRequestedError, DateChangeWithOccupiedSeatsError, EndDateRequiredError, InvalidPeriodicIntervalError,
    InvalidRequestStatusError, InvalidStatusTransitionError, InvalidValidationCodeError, StatusNotRequestableError,
    NotTravelOwnerError, PassengerAlreadyValidatedError, PassengerNotAcceptedError, PassengerNotFoundError,
    PassengerNotInTravelError, PeriodicDeniedUsersError, PeriodicSeatsReductionError, PickUpPointNotFoundError,
    RequestOwnTravelError, SeatsBelowOccupiedError, SeatsFullError, SeriesVehicleSeatsInsufficientError,
    TravelIsNotPunctualError, VehicleNotFoundError, VehicleSeatsInsufficientError)

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

# Endpoints de los viajes
class TravelViewSet(SoftDeleteQuerysetMixin, viewsets.ModelViewSet):
    queryset = Travel.objects.all()
    serializer_class = TravelSerializer
    permission_classes = [IsAuthenticated]

    # PUT no se utiliza, por lo que no se publica
    http_method_names = ['get', 'post', 'patch', 'delete', 'head', 'options']

    # Sin ambito por defecto, solo se limita la accion que declara el suyo
    throttle_scope = None

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

        try:
            with transaction.atomic():
                # El servicio avisa a los solicitantes y borra sus solicitudes
                TravelService.delete_travel(travel)

                logger.info(f"Soft-deleting travel {travel.id_travel}.")
                return super().destroy(request, *args, **kwargs)
        except (Http404, APIException, DjangoValidationError):
            raise
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

        try:
            # Todo el filtrado y la ordenacion los construye el servicio
            travels = TravelService.search_travels(self.get_queryset(), request.user, data)

            # Se paginan los resultados
            paginator = Paginator(travels, page_size)
            page_obj = paginator.get_page(page_number)

            # Serializamos solo los viajes de esta página
            serializer = self.get_serializer(page_obj, many=True)

            return Response({
                'status': 'ok',
                'data': list(serializer.data),
                'has_next': page_obj.has_next() if hasattr(page_obj, 'has_next') else False
            })

        except (Http404, APIException, DjangoValidationError):
            raise
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
            requests_created = TravelService.request_seat(user, travel_ids)

            return Response({
                "status": "ok",
                "requests_created": requests_created,
                "message": f"Se han creado {requests_created} solicitudes."
            }, status=status.HTTP_200_OK)

        except RequestOwnTravelError:
            return Response({
                "status": "error",
                "message": "No puedes solicitar una plaza en tu propio viaje.",
                "error_code": ErrorCodes.REQUEST_OWN_TRAVEL
            }, status=status.HTTP_400_BAD_REQUEST)
        except AlreadyRequestedError:
            return Response({
                "status": "error",
                "message": "Ya has solicitado una plaza en alguno de uno estos viajes." if len(travel_ids) > 1 else "Ya has solicitado una plaza en este viaje.",
                "error_code": ErrorCodes.ALREADY_REQUESTED
            }, status=status.HTTP_400_BAD_REQUEST)
        except Travel.DoesNotExist: # Si no existe el viaje, se devuelve un error
            return Response({"status": "error", "message": "Viaje no encontrado", "error_code": ErrorCodes.TRAVEL_DONT_EXIST}, status=status.HTTP_404_NOT_FOUND)
        except (Http404, APIException, DjangoValidationError):
            raise
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
            TravelService.change_pickup_points(travel, pickup_points)

            return Response({
                "status": "ok",
                "message": "Los puntos de recogida se han actualizado correctamente."
            }, status=status.HTTP_200_OK)

        except TravelIsNotPunctualError:
            return Response({
                "status": "error",
                "message": "No se pueden modificar los puntos de recogida en un viaje periodico.",
                "error_code": ErrorCodes.TRAVEL_IS_NOT_PUNCTUAL
            }, status=status.HTTP_400_BAD_REQUEST)
        except (Http404, APIException, DjangoValidationError):
            raise
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

        logger.info(f"Request to edit travel {travel.id_travel} by user {request.user.username}")

        # Solo el creador del viaje puede modificar
        if travel.creation_user != request.user:
            return Response({
                "status": "error",
                "message": "No tienes permiso para modificar este viaje.",
                "error_code": ErrorCodes.INSUFICIENT_CREDENTIALS
            }, status=status.HTTP_403_FORBIDDEN)

        try:
            TravelService.edit_travel(travel, request.data)

            return Response({
                "status": "ok",
                "message": "La modificación se ha realizado correctamente."
            }, status=status.HTTP_200_OK)

        except PeriodicSeatsReductionError:
            return Response({
                "status": "error",
                "message": "No se puede reducir el número de asientos en un viaje periódico.",
                "error_code": ErrorCodes.TRAVEL_IS_NOT_PUNCTUAL
            }, status=status.HTTP_400_BAD_REQUEST)
        except PeriodicDeniedUsersError:
            return Response({
                "status": "error",
                "message": "No se puede cambiar los usuarios denegados en un viaje periódico.",
                "error_code": ErrorCodes.TRAVEL_IS_NOT_PUNCTUAL
            }, status=status.HTTP_400_BAD_REQUEST)
        except DateChangeWithOccupiedSeatsError:
            return Response({
                "status": "error",
                "message": "No se puede cambiar la fecha del viaje porque ya hay plazas ocupadas.",
                "error_code": ErrorCodes.SEATS_BELOW_OCCUPIED
            }, status=status.HTTP_400_BAD_REQUEST)
        except SeatsBelowOccupiedError as e:
            return Response({
                "status": "error",
                "message": f"No se puede reducir el número de asientos a {e.seats} porque ya hay {e.occupied_seats} plazas ocupadas.",
                "error_code": ErrorCodes.SEATS_BELOW_OCCUPIED
            }, status=status.HTTP_400_BAD_REQUEST)
        except VehicleNotFoundError:
            return Response({
                "status": "error",
                "message": "Vehículo no encontrado.",
                "error_code": ErrorCodes.VEHICLE_DONT_EXIST
            }, status=status.HTTP_404_NOT_FOUND)
        except SeriesVehicleSeatsInsufficientError:
            return Response({
                "status": "error",
                "message": "No se puede cambiar a este vehículo en toda la serie periódica porque un viaje futuro tiene más asientos que el vehículo seleccionado.",
                "error_code": ErrorCodes.VEHICLE_SEATS_INSUFFICIENT
            }, status=status.HTTP_400_BAD_REQUEST)
        except VehicleSeatsInsufficientError:
            return Response({
                "status": "error",
                "message": "No se puede cambiar a este vehículo porque tiene menos asientos que el viaje actual.",
                "error_code": ErrorCodes.VEHICLE_SEATS_INSUFFICIENT
            }, status=status.HTTP_400_BAD_REQUEST)
        except EndDateRequiredError:
            return Response({
                "status": "error",
                "message": "Se requiere fecha de finalización de periodicidad para cambiar a periódico.",
                "error_code": ErrorCodes.TO_DATE_REQUIRED
            }, status=status.HTTP_400_BAD_REQUEST)
        except InvalidPeriodicIntervalError:
            return Response({
                "status": "error",
                "message": "El intervalo de periodicidad es requerido y debe ser un número entre 1 y 31.",
                "error_code": ErrorCodes.INVALID_PERIODIC_INTERVAL
            }, status=status.HTTP_400_BAD_REQUEST)
        except (Http404, APIException, DjangoValidationError):
            raise
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
                points = PickUpPoints.objects.filter(id_travel=travel, is_deleted=False).order_by('order_in_travel')
                pickup_serializer = PickUpPointSerializer(points, many=True)
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

            except (Http404, APIException, DjangoValidationError):
                raise
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

        # Solo el creador del viaje puede eliminar pasajeros.
        if travel.creation_user != request.user or str(user.id) != str(user_id):
            logger.warning(f"User {request.user.username} tried to remove a passenger from travel {travel.id_travel} without being the creator")
            return Response({
                "status": "error",
                "message": "No tienes permiso para eliminar pasajeros de este viaje.",
                "error_code": ErrorCodes.INSUFICIENT_CREDENTIALS
            }, status=status.HTTP_403_FORBIDDEN)

        try:
            travel, passenger = TravelService.remove_passenger(travel, passenger_username)

            # Se le notifica que el chat del viaje ha sido eliminado para ese pasajero
            _notify_chat_removed(travel, passenger)

            return Response({
                    "status": "ok",
                    "message": "Pasajero eliminado del viaje. Asiento liberado."
                }, status=status.HTTP_200_OK)

        except PassengerNotFoundError:
            return Response({
                "status": "error",
                "message": "Pasajero no encontrado.",
                "error_code": ErrorCodes.USER_DONT_EXIST
            }, status=status.HTTP_400_BAD_REQUEST)
        except PassengerNotInTravelError as e:
            logger.warning(f"Passenger not in travel: {str(e)}")
            return Response({
                "status": "error",
                "message": "El pasajero no tiene una solicitud aceptada en este viaje.",
                "error_code": ErrorCodes.NOT_FOUND
            }, status=status.HTTP_404_NOT_FOUND)
        except (Http404, APIException, DjangoValidationError):
            raise
        except Exception as e:
            logger.error(f"Error removing passenger from travel: {str(e)}")
            return Response({"error": "Error removing passenger from travel", "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=500)

    @action(
        detail=True,
        methods=['post'],
        url_path='validate_passenger',
        permission_classes=[IsAuthenticated],
        throttle_scope='validation_code'
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
            request_travel = TravelService.validate_passenger(travel, code)

            return Response({
                "status": "ok",
                "message": f"Pasajero {request_travel.user.username} validado correctamente."
            }, status=status.HTTP_200_OK)

        except PassengerAlreadyValidatedError as e:
            return Response({
                "status": "error",
                "message": f"Pasajero {e.username} ya ha sido validado.",
                "error_code": ErrorCodes.PASSENGER_ALREADY_VALIDATED
            }, status=status.HTTP_400_BAD_REQUEST)
        except PassengerNotAcceptedError as e:
            return Response({
                "status": "error",
                "message": f"Pasajero {e.username} no está en estado aceptado y no puede ser validado.",
                "error_code": ErrorCodes.PASSENGER_NOT_ACCEPTED
            }, status=status.HTTP_400_BAD_REQUEST)
        except InvalidValidationCodeError:
            return Response({
                "status": "error",
                "message": "Código de validación no válido o pasajero no encontrado.",
                "error_code": ErrorCodes.INVALID_VALIDATION_CODE
            }, status=status.HTTP_404_NOT_FOUND)
        except (Http404, APIException, DjangoValidationError):
            raise
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
            unvalidated_count = TravelService.finish_travel(travel)

            return Response({
                "status": "ok",
                "message": f"Viaje finalizado. {unvalidated_count} pasajeros no validados."
            }, status=status.HTTP_200_OK)

        except (Http404, APIException, DjangoValidationError):
            raise
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

        # Solo el creador del viaje puede marcar los puntos de recogida
        if travel.creation_user != request.user:
            return Response({
                "status": "error",
                "message": "No tienes permiso para marcar puntos de recogida en este viaje.",
                "error_code": ErrorCodes.INSUFICIENT_CREDENTIALS
            }, status=status.HTTP_403_FORBIDDEN)

        try:
            TravelService.reach_pickup_point(travel, point_id)
            return Response({
                "status": "ok",
                "message": "Punto de recogida marcado como alcanzado."
            }, status=status.HTTP_200_OK)
        except PickUpPointNotFoundError:
            return Response({
                "status": "error",
                "message": "Punto de recogida no encontrado.",
                "error_code": ErrorCodes.PICKUP_POINT_NOT_FOUND
            }, status=status.HTTP_400_BAD_REQUEST)

# Endpoints para gestionar las solicitudes de los viajes
class RequestTravelsViewSet(OwnedQuerysetMixin, SoftDeleteQuerysetMixin, viewsets.ModelViewSet):
    queryset = RequestTravels.objects.all()
    serializer_class = RequestTravelsSerializer
    permission_classes = [IsAuthenticated]
    # Representa al dueño del viaje y al que ha solicitado la plaza (que ya ha sido aprobada)
    owner_field = ('user', 'id_travel__creation_user')

    # Como no se utilizan put ni post, no se añaden
    http_method_names = ['get', 'patch', 'delete', 'head', 'options']

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
                
                # El servicio libera el asiento y avisa al conductor
                TravelService.cancel_request(instance)

            self.perform_destroy(instance)
            return Response({
                "status": "ok",
                "message": "Solicitud eliminada correctamente."
            }, status=status.HTTP_200_OK)
        except (Http404, APIException, DjangoValidationError):
            raise
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
        
        if new_status_code and request.user != instance.id_travel.creation_user:
            logger.warning(f"User {request.user.username} tried to change status of request {instance.id} without proper credentials.")
            return Response({
                "status": "error",
                "message": "No tienes permiso para cambiar el estado de esta solicitud.",
                "error_code": ErrorCodes.INSUFICIENT_CREDENTIALS
            }, status=status.HTTP_403_FORBIDDEN)

        if new_status_code: # Si se ha cambiado el estado de la solicitud
            try:
                TravelService.change_request_status(instance, new_status_code)

                return Response({
                    "status": "ok",
                    "message": f"Solicitud marcada como {new_status_code}"
                }, status=status.HTTP_200_OK)

            except SeatsFullError:
                return Response({
                    "status": "error",
                    "message": "El viaje ya está completo. No puedes aceptar más pasajeros.",
                    "error_code": ErrorCodes.TRAVEL_IS_FULL
                }, status=status.HTTP_400_BAD_REQUEST)
            except InvalidRequestStatusError:
                return Response({"status": "error", "message": "Código de estado inválido.", "error_code": ErrorCodes.INVALID_REQUEST_STATUS}, status=status.HTTP_400_BAD_REQUEST)
            except StatusNotRequestableError as e:
                # El cambio a ese estado debe hacerse por el metodo correcto
                message = f"El estado -{e.status_code}- no se puede asignar desde aquí."
                if e.gateway:
                    message += f" Se consigue {e.gateway}."
                return Response({
                    "status": "error",
                    "message": message,
                    "error_code": ErrorCodes.STATUS_NOT_REQUESTABLE
                }, status=status.HTTP_400_BAD_REQUEST)
            except InvalidStatusTransitionError as e:
                # El paso al esatdo solicitado es imposible de hacer
                return Response({
                    "status": "error",
                    "message": f"No se puede pasar de -{e.current_status}- a -{e.new_status}-.",
                    "error_code": ErrorCodes.INVALID_STATUS_TRANSITION
                }, status=status.HTTP_400_BAD_REQUEST)
            except (Http404, APIException, DjangoValidationError):
                raise
            except Exception as e:
                logger.error(f"Error: {str(e)}")
                return Response({"status": "error", "message": str(e), "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
        return super().partial_update(request, *args, **kwargs)

# Base comun de los endpoints de lo que depende de un viaje
class TravelChildViewSet(OwnedQuerysetMixin, SoftDeleteQuerysetMixin, viewsets.ModelViewSet):
    """
    Base de los ViewSets de lo que depende de un viaje: puntos de recogida y tipos
    de usuario denegados. Solo el creador del viaje puede tocarlos.
    """
    permission_classes = [IsAuthenticated]
    owner_field = 'id_travel__creation_user'

    # Respuesta comun cuando se intenta tocar un viaje ajeno
    def _not_owner_response(self):
        return Response({
            "status": "error",
            "message": "No tienes permiso para modificar los datos de este viaje.",
            "error_code": ErrorCodes.INSUFICIENT_CREDENTIALS
        }, status=status.HTTP_403_FORBIDDEN)

    # Comprueba la propiedad de los viajes referenciados en el cuerpo ya validado
    def _check_travels(self, serializer, is_many=False):
        rows = serializer.validated_data if is_many else [serializer.validated_data]
        TravelService.assert_travels_belong_to(
            self.request.user, [row.get('id_travel') for row in rows]
        )

    # Se sobreescribe el POST para permitir la creacion de varios de golpe
    def create(self, request, *args, **kwargs):

        # Se comprueba si se ha pasado una lista o un solo objeto para crear varios o solo uno
        is_many = isinstance(request.data, list)

        serializer = self.get_serializer(data=request.data, many=is_many)

        # Se valida primero
        serializer.is_valid(raise_exception=True)

        try:
            self._check_travels(serializer, is_many)
        except NotTravelOwnerError:
            return self._not_owner_response()

        self.perform_create(serializer)

        headers = self.get_success_headers(serializer.data)
        return Response(
            serializer.data,
            status=status.HTTP_201_CREATED,
            headers=headers
        )

    # Se sobreescribe el update para que no se pueda mover una fila propia a un viaje ajeno
    def update(self, request, *args, **kwargs):
        partial = kwargs.pop('partial', False)
        instance = self.get_object()

        serializer = self.get_serializer(instance, data=request.data, partial=partial)
        serializer.is_valid(raise_exception=True)

        try:
            self._check_travels(serializer)
        except NotTravelOwnerError:
            return self._not_owner_response()

        self.perform_update(serializer)
        return Response(serializer.data)


# Endpoint para gestionar los puntos de recogida de los viajes
class PickUpPointsViewSet(TravelChildViewSet):
    queryset = PickUpPoints.objects.all()
    serializer_class = PickUpPointSerializer

# Endpoint para gestionar los usuarios denegados en los viajes
class UsersDeniedViewSet(TravelChildViewSet):
    queryset = UsersDenied.objects.all()
    serializer_class = UsersDeniedSerializer
