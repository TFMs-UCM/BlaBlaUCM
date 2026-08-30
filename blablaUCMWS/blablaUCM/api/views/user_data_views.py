"""
Endpoints de los datos que pertenecen a un usuario: notificaciones, dispositivos, preferencias, valoraciones emitidas y vehiculos.
Todos heredan de OwnedQuerysetMixin, asi que la proteccion viene de serie,
cada uno solo ve y toca lo suyo sin tener que acordarse de comprobarlo en cada metodo
"""
import logging

from rest_framework import status, viewsets
from django.core.exceptions import ValidationError as DjangoValidationError
from django.http import Http404
from rest_framework.exceptions import APIException
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from api.errors import ErrorCodes
from api.ownership import OwnedCreateMixin, OwnedQuerysetMixin
from api.serializers.user_serializer import ( DeviceSerializer, DriverRatingsSerializer, NotificationsSerializer, 
                                            PreferencesSerializer, VehicleSerializer)
from api.soft_delete import SoftDeleteQuerysetMixin
from users.models import Device, DriverRatings, Notifications, Preferences, Vehicles
from users.services.exceptions import (VehicleHasActiveTravelsError, VehicleSeatsInsufficientError)
from users.services.user_service import UserService

# Logger para almacenar los logs
logger = logging.getLogger(__name__)


# Base comun de los datos propios de un usuario
class OwnedDataViewSet(OwnedCreateMixin, OwnedQuerysetMixin, SoftDeleteQuerysetMixin, viewsets.ModelViewSet):
    permission_classes = [IsAuthenticated]

    # El metodo put no se usa, por lo que no se publica
    http_method_names = ['get', 'post', 'patch', 'delete', 'head', 'options']


# Endpoints para gestionar las notificaciones
class NotificationsViewSet(OwnedDataViewSet):
    queryset = Notifications.objects.all()
    serializer_class = NotificationsSerializer

# Endpoints para gestionar las preferencias de los usuarios
class PreferencesViewSet(OwnedDataViewSet):
    queryset = Preferences.objects.all()
    serializer_class = PreferencesSerializer

# Endpoints para gestionar las valoraciones de los conductores
class DriverRatingsViewSet(OwnedDataViewSet):
    queryset = DriverRatings.objects.all()
    serializer_class = DriverRatingsSerializer

# Endpoints para gestionar los dispositivos registrados para notificaciones push
class DeviceViewSet(OwnedDataViewSet):
    queryset = Device.objects.all()
    serializer_class = DeviceSerializer

    # Si el dispositivo ya existe, se actualiza, si no, se crea
    def create(self, request, *args, **kwargs):
        # coge el token fcm
        fcm_token = request.data.get('fcm_token')
        if not fcm_token: # si no hay token, devuelve un error
            return Response(
                {"error": "fcm_token is required", "error_code": ErrorCodes.MISSING_REQUIRED_FIELD},
                status=status.HTTP_400_BAD_REQUEST
            )

        device = UserService.register_device(
            request.user, fcm_token, request.data.get('platform', '')
        )
        serializer = self.get_serializer(device)
        return Response(serializer.data, status=status.HTTP_200_OK)


# Endpoints para gestionar los vehiculos de los usuarios
class VehiclesViewSet(OwnedDataViewSet):
    queryset = Vehicles.objects.all()
    serializer_class = VehicleSerializer

    # Se sobreescribe el metodo partial_update para poder hacer las comprobaciones de asientos necesarias al actualizar un vehiculo
    def partial_update(self, request, *args, **kwargs):
        vehicle = self.get_object()
        new_seats = request.data.get('seats')

        # El numero de asientos es obligatorio para actualizar el vehiculo
        if new_seats is None:
            logger.error("Seats field is required for updating vehicle")
            return Response({"error": "Numero de asientos invalido", "error_code": ErrorCodes.MISSING_REQUIRED_FIELD}, status=status.HTTP_400_BAD_REQUEST)

        try:
            new_seats = int(new_seats)
        except ValueError:
            return Response({"error": "Numero de asientos invalido", "error_code": ErrorCodes.MISSING_REQUIRED_FIELD}, status=status.HTTP_400_BAD_REQUEST)

        try:
            UserService.check_new_seats(request.user, vehicle, new_seats)
        except VehicleSeatsInsufficientError:
            return Response({"error": "El numero de asientos no puede ser menor que 2", "error_code": ErrorCodes.VEHICLE_SEATS_INSUFFICIENT}, status=status.HTTP_400_BAD_REQUEST)
        except VehicleHasActiveTravelsError:
            return Response({"error": {"code": ErrorCodes.VEHICLE_SEATS_INSUFFICIENT, "message":
                "Tiene algun viaje activo asociado a este vehículo con más asientos que los nuevos, modifique el viaje antes de actualizar el vehículo."}}, status=status.HTTP_400_BAD_REQUEST)
        except (Http404, APIException, DjangoValidationError):
            raise
        except Exception as e:
            logger.error(f"Error occurred while checking associated travels for seats: {str(e)}")
            return Response({"error": "Error occurred while checking associated travels for seats", "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

        logger.info(f"Updating vehicle ID: {vehicle.id_vehicle} with new seats: {new_seats}")
        return super().partial_update(request, *args, **kwargs)


    # Se sobreescribe el metodo destroy para hacer las comprobaciones necesarias antes de borrar el vehiculo
    def destroy(self, request, *args, **kwargs):
        """
        Endpoint DELETE /vehicles/{id_vehicle}/
        Elimina el vehiculo indicado, siempre que no tenga un viaje asociado a él
        """
        vehicle = self.get_object()

        # Solo el dueño del vehiculo puede eliminarlo
        if vehicle.id_user != request.user:
            return Response({
                "status": "error",
                "message": "No tienes permiso para borrar este vehiculo.",
                "error_code": ErrorCodes.INSUFICIENT_CREDENTIALS
            }, status=status.HTTP_403_FORBIDDEN)

        # Solo se puede eliminar si no tiene viajes activos asociados a él
        try:
            UserService.check_vehicle_is_free(request.user, vehicle)
        except VehicleHasActiveTravelsError:
            return Response({
                "error": {
                    "code": ErrorCodes.VEHICLE_ASSOCIATED_TO_TRAVEL,
                    "message": "El vehículo tiene viajes asociados, sustituyalo en ellos antes de eliminarlo."
                }
            }, status=status.HTTP_400_BAD_REQUEST)
        except (Http404, APIException, DjangoValidationError):
            raise
        except Exception as e:
            logger.error(f"Error occurred while checking associated travels: {str(e)}")
            return Response({"error": "Error occurred while checking associated travels", "error_code": ErrorCodes.INTERNAL_SERVER_ERROR}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

        return super().destroy(request, *args, **kwargs)
