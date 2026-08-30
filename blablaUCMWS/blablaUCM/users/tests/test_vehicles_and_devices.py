"""
Vehiculos y dispositivos: reglas de negocio de `user_data_views.py`.
"""
from unittest.mock import patch

from django.db import IntegrityError, transaction
from django.http import Http404
from rest_framework import status
from rest_framework.test import APITestCase

from api.errors import ErrorCodes
from api.serializers.user_serializer import VehicleSerializer
from travels.tests.factories import create_travel, create_user, create_vehicle

FAILURE = RuntimeError("fallo inesperado dentro del servicio")


class BaseVehicleTest(APITestCase):

    def setUp(self):
        self.user = create_user("conductor")
        self.client.force_authenticate(user=self.user)

    def url(self, vehicle):
        return f"/api/v1/vehicles/{vehicle.id_vehicle}/"


class UpdateVehicleSeatsTest(BaseVehicleTest):

    CHECK = "api.views.user_data_views.UserService.check_new_seats"

    def setUp(self):
        super().setUp()
        self.vehicle = create_vehicle(self.user, seats=4)

    def test_the_number_of_seats_is_required(self):
        response = self.client.patch(self.url(self.vehicle), {"color": "Azul"}, format='json')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.MISSING_REQUIRED_FIELD)

    def test_a_non_numeric_number_of_seats_is_rejected(self):
        response = self.client.patch(self.url(self.vehicle), {"seats": "muchos"}, format='json')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.MISSING_REQUIRED_FIELD)

    def test_it_cannot_drop_below_the_minimum_of_two_seats(self):
        response = self.client.patch(self.url(self.vehicle), {"seats": 1}, format='json')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.VEHICLE_SEATS_INSUFFICIENT)

    def test_it_cannot_drop_below_the_seats_of_an_active_travel(self):
        # create_travel monta un viaje activo de 3 plazas con su propio vehiculo
        travel = create_travel(self.user, num_seats=3)

        response = self.client.patch(
            f"/api/v1/vehicles/{travel.vehicle.id_vehicle}/", {"seats": 3}, format='json')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(
            response.data['error']['code'], ErrorCodes.VEHICLE_SEATS_INSUFFICIENT)

    def test_a_valid_number_of_seats_is_saved(self):
        response = self.client.patch(self.url(self.vehicle), {"seats": 5}, format='json')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.vehicle.refresh_from_db()
        self.assertEqual(self.vehicle.seats, 5)

    def test_an_unexpected_failure_returns_500(self):
        with patch(self.CHECK, side_effect=FAILURE):
            response = self.client.patch(self.url(self.vehicle), {"seats": 4}, format='json')

        self.assertEqual(response.status_code, status.HTTP_500_INTERNAL_SERVER_ERROR)
        self.assertEqual(response.data['error_code'], ErrorCodes.INTERNAL_SERVER_ERROR)

    def test_a_404_is_not_turned_into_a_500(self):
        with patch(self.CHECK, side_effect=Http404):
            response = self.client.patch(self.url(self.vehicle), {"seats": 4}, format='json')

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(response.data['error_code'], ErrorCodes.NOT_FOUND)


class DeleteVehicleTest(BaseVehicleTest):

    CHECK = "api.views.user_data_views.UserService.check_vehicle_is_free"

    def test_a_free_vehicle_is_deleted(self):
        vehicle = create_vehicle(self.user)

        response = self.client.delete(self.url(vehicle))

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)

    def test_a_vehicle_with_an_active_travel_cannot_be_deleted(self):
        travel = create_travel(self.user)

        response = self.client.delete(f"/api/v1/vehicles/{travel.vehicle.id_vehicle}/")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(
            response.data['error']['code'], ErrorCodes.VEHICLE_ASSOCIATED_TO_TRAVEL)

    def test_an_unexpected_failure_returns_500(self):
        vehicle = create_vehicle(self.user)

        with patch(self.CHECK, side_effect=FAILURE):
            response = self.client.delete(self.url(vehicle))

        self.assertEqual(response.status_code, status.HTTP_500_INTERNAL_SERVER_ERROR)
        self.assertEqual(response.data['error_code'], ErrorCodes.INTERNAL_SERVER_ERROR)

    def test_a_404_is_not_turned_into_a_500(self):
        vehicle = create_vehicle(self.user)

        with patch(self.CHECK, side_effect=Http404):
            response = self.client.delete(self.url(vehicle))

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(response.data['error_code'], ErrorCodes.NOT_FOUND)

    def test_the_explicit_owner_check_still_protects_if_the_queryset_stops_filtering(self):
        """
        La comprobacion `vehicle.id_user != request.user` de `destroy` no se
        alcanza por la API, porque `OwnedQuerysetMixin` ya deja fuera lo ajeno:
        el intento normal da 404, no 403.

        Se simula que el queryset dejara de filtrar sustituyendo `get_object`.
        Es artificial a proposito: prueba la defensa en profundidad, no el
        camino real.
        """
        victim = create_user("victima")
        foreign_vehicle = create_vehicle(victim)

        # Por la via normal ni siquiera se ve
        self.assertEqual(
            self.client.delete(self.url(foreign_vehicle)).status_code,
            status.HTTP_404_NOT_FOUND,
        )

        with patch(
            "api.views.user_data_views.VehiclesViewSet.get_object",
            return_value=foreign_vehicle,
        ):
            response = self.client.delete(self.url(foreign_vehicle))

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data['error_code'], ErrorCodes.INSUFICIENT_CREDENTIALS)


class LicensePlateUniquenessTest(BaseVehicleTest):
    """
    La unicidad no se puede dejar en el `unique=True` del modelo, y de hecho el
    serializer lo desactiva a proposito (`extra_kwargs` con `validators: []`).
    El motivo es el soft delete: la restriccion de la base de datos no distingue
    una matricula en uso de otra de un vehiculo borrado, y sin este validador no
    se podria volver a dar de alta la matricula de un coche que se dio de baja.
    """

    def vehicle_payload(self, license_plate):
        from users.models import EnvTypes

        return {
            "brand": "Seat",
            "model": "Leon",
            "license_plate": license_plate,
            "color": "Blanco",
            "seats": 4,
            "id_user": str(self.user.id),
            "env_sticker": EnvTypes.objects.get(code='eco').code,
        }

    def test_a_free_license_plate_is_accepted(self):
        response = self.client.post(
            "/api/v1/vehicles/", self.vehicle_payload("1111AAA"), format='json')

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_a_license_plate_already_in_use_is_rejected_with_409(self):
        existing = create_vehicle(self.user)

        response = self.client.post(
            "/api/v1/vehicles/", self.vehicle_payload(existing.license_plate), format='json')

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)
        self.assertEqual(response.data['error_code'], ErrorCodes.LICENSE_PLATE_ALREADY_EXISTS)

    def test_the_plate_of_someone_elses_vehicle_is_also_rejected(self):
        """La unicidad es global, no por usuario: una matricula es de un coche."""
        other = create_user("ajeno")
        foreign = create_vehicle(other)

        response = self.client.post(
            "/api/v1/vehicles/", self.vehicle_payload(foreign.license_plate), format='json')

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)

    def test_a_vehicle_can_keep_its_own_plate_when_updated(self):
        """Al actualizar hay que excluirse a uno mismo, o nadie podria editar nada."""
        vehicle = create_vehicle(self.user)

        response = self.client.patch(
            self.url(vehicle),
            {"license_plate": vehicle.license_plate, "seats": 4},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_the_validator_lets_the_plate_of_a_deleted_vehicle_through(self):
        """
        El validador mira `is_deleted=False`, asi que da por libre la matricula
        de un vehiculo dado de baja. Es justo para lo que se escribio, y por eso
        el serializer desactiva el `UniqueValidator` de DRF.
        """
        retired = create_vehicle(self.user)
        retired.is_deleted = True
        retired.save()

        serializer = VehicleSerializer(
            data=self.vehicle_payload(retired.license_plate),
            context={'request': self.client.request().wsgi_request},
        )

        self.assertTrue(serializer.is_valid(), serializer.errors)

    def test_but_the_database_still_rejects_it_and_the_insert_explodes(self):

        retired = create_vehicle(self.user)
        plate = retired.license_plate
        retired.is_deleted = True
        retired.save()

        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                self.client.post(
                    "/api/v1/vehicles/", self.vehicle_payload(plate), format='json')


class RegisterDeviceTest(APITestCase):

    def setUp(self):
        self.user = create_user("movil")
        self.client.force_authenticate(user=self.user)

    def test_the_fcm_token_is_required(self):
        response = self.client.post("/api/v1/devices/", {"platform": "android"}, format='json')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.MISSING_REQUIRED_FIELD)

    def test_registering_a_device_returns_200(self):
        response = self.client.post(
            "/api/v1/devices/", {"fcm_token": "token-abc", "platform": "android"}, format='json')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(self.user.devices.filter(fcm_token="token-abc").exists())
