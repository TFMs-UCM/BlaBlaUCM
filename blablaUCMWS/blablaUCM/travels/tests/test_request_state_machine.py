"""
Pruebas del CICLO DE VIDA de una solicitud de viaje.
La tabla que se fija aquí es:
    pending   -> accepted, rejected
    accepted  -> validated, unvalidated, rejected
    validated -> unvalidated
    rejected, unvalidated -> (nada, son finales)
"""
from rest_framework import status
from rest_framework.test import APITestCase

from travels.models import RequestStates, RequestTravels, Travel
from travels.services.exceptions import InvalidStatusTransitionError
from travels.services.travel_service import TravelService
from travels.tests.factories import create_request, create_travel, create_user

# Todas las combinaciones que la tabla NO permite, sin contar repetir el estado
# actual (que es una operacion vacia y se prueba aparte)
FORBIDDEN_TRANSITIONS = [
    ('pending', 'validated'),
    ('pending', 'unvalidated'),
    ('accepted', 'pending'),
    ('validated', 'pending'),
    ('validated', 'accepted'),
    ('validated', 'rejected'),
    ('rejected', 'pending'),
    ('rejected', 'accepted'),
    ('rejected', 'validated'),
    ('rejected', 'unvalidated'),
    ('unvalidated', 'pending'),
    ('unvalidated', 'accepted'),
    ('unvalidated', 'validated'),
    ('unvalidated', 'rejected'),
]


class BaseStateMachineTest(APITestCase):

    def setUp(self):
        self.driver = create_user("driver")
        self.passenger = create_user("passenger")
        self.travel = create_travel(self.driver, num_seats=3)
        self.client.force_authenticate(user=self.driver)

    def request_row(self, state_row='pending'):
        return create_request(self.travel, self.passenger, state_row)

    def patch(self, request_travel, new_state):
        return self.client.patch(
            f"/api/v1/requesttravel/{request_travel.id}/",
            {'status': new_state},
            format='json',
        )

    def seats_left(self):
        self.travel.refresh_from_db()
        return self.travel.remaining_seats


class ForbiddenTransitionsTest(BaseStateMachineTest):

    def test_every_forbidden_transition_is_rejected(self):
        for current, new_state in FORBIDDEN_TRANSITIONS:
            with self.subTest(transition=f"{current} -> {new_state}"):
                request_row = self.request_row(current)

                response = self.patch(request_row, new_state)

                self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
                request_row.refresh_from_db()
                self.assertEqual(request_row.status.code, current)

    def test_the_error_names_both_states(self):
        # El mensaje tiene que distinguirse del de "codigo de estado invalido":
        # aqui el estado existe, lo que no vale es el salto
        request_row = self.request_row('rejected')

        response = self.patch(request_row, 'accepted')

        self.assertIn('rejected', response.data['message'])
        self.assertIn('accepted', response.data['message'])

    def test_a_status_that_does_not_exist_is_still_a_different_error(self):
        request_row = self.request_row('pending')

        response = self.patch(request_row, 'inventado')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('inválido', response.data['message'])


class AllowedTransitionsTest(BaseStateMachineTest):

    def test_pending_to_accepted(self):
        request_row = self.request_row('pending')

        response = self.patch(request_row, 'accepted')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        request_row.refresh_from_db()
        self.assertEqual(request_row.status.code, 'accepted')
        self.assertIsNotNone(request_row.validation_code)

    def test_pending_to_rejected(self):
        request_row = self.request_row('pending')

        response = self.patch(request_row, 'rejected')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        request_row.refresh_from_db()
        self.assertEqual(request_row.status.code, 'rejected')

    def test_accepted_to_rejected(self):
        request_row = self.request_row('accepted')

        response = self.patch(request_row, 'rejected')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        request_row.refresh_from_db()
        self.assertEqual(request_row.status.code, 'rejected')

    def test_accepted_to_validated_and_unvalidated(self):
        """
        Son transiciones legitimas del dominio, pero no se piden por la API
        """
        for new_state in ('validated', 'unvalidated'):
            with self.subTest(new_state=new_state):
                request_row = self.request_row('accepted')

                TravelService.change_request_status(request_row, new_state, from_api=False)

                request_row.refresh_from_db()
                self.assertEqual(request_row.status.code, new_state)

    def test_validated_to_unvalidated(self):
        request_row = self.request_row('validated')

        TravelService.change_request_status(request_row, 'unvalidated', from_api=False)

        request_row.refresh_from_db()
        self.assertEqual(request_row.status.code, 'unvalidated')

    def test_repeating_the_current_status_is_not_an_error(self):
        """
        Idempotencia: si la aplicación manda dos veces "aceptar",
        la segunda no puede responder un error de algo que ya salió bien.
        """
        request_row = self.request_row('pending')
        self.patch(request_row, 'accepted')
        seats_after_accepting = self.seats_left()

        response = self.patch(request_row, 'accepted')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        # Y sobre todo: no reserva un segundo asiento
        self.assertEqual(self.seats_left(), seats_after_accepting)


class SeatAccountingTest(BaseStateMachineTest):
    """
    El asiento tiene que volver por todos los caminos que sacan de 'accepted',
    no solo por el que estaba escrito.
    """

    def test_accepting_takes_a_seat_and_rejecting_gives_it_back(self):
        request_row = self.request_row('pending')
        free_seats = self.seats_left()

        self.patch(request_row, 'accepted')
        self.assertEqual(self.seats_left(), free_seats - 1)

        self.patch(request_row, 'rejected')
        self.assertEqual(self.seats_left(), free_seats)

    def test_the_seat_can_not_be_leaked_through_pending(self):
        request_row = self.request_row('pending')
        free_seats = self.seats_left()
        self.patch(request_row, 'accepted')

        response = self.patch(request_row, 'pending')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(self.seats_left(), free_seats - 1)
        request_row.refresh_from_db()
        self.assertEqual(request_row.status.code, 'accepted')

    def test_validating_does_not_give_the_seat_back(self):
        # El pasajero ha viajado: su plaza sigue consumida
        request_row = self.request_row('pending')
        self.patch(request_row, 'accepted')
        occupied = self.seats_left()

        self.patch(request_row, 'validated')

        self.assertEqual(self.seats_left(), occupied)


class ValidationCodeCanNotBeBypassedTest(BaseStateMachineTest):

    def test_validate_passenger_still_requires_the_right_code(self):
        request_row = self.request_row('accepted')
        RequestTravels.objects.filter(pk=request_row.pk).update(validation_code="ABCD1234")

        response = self.client.post(
            f"/api/v1/travel/{self.travel.id_travel}/validate_passenger/",
            {'code': "OTRO5678"},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        request_row.refresh_from_db()
        self.assertEqual(request_row.status.code, 'accepted')

    def test_a_rejected_passenger_can_not_be_validated_by_any_route(self):
        request_row = self.request_row('rejected')
        RequestTravels.objects.filter(pk=request_row.pk).update(validation_code="ABCD1234")

        self.assertEqual(self.patch(request_row, 'validated').status_code,
                         status.HTTP_400_BAD_REQUEST)

        response = self.client.post(
            f"/api/v1/travel/{self.travel.id_travel}/validate_passenger/",
            {'code': "ABCD1234"},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

        request_row.refresh_from_db()
        self.assertEqual(request_row.status.code, 'rejected')


class StatusesTheApiCanNotRequestTest(BaseStateMachineTest):

    def test_the_api_can_not_ask_for_validated(self):
        request_row = self.request_row('accepted')

        response = self.patch(request_row, 'validated')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        request_row.refresh_from_db()
        self.assertEqual(request_row.status.code, 'accepted')

    def test_the_api_can_not_ask_for_unvalidated(self):
        request_row = self.request_row('accepted')

        response = self.patch(request_row, 'unvalidated')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        request_row.refresh_from_db()
        self.assertEqual(request_row.status.code, 'accepted')

    def test_the_error_says_where_it_is_actually_done(self):
        # Es el unico de los tres errores de estado que puede decir por donde se
        # hace, y decirlo es la diferencia entre un "no" util y uno inutil
        request_row = self.request_row('accepted')

        response = self.patch(request_row, 'validated')

        self.assertIn('validated', response.data['message'])
        self.assertIn('código de validación', response.data['message'])

    def test_not_even_to_leave_it_as_it_is(self):
        """
        Ni siquiera repitiendo el estado actual: si un estado no se puede pedir,
        no se puede pedir nunca. El endpoint no conoce esa palabra.
        """
        request_row = self.request_row('validated')

        response = self.patch(request_row, 'validated')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_what_the_app_does_send_still_works(self):
        # La contrapartida: la aplicacion solo manda estos dos
        for initial_state, new_state in (('pending', 'accepted'), ('pending', 'rejected')):
            with self.subTest(transition=f"{initial_state} -> {new_state}"):
                request_row = self.request_row(initial_state)

                response = self.patch(request_row, new_state)

                self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_the_domain_machine_is_untouched(self):
        """
        Lo que se ha cerrado es la puerta, no la transición: por dentro sigue
        siendo posible, que es lo que necesitan `validate_passenger` y
        `finish_travel`.
        """
        request_row = self.request_row('accepted')

        TravelService.change_request_status(request_row, 'validated', from_api=False)

        request_row.refresh_from_db()
        self.assertEqual(request_row.status.code, 'validated')

    def test_the_domain_table_still_applies_internally(self):
        # `from_api=False` levanta una restriccion, no las dos
        request_row = self.request_row('rejected')

        with self.assertRaises(InvalidStatusTransitionError):
            TravelService.change_request_status(request_row, 'validated', from_api=False)


class ServiceLevelTest(APITestCase):
    """
    La tabla vive en el servicio, así que se comprueba también sin pasar por HTTP.
    """

    def setUp(self):
        self.driver = create_user("driver")
        self.passenger = create_user("passenger")
        self.travel = create_travel(self.driver)

    def test_the_service_raises_on_a_forbidden_transition(self):
        request_row = create_request(self.travel, self.passenger, 'rejected')

        with self.assertRaises(InvalidStatusTransitionError) as ctx:
            TravelService.change_request_status(request_row, 'accepted')

        self.assertEqual(ctx.exception.current_status, 'rejected')
        self.assertEqual(ctx.exception.new_status, 'accepted')

    def test_the_table_covers_every_state_in_the_catalog(self):
        """
        Si se siembra un estado nuevo y nadie lo añade a la tabla, esta
        prueba avisa: un estado sin entrada se comportaría como final y sus
        transiciones se rechazarían todas en silencio.
        """
        from_catalog = set(
            RequestStates.objects.filter(is_deleted=False).values_list('code', flat=True)
        )

        self.assertEqual(from_catalog, set(TravelService.ALLOW_TRANSITIONS))
