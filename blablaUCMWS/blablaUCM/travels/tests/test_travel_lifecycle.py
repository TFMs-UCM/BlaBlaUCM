"""
Pruebas de los metodos del ciclo de vida del viaje que se movieron a
TravelService SIN caracterizar antes: delete_travel, change_pickup_points y reach_pickup_point.
"""
from rest_framework import status
from rest_framework.test import APITestCase

from api.errors import ErrorCodes
from travels.models import PickUpPoints, Travel
from travels.tests.factories import (
    create_periodic_travel,
    create_request,
    create_travel,
    create_user,
)
from users.models import Notifications


class BaseLifecycleTest(APITestCase):

    def setUp(self):
        self.driver = create_user("driver")
        self.passenger = create_user("passenger")

    def authenticate(self, user):
        self.client.force_authenticate(user=user)


class DeleteTravelTest(BaseLifecycleTest):
    """DELETE /api/v1/travel/{id}/ ."""

    def test_deleting_an_active_travel_warns_and_removes_the_requests(self):
        travel = create_travel(self.driver, num_seats=3, remaining_seats=2)
        accepted = create_request(travel, self.passenger, 'accepted')
        other_user = create_user("other")
        pending = create_request(travel, other_user, 'pending')
        self.authenticate(self.driver)

        response = self.client.delete(f"/api/v1/travel/{travel.pk}/")

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)

        # El viaje queda marcado como borrado, no desaparece
        self.assertTrue(Travel.objects.get(pk=travel.pk).is_deleted)

        # Las solicitudes tambien, tanto la aceptada como la pendiente
        accepted.refresh_from_db()
        pending.refresh_from_db()
        self.assertTrue(accepted.is_deleted)
        self.assertTrue(pending.is_deleted)

        # Y se avisa a los dos solicitantes con el mismo mensaje
        self.assertEqual(Notifications.objects.filter(id_user=self.passenger).count(), 1)
        self.assertEqual(Notifications.objects.filter(id_user=other_user).count(), 1)
        self.assertIn(
            "ha sido cancelado",
            Notifications.objects.filter(id_user=self.passenger).first().content,
        )

    def test_deleting_a_finished_travel_keeps_the_requests(self):
        """
        Si el viaje ya no esta activo las solicitudes se mantienen como
        historico y no se notifica a nadie. Esta rama no la habia ejercitado
        ninguna prueba hasta ahora.
        """
        travel = create_travel(self.driver, num_seats=3, remaining_seats=2, state='fnd')
        request_travel = create_request(travel, self.passenger, 'validated')
        self.authenticate(self.driver)

        response = self.client.delete(f"/api/v1/travel/{travel.pk}/")

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertTrue(Travel.objects.get(pk=travel.pk).is_deleted)

        # La solicitud sobrevive y no hay notificaciones
        request_travel.refresh_from_db()
        self.assertFalse(request_travel.is_deleted)
        self.assertEqual(Notifications.objects.filter(id_user=self.passenger).count(), 0)

    def test_deleting_someone_elses_travel_returns_403(self):
        travel = create_travel(self.driver)
        self.authenticate(self.passenger)

        response = self.client.delete(f"/api/v1/travel/{travel.pk}/")

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data['error_code'], ErrorCodes.INSUFICIENT_CREDENTIALS)
        self.assertFalse(Travel.objects.get(pk=travel.pk).is_deleted)


class ChangePickupPointsTest(BaseLifecycleTest):
    """PATCH /api/v1/travel/{id}/change_pickup_points/ ."""

    def pickup_points(self, *directions):
        return [
            {
                'direction': d,
                'order_in_travel': i + 1,
                'lat': 40.45 + i / 100,
                'lng': -3.72 - i / 100,
            }
            for i, d in enumerate(directions)
        ]

    def test_replaces_the_previous_pickup_points(self):
        travel = create_travel(self.driver)
        old_point = PickUpPoints.objects.create(
            id_travel=travel, direction="Parada vieja", order_in_travel=1
        )
        self.authenticate(self.driver)

        response = self.client.patch(
            f"/api/v1/travel/{travel.pk}/change_pickup_points/",
            {'pickup_points': self.pickup_points("Moncloa", "Argüelles")},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)

        # La antigua se marca como borrada, no se elimina
        old_point.refresh_from_db()
        self.assertTrue(old_point.is_deleted)

        active_points = PickUpPoints.objects.filter(
            id_travel=travel, is_deleted=False
        ).order_by('order_in_travel')
        self.assertEqual([p.direction for p in active_points], ["Moncloa", "Argüelles"])
        # Se guardan las coordenadas como punto geografico
        self.assertIsNotNone(active_points.first().point)

    def test_on_a_periodic_travel_returns_error(self):
        travel = create_periodic_travel(self.driver)
        self.authenticate(self.driver)

        response = self.client.patch(
            f"/api/v1/travel/{travel.pk}/change_pickup_points/",
            {'pickup_points': self.pickup_points("Moncloa")},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.TRAVEL_IS_NOT_PUNCTUAL)
        self.assertEqual(
            PickUpPoints.objects.filter(id_travel=travel, is_deleted=False).count(), 0
        )

    def test_empty_list_returns_error(self):
        travel = create_travel(self.driver)
        self.authenticate(self.driver)

        response = self.client.patch(
            f"/api/v1/travel/{travel.pk}/change_pickup_points/",
            {'pickup_points': []},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.MISSING_REQUIRED_FIELD)

    def test_on_someone_elses_travel_returns_403(self):
        travel = create_travel(self.driver)
        self.authenticate(self.passenger)

        response = self.client.patch(
            f"/api/v1/travel/{travel.pk}/change_pickup_points/",
            {'pickup_points': self.pickup_points("Moncloa")},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)


class ReachPickupPointTest(BaseLifecycleTest):
    """POST /api/v1/travel/{id}/reached_pickup_point/ ."""

    def test_marks_the_pickup_point_as_reached(self):
        travel = create_travel(self.driver)
        pickup_point = PickUpPoints.objects.create(
            id_travel=travel, direction="Moncloa", order_in_travel=1
        )
        self.authenticate(self.driver)

        response = self.client.post(
            f"/api/v1/travel/{travel.pk}/reached_pickup_point/",
            {'id_point': str(pickup_point.id_point)},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        pickup_point.refresh_from_db()
        self.assertTrue(pickup_point.is_reached)

    def test_pickup_point_from_another_travel_returns_error(self):
        travel = create_travel(self.driver)
        other_travel = create_travel(self.driver)
        other_travel_point = PickUpPoints.objects.create(
            id_travel=other_travel, direction="Atocha", order_in_travel=1
        )
        self.authenticate(self.driver)

        response = self.client.post(
            f"/api/v1/travel/{travel.pk}/reached_pickup_point/",
            {'id_point': str(other_travel_point.id_point)},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.PICKUP_POINT_NOT_FOUND)
        other_travel_point.refresh_from_db()
        self.assertFalse(other_travel_point.is_reached)

    def test_only_the_driver_can_mark_a_pickup_point(self):
        travel = create_travel(self.driver)
        pickup_point = PickUpPoints.objects.create(
            id_travel=travel, direction="Moncloa", order_in_travel=1
        )
        self.authenticate(self.passenger)

        response = self.client.post(
            f"/api/v1/travel/{travel.pk}/reached_pickup_point/",
            {'id_point': str(pickup_point.id_point)},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data['error_code'], ErrorCodes.INSUFICIENT_CREDENTIALS)
        pickup_point.refresh_from_db()
        self.assertFalse(pickup_point.is_reached)