"""
Pruebas de CARACTERIZACION de los viajes y solicitudes vistos desde el usuario.
    GET  /api/v1/users/{id}/travel/?type=pending|past
    GET  /api/v1/users/{id}/my-requests/?type=pending|active|past
    GET  /api/v1/users/{id}/received-requests/
    GET  /api/v1/users/{id}/next_travel/
    POST /api/v1/users/{id}/rate_a_driver/
"""
from datetime import timedelta

from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from api.errors import ErrorCodes
from travels.models import RequestTravels, Travel, TravelStates
from travels.tests.factories import create_request, create_travel, create_user
from users.models import Criteria, DriverRatings

class BaseUserTravelsTest(APITestCase):

    def setUp(self):
        self.user = create_user("owner")
        self.client.force_authenticate(user=self.user)

    def get(self, path, user_id=None):
        return self.client.get(f"/api/v1/users/{user_id or self.user.id}/{path}")

    def move_travel_to(self, travel, days, state=None):
        """Coloca el viaje en el pasado o el futuro sin pasar por full_clean."""
        updates = {'travel_date': timezone.now() + timedelta(days=days)}
        if state:
            updates['state'] = TravelStates.objects.get(code=state)
        Travel.objects.filter(pk=travel.pk).update(**updates)
        return Travel.objects.get(pk=travel.pk)


class UserTravelsTest(BaseUserTravelsTest):

    def test_without_type_returns_every_travel_of_the_user(self):
        create_travel(self.user)
        create_travel(self.user)

        response = self.get("travel/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['count'], 2)

    def test_pending_returns_only_future_active_travels(self):
        future = create_travel(self.user)
        past = self.move_travel_to(create_travel(self.user), days=-10)

        response = self.get("travel/?type=pending")

        ids = {row['id_travel'] for row in response.data['results']}
        self.assertIn(str(future.pk), ids)
        self.assertNotIn(str(past.pk), ids)

    def test_pending_includes_started_travels_even_if_the_date_passed(self):
        started = self.move_travel_to(create_travel(self.user), days=-2, state='started')

        response = self.get("travel/?type=pending")

        ids = {row['id_travel'] for row in response.data['results']}
        self.assertIn(str(started.pk), ids)

    def test_past_returns_finished_or_old_travels(self):
        old = self.move_travel_to(create_travel(self.user), days=-10)
        finished = create_travel(self.user, state='fnd')
        future = create_travel(self.user)

        response = self.get("travel/?type=past")

        ids = {row['id_travel'] for row in response.data['results']}
        self.assertIn(str(old.pk), ids)
        self.assertIn(str(finished.pk), ids)
        self.assertNotIn(str(future.pk), ids)

    def test_excludes_deleted_travels(self):
        travel = create_travel(self.user)
        Travel.objects.filter(pk=travel.pk).update(is_deleted=True)

        response = self.get("travel/")

        self.assertEqual(response.data['count'], 0)

    def test_does_not_include_travels_from_other_drivers(self):
        create_travel(create_user("other_driver"))

        response = self.get("travel/")

        self.assertEqual(response.data['count'], 0)

class MyRequestsTest(BaseUserTravelsTest):

    def setUp(self):
        super().setUp()
        self.driver = create_user("driver")

    def test_without_type_returns_every_request(self):
        create_request(create_travel(self.driver), self.user, 'pending')
        create_request(create_travel(self.driver), self.user, 'accepted')

        response = self.get("my-requests/")

        self.assertEqual(response.data['count'], 2)

    def test_pending_includes_rejected_ones_too(self):
        """
        El filtro `pending` incluye tambien las rechazadas
        (`status__code__in=['pending','rejected']`). Puede ser intencionado
        —mostrar al usuario en que quedo su solicitud— pero el nombre despista.
        """
        pending = create_request(create_travel(self.driver), self.user, 'pending')
        rejected = create_request(create_travel(self.driver), self.user, 'rejected')

        response = self.get("my-requests/?type=pending")

        ids = {row['id'] for row in response.data['results']}
        self.assertIn(str(pending.pk), ids)
        self.assertIn(str(rejected.pk), ids)

    def test_active_returns_only_accepted_ones(self):
        accepted = create_request(create_travel(self.driver), self.user, 'accepted')
        create_request(create_travel(self.driver), self.user, 'pending')

        response = self.get("my-requests/?type=active")

        ids = {row['id'] for row in response.data['results']}
        self.assertEqual(ids, {str(accepted.pk)})

    def test_past_returns_validated_and_unvalidated(self):
        validated = create_request(create_travel(self.driver), self.user, 'validated')
        unvalidated = create_request(create_travel(self.driver), self.user, 'unvalidated')
        create_request(create_travel(self.driver), self.user, 'accepted')

        response = self.get("my-requests/?type=past")

        ids = {row['id'] for row in response.data['results']}
        self.assertEqual(ids, {str(validated.pk), str(unvalidated.pk)})

    def test_excludes_deleted_requests(self):
        request_travel = create_request(create_travel(self.driver), self.user, 'pending')
        RequestTravels.objects.filter(pk=request_travel.pk).update(is_deleted=True)

        response = self.get("my-requests/")

        self.assertEqual(response.data['count'], 0)


class ReceivedRequestsTest(BaseUserTravelsTest):

    def test_returns_only_pending_requests_on_my_travels(self):
        travel = create_travel(self.user)
        pending = create_request(travel, create_user("p1"), 'pending')
        create_request(travel, create_user("p2"), 'accepted')

        response = self.get("received-requests/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        ids = {row['id'] for row in response.data['results']}
        self.assertEqual(ids, {str(pending.pk)})

    def test_does_not_return_requests_on_other_drivers_travels(self):
        other_travel = create_travel(create_user("other_driver"))
        create_request(other_travel, create_user("p1"), 'pending')

        response = self.get("received-requests/")

        self.assertEqual(response.data['count'], 0)


class NextTravelTest(BaseUserTravelsTest):

    def test_without_travels_returns_404(self):
        response = self.get("next_travel/")

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(response.data['error_code'], ErrorCodes.TRAVEL_DONT_EXIST)

    def test_returns_the_created_travels_ordered_by_date(self):
        soon = create_travel(self.user)
        later = create_travel(self.user)
        Travel.objects.filter(pk=later.pk).update(travel_date=timezone.now() + timedelta(days=20))

        response = self.get("next_travel/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        ids = [row['id'] for row in response.data['results']]
        self.assertEqual(ids, [soon.pk, later.pk])

    def test_returns_at_most_three_travels(self):
        for _ in range(5):
            create_travel(self.user)

        response = self.get("next_travel/")

        self.assertEqual(len(response.data['results']), 3)

    def test_a_started_travel_goes_first_and_takes_a_slot(self):
        started = self.move_travel_to(create_travel(self.user), days=1, state='started')
        for _ in range(3):
            create_travel(self.user)

        response = self.get("next_travel/")

        results = response.data['results']
        self.assertEqual(results[0]['id'], started.pk)
        # Con un viaje iniciado el limite baja a 2 acompañantes: 1 + 2 = 3
        self.assertEqual(len(results), 3)

    def test_accepted_requests_appear_marked_and_with_their_code(self):
        driver = create_user("driver")
        request_travel = create_request(create_travel(driver), self.user, 'accepted')
        request_travel.validation_code = "ABCD1234"
        request_travel.save()

        response = self.get("next_travel/")

        row = next(r for r in response.data['results'] if r['is_request'])
        self.assertEqual(row['id'], request_travel.pk)
        self.assertEqual(row['code'], "ABCD1234")
        self.assertEqual(row['status'], 'accepted')

    def test_finished_travels_are_not_returned(self):
        create_travel(self.user, state='fnd')

        response = self.get("next_travel/")

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)


class RateADriverTest(BaseUserTravelsTest):

    def setUp(self):
        super().setUp()
        self.driver = create_user("driver")
        self.travel = create_travel(self.driver)
        self.request_travel = create_request(self.travel, self.user, 'validated')

    def rate(self, user_id=None, **payload):
        return self.client.post(
            f"/api/v1/users/{user_id or self.user.id}/rate_a_driver/", payload, format='json'
        )

    def test_rating_a_validated_travel_stores_the_scores(self):
        response = self.rate(
            results={'punctuality': 9, 'kindness': 7},
            request_travel=str(self.request_travel.pk),
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(DriverRatings.objects.filter(id_driver=self.driver).count(), 2)

    def test_the_request_becomes_unvalidated_so_it_cannot_be_rated_twice(self):
        self.rate(results={'punctuality': 9}, request_travel=str(self.request_travel.pk))

        self.request_travel.refresh_from_db()
        self.assertEqual(self.request_travel.status_id, 'unvalidated')

        # Un segundo intento ya no encuentra la solicitud en estado validated
        second = self.rate(results={'punctuality': 1}, request_travel=str(self.request_travel.pk))
        self.assertEqual(second.status_code, status.HTTP_400_BAD_REQUEST)

    def test_missing_fields_return_400(self):
        response = self.rate(results={'punctuality': 9})

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.MISSING_REQUIRED_FIELD)

    def test_a_request_that_is_not_validated_cannot_be_rated(self):
        pending = create_request(create_travel(self.driver), self.user, 'accepted')

        response = self.rate(results={'punctuality': 9}, request_travel=str(pending.pk))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.TRAVEL_DONT_EXIST)

    def test_unknown_criteria_are_skipped_without_failing(self):
        response = self.rate(
            results={'punctuality': 9, 'NO_EXISTE': 5},
            request_travel=str(self.request_travel.pk),
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(DriverRatings.objects.filter(id_driver=self.driver).count(), 1)

    def test_rating_on_behalf_of_another_user_is_blocked(self):
        """
        La accion valida la solicitud contra `self.get_object()` (el usuario de
        la URL) y nunca ha comprobado `request.user`: con el id de una solicitud
        validada, un tercero podia puntuar en nombre de otro y hundir o inflar
        la nota de un conductor. Ahora `get_queryset` deja fuera a los demas
        usuarios, asi que la URL de la victima ya no resuelve.
        """
        intruder = create_user("intruder")
        self.client.force_authenticate(user=intruder)

        response = self.rate(
            user_id=self.user.id,  # la URL sigue siendo la de la victima
            results={'punctuality': 1},
            request_travel=str(self.request_travel.pk),
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertFalse(DriverRatings.objects.filter(id_driver=self.driver).exists())
        self.request_travel.refresh_from_db()
        self.assertEqual(self.request_travel.status_id, 'validated')
        self.assertEqual(Criteria.objects.filter(code='punctuality').count(), 1)
