"""
Pruebas UNITARIAS de TravelService.

A diferencia de las de caracterizacion, estas atacan al servicio directamente,
sin pasar por HTTP: comprueban el invariante `remaining_seats` en aislamiento.
Son las que documentan el contrato del servicio (que devuelve, que lanza).
"""
from django.test import TestCase

from travels.models import Travel
from travels.services.exceptions import (
    InvalidValidationCodeError,
    PassengerAlreadyValidatedError,
    PassengerNotAcceptedError,
    SeatsFullError,
)
from travels.services.travel_service import TravelService
from travels.tests.factories import create_request, create_travel, create_user
from users.models import Notifications


class TravelServiceSeatsTest(TestCase):

    def setUp(self):
        self.driver = create_user("driver")

    def reload(self, travel):
        return Travel.objects.get(pk=travel.pk)

    # --- reserve_seat -----------------------------------------------------

    def test_reserve_seat_takes_one_seat(self):
        travel = create_travel(self.driver, num_seats=3, remaining_seats=3)

        returned = TravelService.reserve_seat(travel.pk)

        self.assertEqual(returned.remaining_seats, 2)
        self.assertEqual(self.reload(travel).remaining_seats, 2)

    def test_reserve_seat_on_full_travel_raises_seats_full(self):
        travel = create_travel(self.driver, num_seats=3, remaining_seats=0)

        with self.assertRaises(SeatsFullError):
            TravelService.reserve_seat(travel.pk)

        # No deja el viaje en negativo
        self.assertEqual(self.reload(travel).remaining_seats, 0)

    def test_reserve_seat_can_take_the_last_seat(self):
        travel = create_travel(self.driver, num_seats=2, remaining_seats=1)

        TravelService.reserve_seat(travel.pk)

        self.assertEqual(self.reload(travel).remaining_seats, 0)

    # --- release_seat -----------------------------------------------------

    def test_release_seat_gives_one_seat_back(self):
        travel = create_travel(self.driver, num_seats=3, remaining_seats=1)

        returned, released = TravelService.release_seat(travel.pk)

        self.assertTrue(released)
        self.assertEqual(returned.remaining_seats, 2)
        self.assertEqual(self.reload(travel).remaining_seats, 2)

    def test_release_seat_does_not_exceed_the_maximum(self):
        """
        El guard centralizado: es la regla que antes solo aplicaban dos de las
        tres rutas de liberacion
        """
        travel = create_travel(self.driver, num_seats=3, remaining_seats=3)

        returned, released = TravelService.release_seat(travel.pk)

        self.assertFalse(released)
        self.assertEqual(returned.remaining_seats, 3)
        self.assertEqual(self.reload(travel).remaining_seats, 3)

    # --- combinadas -------------------------------------------------------

    def test_reserve_and_release_leaves_the_travel_as_it_was(self):
        travel = create_travel(self.driver, num_seats=4, remaining_seats=4)

        TravelService.reserve_seat(travel.pk)
        TravelService.reserve_seat(travel.pk)
        self.assertEqual(self.reload(travel).remaining_seats, 2)

        TravelService.release_seat(travel.pk)
        TravelService.release_seat(travel.pk)
        self.assertEqual(self.reload(travel).remaining_seats, 4)


class TravelServiceValidatePassengerTest(TestCase):
    """
    validate_passenger no tenia ninguna cobertura antes de la fase 3c:
    estas son sus primeras pruebas.
    """

    def setUp(self):
        self.driver = create_user("driver")
        self.passenger = create_user("passenger")
        self.travel = create_travel(self.driver, num_seats=3, remaining_seats=2)

    def create_request_with_code(self, state='accepted', code='ABCD1234'):
        request_travel = create_request(self.travel, self.passenger, state)
        request_travel.validation_code = code
        request_travel.save()
        return request_travel

    def test_validate_accepted_passenger_marks_them_as_validated(self):
        request_travel = self.create_request_with_code()

        returned = TravelService.validate_passenger(self.travel, 'ABCD1234')

        self.assertEqual(returned.pk, request_travel.pk)
        request_travel.refresh_from_db()
        self.assertEqual(request_travel.status_id, 'validated')

    def test_validating_twice_raises_already_validated(self):
        self.create_request_with_code(state='validated')

        with self.assertRaises(PassengerAlreadyValidatedError) as ctx:
            TravelService.validate_passenger(self.travel, 'ABCD1234')

        # La excepcion lleva el username para que el view componga su mensaje
        self.assertEqual(ctx.exception.username, self.passenger.username)

    def test_validating_a_pending_request_raises_not_accepted(self):
        self.create_request_with_code(state='pending')

        with self.assertRaises(PassengerNotAcceptedError):
            TravelService.validate_passenger(self.travel, 'ABCD1234')

    def test_unknown_code_raises_invalid_validation_code(self):
        self.create_request_with_code()

        with self.assertRaises(InvalidValidationCodeError):
            TravelService.validate_passenger(self.travel, 'NOEXISTE')


class TravelServiceFinishTravelTest(TestCase):

    def setUp(self):
        self.driver = create_user("driver")
        self.travel = create_travel(self.driver, num_seats=4, remaining_seats=2)

    def test_finish_marks_not_validated_and_notifies_everyone(self):
        not_validated = create_request(self.travel, create_user(), 'accepted')
        validated = create_request(self.travel, create_user(), 'validated')

        count = TravelService.finish_travel(self.travel)

        self.assertEqual(count, 1)

        # El viaje queda finalizado
        self.assertEqual(Travel.objects.get(pk=self.travel.pk).state_id, 'fnd')

        # El aceptado sin validar pasa a unvalidated, el validado no se toca
        not_validated.refresh_from_db()
        validated.refresh_from_db()
        self.assertEqual(not_validated.status_id, 'unvalidated')
        self.assertEqual(validated.status_id, 'validated')

        # Ambos reciben notificacion, con mensajes distintos
        self.assertEqual(Notifications.objects.filter(id_user=not_validated.user).count(), 1)
        self.assertEqual(Notifications.objects.filter(id_user=validated.user).count(), 1)
        self.assertIn(
            "NO has sido validado",
            Notifications.objects.get(id_user=not_validated.user).content,
        )
        self.assertIn(
            "puntuar al conductor",
            Notifications.objects.get(id_user=validated.user).content,
        )

    def test_finish_without_passengers_does_not_fail(self):
        count = TravelService.finish_travel(self.travel)

        self.assertEqual(count, 0)
        self.assertEqual(Travel.objects.get(pk=self.travel.pk).state_id, 'fnd')
