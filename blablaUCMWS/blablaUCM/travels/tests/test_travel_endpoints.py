"""
Pruebas de los endpoints de viaje que quedaban sin cubrir a nivel HTTP.
    GET  /api/v1/travel/{id}/get_travel_details/
    POST /api/v1/travel/{id}/validate_passenger/
    POST /api/v1/travel/{id}/finish_travel/
"""
from datetime import timedelta

from rest_framework import status
from rest_framework.test import APITestCase

from api.errors import ErrorCodes
from travels.models import PickUpPoints, RequestTravels, Travel, UsersDenied
from travels.tests.factories import create_request, create_travel, create_user
from users.models import Criteria, DriverRatings


class TravelDetailsTest(APITestCase):
    """GET /api/v1/travel/{id}/get_travel_details/ ."""

    def setUp(self):
        self.driver = create_user("driver")
        self.passenger = create_user("passenger")
        self.travel = create_travel(self.driver, num_seats=4, remaining_seats=3)
        self.client.force_authenticate(user=self.passenger)

    def details(self, travel=None, **params):
        query = "&".join(f"{k}={v}" for k, v in params.items())
        suffix = f"?{query}" if query else ""
        return self.client.get(
            f"/api/v1/travel/{(travel or self.travel).pk}/get_travel_details/{suffix}"
        )

    def test_returns_the_driver_and_the_empty_ratings(self):
        response = self.details()

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['driver']['username'], "driver")
        self.assertEqual(response.data['ratings']['results'], {})

    def test_includes_the_ratings_computed_by_the_stored_procedure(self):
        DriverRatings.objects.create(
            id_user=self.passenger,
            id_driver=self.driver,
            criteria=Criteria.objects.get(code='punctuality'),
            score=8,
        )

        response = self.details()

        self.assertEqual(response.data['ratings']['results']['punctuality'], 8.0)
        self.assertEqual(response.data['ratings']['count'], 1.0)

    def test_lists_the_pickup_points_in_order(self):
        PickUpPoints.objects.create(id_travel=self.travel, direction="Segunda", order_in_travel=2)
        PickUpPoints.objects.create(id_travel=self.travel, direction="Primera", order_in_travel=1)

        response = self.details()

        directions = [p['direction'] for p in response.data['pickup_points']]
        self.assertEqual(directions, ["Primera", "Segunda"])

    def test_lists_only_the_accepted_passengers(self):
        accepted = create_user("aceptado")
        create_request(self.travel, accepted, 'accepted')
        create_request(self.travel, create_user("pendiente"), 'pending')

        response = self.details()

        usernames = [p['username'] for p in response.data['passengers']]
        self.assertEqual(usernames, ["aceptado"])

    def test_is_requested_reflects_the_caller_own_request(self):
        self.assertFalse(self.details().data['is_requested'])

        create_request(self.travel, self.passenger, 'pending')

        self.assertTrue(self.details().data['is_requested'])

    def test_reports_the_denied_roles(self):
        UsersDenied.objects.create(id_travel=self.travel, user_type_id='prof')

        response = self.details()

        self.assertEqual(response.data['denied_roles'], ['prof'])

    def test_returns_the_coordinates_as_plain_numbers(self):
        response = self.details()

        # El viaje de la factoria no lleva puntos: se devuelven a null
        self.assertIsNone(response.data['origin_lat'])
        self.assertIsNone(response.data['destination_lng'])

    def test_next_travels_is_empty_unless_it_is_requested(self):
        response = self.details()

        self.assertEqual(response.data['next_travels'], {})

    def test_next_travels_returns_the_upcoming_ones_of_the_series(self):
        child = create_travel(self.driver, num_seats=4, remaining_seats=4)
        Travel.objects.filter(pk=child.pk).update(
            id_origin_travel=self.travel,
            travel_date=self.travel.travel_date + timedelta(days=7),
        )

        response = self.details(future_travels="true")

        self.assertIn(str(child.pk), response.data['next_travels'])
        self.assertFalse(response.data['next_travels'][str(child.pk)]['is_requested'])

    def test_an_unknown_travel_returns_500(self):
        """
        COMPORTAMIENTO ACTUAL: un id inexistente cae en el `except` generico y
        sale un 500 en vez de un 404
        """
        import uuid

        response = self.client.get(f"/api/v1/travel/{uuid.uuid4()}/get_travel_details/")

        self.assertEqual(response.status_code, status.HTTP_500_INTERNAL_SERVER_ERROR)


class ValidatePassengerEndpointTest(APITestCase):
    """POST /api/v1/travel/{id}/validate_passenger/ ."""

    def setUp(self):
        self.driver = create_user("driver")
        self.passenger = create_user("passenger")
        self.travel = create_travel(self.driver, num_seats=3, remaining_seats=2)
        self.request_travel = create_request(self.travel, self.passenger, 'accepted')
        self.request_travel.validation_code = "ABCD1234"
        self.request_travel.save()
        self.client.force_authenticate(user=self.driver)

    def validate(self, code, travel=None):
        return self.client.post(
            f"/api/v1/travel/{(travel or self.travel).pk}/validate_passenger/",
            {'code': code},
            format='json',
        )

    def test_a_valid_code_validates_the_passenger(self):
        response = self.validate("ABCD1234")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.request_travel.refresh_from_db()
        self.assertEqual(self.request_travel.status_id, 'validated')

    def test_an_empty_code_returns_400(self):
        response = self.validate("   ")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.MISSING_REQUIRED_FIELD)

    def test_only_the_driver_can_validate(self):
        self.client.force_authenticate(user=self.passenger)

        response = self.validate("ABCD1234")

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data['error_code'], ErrorCodes.INSUFICIENT_CREDENTIALS)
        self.request_travel.refresh_from_db()
        self.assertEqual(self.request_travel.status_id, 'accepted')

    def test_an_unknown_code_returns_404(self):
        response = self.validate("NOEXISTE")

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(response.data['error_code'], ErrorCodes.INVALID_VALIDATION_CODE)

    def test_validating_twice_returns_already_validated(self):
        self.validate("ABCD1234")

        response = self.validate("ABCD1234")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.PASSENGER_ALREADY_VALIDATED)
        self.assertIn(self.passenger.username, response.data['message'])

    def test_a_pending_request_cannot_be_validated(self):
        
        pending = create_request(self.travel, create_user("otro"), 'pending')
        pending.validation_code = "PEND1234"
        pending.save()

        response = self.validate("PEND1234")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.PASSENGER_NOT_ACCEPTED)
        self.assertIn("otro", response.data['message'])

        pending.refresh_from_db()
        self.assertEqual(pending.status_id, 'pending')

    def test_a_code_of_another_travel_is_not_accepted(self):
        other_travel = create_travel(self.driver, num_seats=3, remaining_seats=3)

        response = self.validate("ABCD1234", travel=other_travel)

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)


class FinishTravelEndpointTest(APITestCase):
    """POST /api/v1/travel/{id}/finish_travel/ ."""

    def setUp(self):
        self.driver = create_user("driver")
        self.travel = create_travel(self.driver, num_seats=4, remaining_seats=2)
        self.client.force_authenticate(user=self.driver)

    def finish(self, travel=None):
        return self.client.post(
            f"/api/v1/travel/{(travel or self.travel).pk}/finish_travel/", {}, format='json'
        )

    def test_finishing_reports_how_many_were_not_validated(self):
        create_request(self.travel, create_user("p1"), 'accepted')
        create_request(self.travel, create_user("p2"), 'validated')

        response = self.finish()

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn("1 pasajeros no validados", response.data['message'])
        self.assertEqual(Travel.objects.get(pk=self.travel.pk).state_id, 'fnd')

    def test_only_the_driver_can_finish_the_travel(self):
        intruder = create_user("intruder")
        self.client.force_authenticate(user=intruder)

        response = self.finish()

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data['error_code'], ErrorCodes.INSUFICIENT_CREDENTIALS)
        self.assertEqual(Travel.objects.get(pk=self.travel.pk).state_id, 'active')

    def test_finishing_a_travel_without_passengers_works(self):
        response = self.finish()

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn("0 pasajeros", response.data['message'])

    def test_accepted_requests_become_unvalidated(self):
        request_travel = create_request(self.travel, create_user("p1"), 'accepted')

        self.finish()

        request_travel.refresh_from_db()
        self.assertEqual(request_travel.status_id, 'unvalidated')

    def test_finishing_twice_leaves_it_finished(self):
        self.finish()

        response = self.finish()

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(Travel.objects.get(pk=self.travel.pk).state_id, 'fnd')
        self.assertEqual(
            RequestTravels.objects.filter(id_travel=self.travel, status__code='accepted').count(), 0
        )
