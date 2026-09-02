"""
Pruebas de CARACTERIZACION del invariante `remaining_seats`.
"""
from django.test import override_settings
from rest_framework import status
from rest_framework.test import APITestCase

from api.errors import ErrorCodes
from travels.models import RequestTravels, Travel
from travels.tests.factories import create_request, create_travel, create_user
from users.models import Notifications

# El canal en memoria evita depender de Redis al notificar la expulsion del chat
IN_MEMORY_CHANNEL = override_settings(
    CHANNEL_LAYERS={'default': {'BACKEND': 'channels.layers.InMemoryChannelLayer'}}
)


class BaseSeatsTest(APITestCase):
    """Montaje comun: un conductor, un pasajero y un viaje puntual activo."""

    def setUp(self):
        self.driver = create_user("driver")
        self.passenger = create_user("passenger")

    def authenticate(self, user):
        self.client.force_authenticate(user=user)

    def reload(self, travel):
        return Travel.objects.get(pk=travel.pk)


class AcceptRequestTest(BaseSeatsTest):
    """PATCH /api/v1/requesttravel/{id}/  con status='accepted'."""

    def test_accept_pending_request_takes_a_seat(self):
        # CU: el conductor acepta una solicitud pendiente
        travel = create_travel(self.driver, num_seats=3, remaining_seats=3)
        request_travel = create_request(travel, self.passenger, 'pending')
        self.authenticate(self.driver)

        response = self.client.patch(
            f"/api/v1/requesttravel/{request_travel.pk}/",
            {'status': 'accepted'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)

        # El asiento se descuenta
        self.assertEqual(self.reload(travel).remaining_seats, 2)

        request_travel.refresh_from_db()
        self.assertEqual(request_travel.status_id, 'accepted')

        # Se genera un codigo de validacion de 8 caracteres para el pasajero
        self.assertIsNotNone(request_travel.validation_code)
        self.assertEqual(len(request_travel.validation_code), 8)

        # Y se le notifica incluyendo ese codigo
        notifications = Notifications.objects.filter(id_user=self.passenger)
        self.assertEqual(notifications.count(), 1)
        self.assertIn(request_travel.validation_code, notifications.first().content)

    def test_accept_request_on_full_travel_returns_travel_is_full(self):
        # CU: el conductor intenta aceptar cuando ya no quedan plazas
        travel = create_travel(self.driver, num_seats=3, remaining_seats=0)
        request_travel = create_request(travel, self.passenger, 'pending')
        self.authenticate(self.driver)

        response = self.client.patch(
            f"/api/v1/requesttravel/{request_travel.pk}/",
            {'status': 'accepted'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.TRAVEL_IS_FULL)

        # Ni se toca el asiento ni se cambia el estado de la solicitud
        self.assertEqual(self.reload(travel).remaining_seats, 0)
        request_travel.refresh_from_db()
        self.assertEqual(request_travel.status_id, 'pending')
        self.assertIsNone(request_travel.validation_code)

    def test_only_the_driver_can_change_the_status(self):
        travel = create_travel(self.driver, num_seats=3, remaining_seats=3)
        request_travel = create_request(travel, self.passenger, 'pending')
        self.authenticate(self.passenger)  # el pasajero intenta autoaceptarse

        response = self.client.patch(
            f"/api/v1/requesttravel/{request_travel.pk}/",
            {'status': 'accepted'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data['error_code'], ErrorCodes.INSUFICIENT_CREDENTIALS)
        self.assertEqual(self.reload(travel).remaining_seats, 3)


class RejectAcceptedRequestTest(BaseSeatsTest):
    """PATCH /api/v1/requesttravel/{id}/  con status='rejected' sobre una aceptada."""

    def test_reject_accepted_request_releases_a_seat(self):
        # Estado coherente: 3 plazas, 1 ocupada
        travel = create_travel(self.driver, num_seats=3, remaining_seats=2)
        request_travel = create_request(travel, self.passenger, 'accepted')
        self.authenticate(self.driver)

        response = self.client.patch(
            f"/api/v1/requesttravel/{request_travel.pk}/",
            {'status': 'rejected'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.reload(travel).remaining_seats, 3)

        request_travel.refresh_from_db()
        self.assertEqual(request_travel.status_id, 'rejected')
        self.assertEqual(Notifications.objects.filter(id_user=self.passenger).count(), 1)

    def test_reject_accepted_respects_the_guard_after_centralizing(self):
        travel = create_travel(self.driver, num_seats=2, remaining_seats=2)
        request_travel = create_request(travel, self.passenger, 'accepted')
        self.authenticate(self.driver)

        response = self.client.patch(
            f"/api/v1/requesttravel/{request_travel.pk}/",
            {'status': 'rejected'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        # El invariante se respeta: no sube por encima de num_seats
        self.assertEqual(self.reload(travel).remaining_seats, 2)

        # El resto del flujo sigue igual: la solicitud se rechaza y se notifica
        request_travel.refresh_from_db()
        self.assertEqual(request_travel.status_id, 'rejected')
        self.assertEqual(Notifications.objects.filter(id_user=self.passenger).count(), 1)


class CancelRequestTest(BaseSeatsTest):
    """DELETE /api/v1/requesttravel/{id}/ ."""

    def test_cancel_accepted_request_releases_seat_and_warns_the_driver(self):
        travel = create_travel(self.driver, num_seats=3, remaining_seats=2)
        request_travel = create_request(travel, self.passenger, 'accepted')
        self.authenticate(self.passenger)  # el propio pasajero cancela

        response = self.client.delete(f"/api/v1/requesttravel/{request_travel.pk}/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.reload(travel).remaining_seats, 3)

        # Soft delete, la fila sigue existiendo
        request_travel.refresh_from_db()
        self.assertTrue(request_travel.is_deleted)

        self.assertEqual(Notifications.objects.filter(id_user=self.driver).count(), 1)

    def test_cancel_pending_request_does_not_touch_the_seats(self):
        travel = create_travel(self.driver, num_seats=3, remaining_seats=3)
        request_travel = create_request(travel, self.passenger, 'pending')
        self.authenticate(self.passenger)

        response = self.client.delete(f"/api/v1/requesttravel/{request_travel.pk}/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.reload(travel).remaining_seats, 3)
        self.assertEqual(Notifications.objects.filter(id_user=self.driver).count(), 0)


@IN_MEMORY_CHANNEL
class RemovePassengerTest(BaseSeatsTest):
    """POST /api/v1/travel/{id}/remove_passenger/ ."""

    def test_remove_passenger_releases_seat_and_notifies_them(self):
        travel = create_travel(self.driver, num_seats=3, remaining_seats=2)
        request_travel = create_request(travel, self.passenger, 'accepted')
        self.authenticate(self.driver)

        response = self.client.post(
            f"/api/v1/travel/{travel.pk}/remove_passenger/",
            {'user_id': str(self.driver.id), 'passenger': self.passenger.username},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.reload(travel).remaining_seats, 3)

        # La solicitud pasa a rechazada (no se borra)
        request_travel.refresh_from_db()
        self.assertEqual(request_travel.status_id, 'rejected')

        self.assertEqual(Notifications.objects.filter(id_user=self.passenger).count(), 1)

    def test_remove_passenger_with_guard_does_not_overflow(self):

        travel = create_travel(self.driver, num_seats=2, remaining_seats=2)
        create_request(travel, self.passenger, 'accepted')
        self.authenticate(self.driver)

        response = self.client.post(
            f"/api/v1/travel/{travel.pk}/remove_passenger/",
            {'user_id': str(self.driver.id), 'passenger': self.passenger.username},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.reload(travel).remaining_seats, 2)

    def test_remove_passenger_requires_being_the_driver(self):

        travel = create_travel(self.driver, num_seats=3, remaining_seats=2)
        request_travel = create_request(travel, self.passenger, 'accepted')
        intruder = create_user("intruder")
        self.authenticate(intruder)

        response = self.client.post(
            f"/api/v1/travel/{travel.pk}/remove_passenger/",
            {'user_id': str(self.driver.id), 'passenger': self.passenger.username},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data['error_code'], ErrorCodes.INSUFICIENT_CREDENTIALS)

        # Ni se libera el asiento ni se toca la solicitud del pasajero
        self.assertEqual(self.reload(travel).remaining_seats, 2)
        request_travel.refresh_from_db()
        self.assertEqual(request_travel.status_id, 'accepted')

    def test_removing_someone_who_is_not_in_the_travel_returns_404(self):

        travel = create_travel(self.driver, num_seats=3, remaining_seats=3)
        outsider = create_user("no_viaja_conmigo")
        self.authenticate(self.driver)

        response = self.client.post(
            f"/api/v1/travel/{travel.pk}/remove_passenger/",
            {'user_id': str(self.driver.id), 'passenger': outsider.username},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(response.data['error_code'], ErrorCodes.NOT_FOUND)
        # Y no se ha inventado un asiento por el camino
        self.assertEqual(self.reload(travel).remaining_seats, 3)

    def test_an_unknown_username_is_still_told_apart_from_the_previous_case(self):
        """
        Contrapartida: "no existe ese usuario" (400) y "existe pero no viaja
        contigo" (404) son dos cosas distintas y tienen que seguir siendolo. Sin
        esta prueba, unificarlas por descuido pasaria desapercibido.
        """
        travel = create_travel(self.driver, num_seats=3, remaining_seats=3)
        self.authenticate(self.driver)

        response = self.client.post(
            f"/api/v1/travel/{travel.pk}/remove_passenger/",
            {'user_id': str(self.driver.id), 'passenger': 'no_existe_este_usuario'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.USER_DONT_EXIST)


class RequestSeatTest(BaseSeatsTest):
    """POST /api/v1/travel/request-travel/ ."""

    def test_request_seat_creates_the_request_and_notifies_the_driver(self):
        travel = create_travel(self.driver, num_seats=3, remaining_seats=3)
        self.authenticate(self.passenger)

        response = self.client.post(
            "/api/v1/travel/request-travel/",
            {'travel_ids': [str(travel.pk)]},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['requests_created'], 1)

        request_travel = RequestTravels.objects.get(id_travel=travel, user=self.passenger)
        self.assertEqual(request_travel.status_id, 'pending')

        # Solicitar NO reserva asiento: eso solo pasa al aceptar
        self.assertEqual(self.reload(travel).remaining_seats, 3)
        self.assertEqual(Notifications.objects.filter(id_user=self.driver).count(), 1)

    def test_duplicated_request_returns_already_requested(self):
        travel = create_travel(self.driver, num_seats=3, remaining_seats=3)
        create_request(travel, self.passenger, 'pending')
        self.authenticate(self.passenger)

        response = self.client.post(
            "/api/v1/travel/request-travel/",
            {'travel_ids': [str(travel.pk)]},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.ALREADY_REQUESTED)

        # No se crea una segunda solicitud
        self.assertEqual(
            RequestTravels.objects.filter(id_travel=travel, user=self.passenger).count(), 1
        )

    def test_request_seat_on_own_travel_returns_request_own_travel(self):
        travel = create_travel(self.driver, num_seats=3, remaining_seats=3)
        self.authenticate(self.driver)

        response = self.client.post(
            "/api/v1/travel/request-travel/",
            {'travel_ids': [str(travel.pk)]},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.REQUEST_OWN_TRAVEL)
        self.assertEqual(RequestTravels.objects.filter(id_travel=travel).count(), 0)
