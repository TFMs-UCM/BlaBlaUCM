"""
Pruebas de CARACTERIZACION del endpoint de edicion de viajes.
    PATCH /api/v1/travel/{id}/edit/
"""
from datetime import timedelta

from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from api.errors import ErrorCodes
from travels.models import PickUpPoints, Travel, UsersDenied
from travels.tests.factories import (
    create_periodic_travel,
    create_request,
    create_travel,
    create_user,
    create_vehicle,
)


class BaseEditTest(APITestCase):

    def setUp(self):
        self.driver = create_user("driver")
        self.passenger = create_user("passenger")

    def authenticate(self, user):
        self.client.force_authenticate(user=user)

    def reload(self, travel):
        return Travel.objects.get(pk=travel.pk)

    def send_edit(self, travel, **extra):
        """
        Manda el PATCH con el cuerpo minimo que envia la app: origen, destino,
        fecha y tipo de viaje siempre viajan aunque no hayan cambiado.
        """
        data = {
            'origin': travel.origin,
            'destination': travel.destination,
            'travel_date': travel.travel_date.isoformat(),
            'is_periodic': travel.is_periodic,
        }
        data.update(extra)
        return self.client.patch(f"/api/v1/travel/{travel.pk}/edit/", data, format='json')


class EditPermissionsTest(BaseEditTest):

    def test_editing_without_being_the_creator_returns_403(self):
        travel = create_travel(self.driver)
        self.authenticate(self.passenger)

        response = self.send_edit(travel, duration=99)

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data['error_code'], ErrorCodes.INSUFICIENT_CREDENTIALS)
        self.assertEqual(self.reload(travel).duration_minutes, 25)


class EditSeatsTest(BaseEditTest):

    def test_increasing_seats_recalculates_the_remaining_ones(self):
        # 3 plazas con 1 ocupada -> al subir a 5, quedan 4 libres
        travel = create_travel(self.driver, num_seats=3, remaining_seats=2)
        self.authenticate(self.driver)

        response = self.send_edit(travel, seats=5)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        updated = self.reload(travel)
        self.assertEqual(updated.num_seats, 5)
        self.assertEqual(updated.remaining_seats, 4)

    def test_reducing_seats_below_the_occupied_ones_returns_error(self):
        # 4 plazas con 2 ocupadas: no se puede bajar a 1
        travel = create_travel(self.driver, num_seats=4, remaining_seats=2)
        self.authenticate(self.driver)

        response = self.send_edit(travel, seats=1)

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.SEATS_BELOW_OCCUPIED)
        self.assertEqual(self.reload(travel).num_seats, 4)

    def test_reducing_seats_on_a_periodic_travel_returns_error(self):
        travel = create_periodic_travel(self.driver, num_seats=3)
        self.authenticate(self.driver)

        response = self.send_edit(travel, seats=2)

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.TRAVEL_IS_NOT_PUNCTUAL)
        self.assertEqual(self.reload(travel).num_seats, 3)


class EditPunctualTravelTest(BaseEditTest):

    def test_change_duration(self):
        travel = create_travel(self.driver)
        self.authenticate(self.driver)

        response = self.send_edit(travel, duration=45)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.reload(travel).duration_minutes, 45)

    def test_change_origin_and_destination(self):
        travel = create_travel(self.driver)
        self.authenticate(self.driver)

        response = self.send_edit(
            travel,
            origin="Atocha",
            destination="Ciudad Universitaria",
            origin_lat=40.4068,
            origin_lng=-3.6891,
            destination_lat=40.4489,
            destination_lng=-3.7280,
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        updated = self.reload(travel)
        self.assertEqual(updated.origin, "Atocha")
        self.assertEqual(updated.destination, "Ciudad Universitaria")
        self.assertIsNotNone(updated.origin_point)

    def test_unknown_vehicle_returns_404(self):
        travel = create_travel(self.driver)
        self.authenticate(self.driver)

        response = self.send_edit(travel, vehicle_id="00000000-0000-0000-0000-000000000000")

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(response.data['error_code'], ErrorCodes.VEHICLE_DONT_EXIST)

    def test_changing_vehicle_notifies_the_accepted_passengers(self):
        travel = create_travel(self.driver, num_seats=3, remaining_seats=2)
        create_request(travel, self.passenger, 'accepted')
        other_vehicle = create_vehicle(self.driver, seats=5)
        self.authenticate(self.driver)

        response = self.send_edit(travel, vehicle_id=str(other_vehicle.id_vehicle))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.reload(travel).vehicle_id, other_vehicle.id_vehicle)
        self.assertEqual(self.passenger.notifications.count(), 1)

    def test_replace_denied_user_types(self):
        travel = create_travel(self.driver)
        self.authenticate(self.driver)

        response = self.send_edit(travel, users_deny=['prof'])

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        active = UsersDenied.objects.filter(id_travel=travel, is_deleted=False)
        self.assertEqual([ud.user_type_id for ud in active], ['prof'])


class EditDateTest(BaseEditTest):

    def test_changing_the_date_with_occupied_seats_returns_error(self):
        travel = create_travel(self.driver, num_seats=3, remaining_seats=2)
        self.authenticate(self.driver)
        new_date = (timezone.now() + timedelta(days=10)).isoformat()

        response = self.send_edit(travel, travel_date=new_date)

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.SEATS_BELOW_OCCUPIED)

    def test_changing_the_date_without_occupied_seats(self):
        travel = create_travel(self.driver, num_seats=3, remaining_seats=3)
        self.authenticate(self.driver)
        new_date = timezone.now() + timedelta(days=10)

        response = self.send_edit(travel, travel_date=new_date.isoformat())

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.reload(travel).travel_date.date(), new_date.date())

    def test_omitting_travel_date_leaves_it_untouched(self):

        travel = create_travel(self.driver, num_seats=3, remaining_seats=3)
        original_date = self.reload(travel).travel_date
        self.authenticate(self.driver)

        response = self.client.patch(
            f"/api/v1/travel/{travel.pk}/edit/",
            {'origin': travel.origin, 'destination': travel.destination, 'is_periodic': False},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.reload(travel).travel_date, original_date)

    def test_omitting_the_date_works_even_with_occupied_seats(self):

        travel = create_travel(self.driver, num_seats=3, remaining_seats=1)
        self.authenticate(self.driver)

        response = self.client.patch(
            f"/api/v1/travel/{travel.pk}/edit/",
            {'origin': travel.origin, 'destination': travel.destination,
             'duration': 45, 'is_periodic': False},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.reload(travel).duration_minutes, 45)


class EditTravelTypeTest(BaseEditTest):

    def test_switching_to_periodic_without_end_date_returns_error(self):
        travel = create_travel(self.driver)
        self.authenticate(self.driver)

        response = self.send_edit(travel, is_periodic=True, periodic_interval=7)

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.TO_DATE_REQUIRED)
        self.assertFalse(self.reload(travel).is_periodic)

    def test_switching_to_periodic_with_invalid_interval_returns_error(self):
        travel = create_travel(self.driver)
        self.authenticate(self.driver)
        end_date = (travel.travel_date + timedelta(days=30)).date().isoformat()

        response = self.send_edit(
            travel, is_periodic=True, periodic_interval=40, end_periodic_date=end_date
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.INVALID_PERIODIC_INTERVAL)

    def test_switching_from_punctual_to_periodic_creates_the_child_travels(self):
        travel = create_travel(self.driver, num_seats=3, remaining_seats=3)
        # Una parada del padre, para comprobar que se copia a los hijos
        PickUpPoints.objects.create(
            id_travel=travel, direction="Parada 1", order_in_travel=1, point=None
        )
        self.authenticate(self.driver)
        end_date = (travel.travel_date + timedelta(days=21)).date().isoformat()

        response = self.send_edit(
            travel, is_periodic=True, periodic_interval=7, end_periodic_date=end_date
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)

        parent = self.reload(travel)
        self.assertTrue(parent.is_periodic)
        self.assertEqual(parent.periodic_interval, 7)

        # Se crean 3 hijos (dias 7, 14 y 21) y heredan la parada del padre
        children = Travel.objects.filter(id_origin_travel=travel)
        self.assertEqual(children.count(), 3)
        for child in children:
            self.assertEqual(child.num_seats, parent.num_seats)
            self.assertEqual(child.remaining_seats, parent.num_seats)
            self.assertEqual(PickUpPoints.objects.filter(id_travel=child).count(), 1)

    def test_switching_from_periodic_to_punctual_affects_the_whole_series(self):
        travel = create_periodic_travel(self.driver, num_seats=3, interval=7, weeks=3)
        self.authenticate(self.driver)

        response = self.send_edit(travel, is_periodic=False)

        self.assertEqual(response.status_code, status.HTTP_200_OK)

        parent = self.reload(travel)
        self.assertFalse(parent.is_periodic)
        self.assertIsNone(parent.periodic_interval)

        # Ningun viaje de la serie sigue marcado como periodico
        self.assertFalse(Travel.objects.filter(is_periodic=True).exists())
