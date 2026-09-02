"""
Pruebas de regresion de seguridad sobre la superficie que publica la API de viajes
"""
from rest_framework import status
from rest_framework.test import APITestCase

from travels.models import RequestTravels, Travel
from travels.tests.factories import (
    create_request,
    create_travel,
    create_user,
    create_vehicle,
)

TRAVEL_URL = "/api/v1/travel/"
REQUEST_URL = "/api/v1/requesttravel/"


class BaseSurfaceTest(APITestCase):
    """
    Tres actores: el conductor, el pasajero que le ha pedido plaza y un tercero
    que no tiene relacion con el viaje
    """

    def setUp(self):
        self.driver = create_user("driver")
        self.passenger = create_user("passenger")
        self.stranger = create_user("stranger")

        self.travel = create_travel(self.driver)
        self.request = create_request(self.travel, self.passenger)


class PutIsNotPublishedTest(BaseSurfaceTest):

    def test_put_on_a_travel_is_not_allowed(self):
        self.client.force_authenticate(user=self.stranger)

        response = self.client.put(f"{TRAVEL_URL}{self.travel.id_travel}/", {}, format='json')

        self.assertEqual(response.status_code, status.HTTP_405_METHOD_NOT_ALLOWED)

    def test_put_on_a_request_is_not_allowed(self):
        self.client.force_authenticate(user=self.driver)

        response = self.client.put(f"{REQUEST_URL}{self.request.id}/", {}, format='json')

        self.assertEqual(response.status_code, status.HTTP_405_METHOD_NOT_ALLOWED)

    def test_put_is_not_allowed_even_for_the_owner(self):
        # No es una comprobacion de permisos: el verbo no existe para nadie
        self.client.force_authenticate(user=self.driver)

        response = self.client.put(f"{TRAVEL_URL}{self.travel.id_travel}/", {}, format='json')

        self.assertEqual(response.status_code, status.HTTP_405_METHOD_NOT_ALLOWED)

    def test_the_verbs_that_the_app_uses_still_work(self):
        # La contrapartida: cerrar PUT no puede haberse llevado por delante PATCH
        self.client.force_authenticate(user=self.driver)

        response = self.client.patch(
            f"{TRAVEL_URL}{self.travel.id_travel}/", {'origin': "Atocha"}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.travel.refresh_from_db()
        self.assertEqual(self.travel.origin, "Atocha")

    def test_patching_someone_elses_travel_still_gives_403(self):
        self.client.force_authenticate(user=self.stranger)

        response = self.client.patch(
            f"{TRAVEL_URL}{self.travel.id_travel}/", {'origin': "Atocha"}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)


class AuditFieldsAreReadOnlyTest(BaseSurfaceTest):

    def test_a_travel_cannot_be_deleted_through_patch(self):
        self.client.force_authenticate(user=self.driver)

        response = self.client.patch(
            f"{TRAVEL_URL}{self.travel.id_travel}/", {'is_deleted': True}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.travel.refresh_from_db()
        self.assertFalse(self.travel.is_deleted)

    def test_a_request_cannot_be_deleted_through_patch(self):
        self.client.force_authenticate(user=self.passenger)

        response = self.client.patch(
            f"{REQUEST_URL}{self.request.id}/", {'is_deleted': True}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.request.refresh_from_db()
        self.assertFalse(self.request.is_deleted)

    def test_deleted_at_cannot_be_written_either(self):
        self.client.force_authenticate(user=self.driver)

        self.client.patch(
            f"{TRAVEL_URL}{self.travel.id_travel}/",
            {'deleted_at': "2020-01-01T00:00:00Z"},
            format='json',
        )

        self.travel.refresh_from_db()
        self.assertIsNone(self.travel.deleted_at)

    def test_deleting_properly_still_works(self):
        # El borrado sigue existiendo, por su verbo y con sus comprobaciones
        self.client.force_authenticate(user=self.driver)

        response = self.client.delete(f"{TRAVEL_URL}{self.travel.id_travel}/")

        self.assertIn(response.status_code, (status.HTTP_200_OK, status.HTTP_204_NO_CONTENT))
        self.travel.refresh_from_db()
        self.assertTrue(self.travel.is_deleted)

class RequestListIsFilteredTest(BaseSurfaceTest):

    def setUp(self):
        super().setUp()
        # Un viaje y una solicitud con los que ninguno de los tres tiene nada que ver
        self.other_driver = create_user("other_driver")
        self.other_travel = create_travel(self.other_driver)
        self.other_request = create_request(self.other_travel, create_user("other_passenger"))

    def _listed_ids(self):
        response = self.client.get(REQUEST_URL)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        payload = response.data.get('results', response.data)
        return {str(row['id']) for row in payload}

    def test_the_passenger_only_sees_their_own_requests(self):
        self.client.force_authenticate(user=self.passenger)

        self.assertEqual(self._listed_ids(), {str(self.request.id)})

    def test_the_driver_sees_the_requests_of_their_travels(self):
        # El segundo dueño legitimo de la fila, y el motivo de que `owner_field` admita una tupla
        self.client.force_authenticate(user=self.driver)

        self.assertEqual(self._listed_ids(), {str(self.request.id)})

    def test_a_stranger_sees_nothing(self):
        self.client.force_authenticate(user=self.stranger)

        self.assertEqual(self._listed_ids(), set())

    def test_someone_elses_request_is_not_reachable_by_id(self):
        self.client.force_authenticate(user=self.passenger)

        response = self.client.get(f"{REQUEST_URL}{self.other_request.id}/")

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

class RequestPatchAuthorizationTest(BaseSurfaceTest):

    def test_patching_someone_elses_request_gives_404(self):
        # Ya no hace falta llegar a la comprobacion: el queryset filtrado deja la fila fuera de alcance
        self.client.force_authenticate(user=self.stranger)

        response = self.client.patch(
            f"{REQUEST_URL}{self.request.id}/", {'is_deleted': True}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.request.refresh_from_db()
        self.assertFalse(self.request.is_deleted)

    def test_the_passenger_cannot_accept_their_own_request(self):
        # Alcanza la fila (es suya) pero no es el conductor
        self.client.force_authenticate(user=self.passenger)

        response = self.client.patch(
            f"{REQUEST_URL}{self.request.id}/", {'status': 'accepted'}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.request.refresh_from_db()
        self.assertEqual(self.request.status.code, 'pending')

    def test_the_driver_still_accepts_and_rejects(self):
        self.client.force_authenticate(user=self.driver)

        response = self.client.patch(
            f"{REQUEST_URL}{self.request.id}/", {'status': 'accepted'}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.request.refresh_from_db()
        self.assertEqual(self.request.status.code, 'accepted')

    def test_the_passenger_still_cancels_their_request(self):
        self.client.force_authenticate(user=self.passenger)

        response = self.client.delete(f"{REQUEST_URL}{self.request.id}/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.request.refresh_from_db()
        self.assertTrue(self.request.is_deleted)

class ValidationCodeVisibilityTest(BaseSurfaceTest):

    def setUp(self):
        super().setUp()
        RequestTravels.objects.filter(pk=self.request.pk).update(validation_code="ABC12345")

    def _code_seen_by(self, user):
        self.client.force_authenticate(user=user)
        response = self.client.get(f"{REQUEST_URL}{self.request.id}/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        return response.data['validation_code']

    def test_the_owner_of_the_request_sees_the_code(self):
        # Es quien lo tiene que enseñar para que le validen
        self.assertEqual(self._code_seen_by(self.passenger), "ABC12345")

    def test_the_driver_does_not_see_the_code(self):
        # El conductor lo teclea mirando la pantalla del pasajero, no la API
        self.assertIsNone(self._code_seen_by(self.driver))

    def test_the_code_cannot_be_written(self):
        self.client.force_authenticate(user=self.passenger)

        self.client.patch(
            f"{REQUEST_URL}{self.request.id}/",
            {'validation_code': "OTRO"},
            format='json',
        )

        self.request.refresh_from_db()
        self.assertEqual(self.request.validation_code, "ABC12345")

    def test_the_passenger_still_sees_the_code_in_my_requests(self):
        """
        `/users/{id}/my-requests/` sirve el mismo serializer por otra ruta, y esa
        pasa por `UsersViewSet.paginated_response`, que construia el serializer
        sin contexto. Sin la peticion no hay a quien comparar y el pasajero
        se quedaba sin ver su propio codigo.
        """
        self.client.force_authenticate(user=self.passenger)

        response = self.client.get(f"/api/v1/users/{self.passenger.id}/my-requests/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        rows = response.data.get('results', response.data)
        self.assertEqual(rows[0]['validation_code'], "ABC12345")

    def test_the_driver_does_not_see_the_code_in_received_requests(self):
        self.client.force_authenticate(user=self.driver)

        response = self.client.get(f"/api/v1/users/{self.driver.id}/received-requests/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        rows = response.data.get('results', response.data)
        self.assertIsNone(rows[0]['validation_code'])

class NestedUserIsReducedTest(BaseSurfaceTest):

    def test_the_travel_list_does_not_leak_the_drivers_email(self):
        self.client.force_authenticate(user=self.stranger)

        response = self.client.get(TRAVEL_URL)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        payload = response.data.get('results', response.data)
        driver_user = payload[0]['creation_user']

        self.assertNotIn('email', driver_user)
        self.assertNotIn('name', driver_user)
        self.assertNotIn('surname1', driver_user)
        self.assertNotIn('has_2FA', driver_user)

    def test_the_travel_list_keeps_what_the_app_uses(self):
        self.client.force_authenticate(user=self.stranger)

        response = self.client.get(TRAVEL_URL)
        payload = response.data.get('results', response.data)
        driver_user = payload[0]['creation_user']

        # `id` es el unico que la app lee sin valor por defecto
        self.assertIn('id', driver_user)
        self.assertEqual(driver_user['username'], "driver")
        self.assertIn('user_type', driver_user)
        self.assertIn('profile_picture_url', driver_user)

    def test_the_request_list_does_not_leak_the_passengers_email(self):
        self.client.force_authenticate(user=self.driver)

        response = self.client.get(REQUEST_URL)
        payload = response.data.get('results', response.data)
        passenger_user = payload[0]['user']

        self.assertNotIn('email', passenger_user)
        self.assertEqual(passenger_user['username'], "passenger")

    def test_the_own_account_still_shows_its_email(self):
        self.client.force_authenticate(user=self.passenger)

        response = self.client.get(f"/api/v1/users/{self.passenger.id}/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['email'], self.passenger.email)

class VehicleMustBeOwnTest(APITestCase):

    def setUp(self):
        self.driver = create_user("driver")
        self.victim = create_user("victim")
        self.own_vehicle = create_vehicle(self.driver)
        self.victim_vehicle = create_vehicle(self.victim)
        self.client.force_authenticate(user=self.driver)

    def payload(self, vehicle):
        from django.utils import timezone
        from datetime import timedelta

        return {
            'origin': "Moncloa",
            'destination': "Facultad de Informatica",
            'origin_lat': 40.4350,
            'origin_lng': -3.7190,
            'destination_lat': 40.4530,
            'destination_lng': -3.7280,
            'duration_minutes': 25,
            'num_seats': 3,
            'remaining_seats': 3,
            'travel_date': (timezone.now() + timedelta(days=3)).isoformat(),
            'state': 'active',
            'vehicle_id': str(vehicle.id_vehicle),
            'is_periodic': False,
        }

    def test_a_travel_cannot_be_created_with_someone_elses_vehicle(self):
        response = self.client.post(TRAVEL_URL, self.payload(self.victim_vehicle), format='json')

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertFalse(Travel.objects.exists())

    def test_a_travel_with_an_own_vehicle_still_works(self):
        response = self.client.post(TRAVEL_URL, self.payload(self.own_vehicle), format='json')

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(Travel.objects.get().vehicle_id, self.own_vehicle.id_vehicle)
