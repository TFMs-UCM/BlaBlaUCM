"""
Ramas de error de los endpoints de viajes
"""
from unittest.mock import patch

from django.http import Http404
from rest_framework import status
from rest_framework.test import APITestCase

from api.errors import ErrorCodes
from travels.models import TravelStates
from travels.tests.factories import create_request, create_travel, create_user

FAILURE = RuntimeError("fallo inesperado dentro del servicio")


class BaseTravelErrorBranchTest(APITestCase):

    def setUp(self):
        self.driver = create_user("conductora")
        self.travel = create_travel(self.driver)
        self.client.force_authenticate(user=self.driver)

    def url(self, suffix=""):
        return f"/api/v1/travel/{self.travel.pk}/{suffix}"

    def call(self, method, url, payload=None):
        send = getattr(self.client, method)
        if payload is None:
            return send(url)
        return send(url, payload, format='json')

    def assert_unexpected_becomes_500(self, target, method, url, payload=None):
        with patch(target, side_effect=FAILURE):
            response = self.call(method, url, payload)

        self.assertEqual(response.status_code, status.HTTP_500_INTERNAL_SERVER_ERROR)

    def assert_not_found_is_not_swallowed(self, target, method, url, payload=None):
        with patch(target, side_effect=Http404):
            response = self.call(method, url, payload)

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)


class TravelWriteErrorsTest(BaseTravelErrorBranchTest):

    # La lista vacia se rechaza antes de llegar al servicio, asi que hay que
    # mandar una parada de verdad para alcanzar las ramas de error
    STOPS = {"pickup_points": [{"direction": "Moncloa", "order_in_travel": 1}]}

    def test_deleting_returns_500_when_something_unexpected_fails(self):
        self.assert_unexpected_becomes_500(
            "api.views.travel_views.TravelService.delete_travel", 'delete', self.url())

    def test_deleting_does_not_turn_a_404_into_a_500(self):
        self.assert_not_found_is_not_swallowed(
            "api.views.travel_views.TravelService.delete_travel", 'delete', self.url())

    def test_editing_returns_500_when_something_unexpected_fails(self):
        self.assert_unexpected_becomes_500(
            "api.views.travel_views.TravelService.edit_travel",
            'patch', self.url("edit/"), {"num_seats": 2})

    def test_editing_does_not_turn_a_404_into_a_500(self):
        self.assert_not_found_is_not_swallowed(
            "api.views.travel_views.TravelService.edit_travel",
            'patch', self.url("edit/"), {"num_seats": 2})

    def test_changing_pickup_points_returns_500_when_something_unexpected_fails(self):
        self.assert_unexpected_becomes_500(
            "api.views.travel_views.TravelService.change_pickup_points",
            'patch', self.url("change_pickup_points/"), self.STOPS)

    def test_changing_pickup_points_does_not_turn_a_404_into_a_500(self):
        self.assert_not_found_is_not_swallowed(
            "api.views.travel_views.TravelService.change_pickup_points",
            'patch', self.url("change_pickup_points/"), self.STOPS)

    def test_an_empty_list_of_pickup_points_is_rejected(self):
        response = self.client.patch(
            self.url("change_pickup_points/"), {"pickup_points": []}, format='json')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.MISSING_REQUIRED_FIELD)


class TravelSearchAndRequestErrorsTest(BaseTravelErrorBranchTest):

    def test_searching_returns_500_when_something_unexpected_fails(self):
        self.assert_unexpected_becomes_500(
            "api.views.travel_views.TravelService.search_travels",
            'post', "/api/v1/travel/search-travels/", {})

    def test_searching_does_not_turn_a_404_into_a_500(self):
        self.assert_not_found_is_not_swallowed(
            "api.views.travel_views.TravelService.search_travels",
            'post', "/api/v1/travel/search-travels/", {})

    def test_requesting_a_seat_returns_500_when_something_unexpected_fails(self):
        passenger = create_user("pasajera")
        self.client.force_authenticate(user=passenger)

        self.assert_unexpected_becomes_500(
            "api.views.travel_views.TravelService.request_seat",
            'post', "/api/v1/travel/request-travel/", {"travel_ids": [str(self.travel.pk)]})


class PassengerManagementErrorsTest(BaseTravelErrorBranchTest):

    def setUp(self):
        super().setUp()
        self.passenger = create_user("pasajero")
        self.request_travel = create_request(self.travel, self.passenger, state='accepted')

    def removal(self):
        # `user_id` es el del CONDUCTOR, no el del pasajero: el endpoint lo
        # contrasta con travel.creation_user
        return {"user_id": str(self.driver.id), "passenger": self.passenger.username}

    def test_removing_a_passenger_returns_500_when_something_unexpected_fails(self):
        self.assert_unexpected_becomes_500(
            "api.views.travel_views.TravelService.remove_passenger",
            'post', self.url("remove_passenger/"), self.removal())

    def test_removing_a_passenger_does_not_turn_a_404_into_a_500(self):
        self.assert_not_found_is_not_swallowed(
            "api.views.travel_views.TravelService.remove_passenger",
            'post', self.url("remove_passenger/"), self.removal())

    def test_validating_a_passenger_returns_500_when_something_unexpected_fails(self):
        self.assert_unexpected_becomes_500(
            "api.views.travel_views.TravelService.validate_passenger",
            'post', self.url("validate_passenger/"), {"code": "ABC123"})

    def test_validating_a_passenger_does_not_turn_a_404_into_a_500(self):
        self.assert_not_found_is_not_swallowed(
            "api.views.travel_views.TravelService.validate_passenger",
            'post', self.url("validate_passenger/"), {"code": "ABC123"})

    def test_finishing_the_travel_returns_500_when_something_unexpected_fails(self):
        self.assert_unexpected_becomes_500(
            "api.views.travel_views.TravelService.finish_travel",
            'post', self.url("finish_travel/"))

    def test_finishing_the_travel_does_not_turn_a_404_into_a_500(self):
        self.assert_not_found_is_not_swallowed(
            "api.views.travel_views.TravelService.finish_travel",
            'post', self.url("finish_travel/"))

    DETAILS = "api.views.travel_views.PickUpPointSerializer"

    def test_the_details_return_500_when_something_unexpected_fails(self):
        self.assert_unexpected_becomes_500(self.DETAILS, 'get', self.url("get_travel_details/"))

    def test_a_404_inside_the_details_is_swallowed_by_the_outer_except(self):
        with patch(self.DETAILS, side_effect=Http404):
            response = self.client.get(self.url("get_travel_details/"))

        self.assertEqual(response.status_code, status.HTTP_500_INTERNAL_SERVER_ERROR)


class RequestTravelErrorsTest(BaseTravelErrorBranchTest):
    """`RequestTravelsViewSet`: cancelar la solicitud y cambiarle el estado."""

    def setUp(self):
        super().setUp()
        self.passenger = create_user("solicitante")
        self.request_travel = create_request(self.travel, self.passenger)

    def request_url(self):
        return f"/api/v1/requesttravel/{self.request_travel.pk}/"

    def test_cancelling_returns_500_when_something_unexpected_fails(self):
        self.client.force_authenticate(user=self.passenger)

        self.assert_unexpected_becomes_500(
            "api.views.travel_views.TravelService.cancel_request", 'delete', self.request_url())

    def test_cancelling_does_not_turn_a_404_into_a_500(self):
        self.client.force_authenticate(user=self.passenger)

        self.assert_not_found_is_not_swallowed(
            "api.views.travel_views.TravelService.cancel_request", 'delete', self.request_url())

    def test_changing_the_status_returns_500_when_something_unexpected_fails(self):
        self.assert_unexpected_becomes_500(
            "api.views.travel_views.TravelService.change_request_status",
            'patch', self.request_url(), {"status": "accepted"})

    def test_changing_the_status_does_not_turn_a_404_into_a_500(self):
        self.assert_not_found_is_not_swallowed(
            "api.views.travel_views.TravelService.change_request_status",
            'patch', self.request_url(), {"status": "accepted"})


class OnlyOneStartedTravelTest(APITestCase):

    def setUp(self):
        self.driver = create_user("conductor")
        self.travel = create_travel(self.driver)
        self.client.force_authenticate(user=self.driver)

    def test_the_creator_can_update_their_travel(self):
        response = self.client.patch(
            f"/api/v1/travel/{self.travel.pk}/", {"origin": "Atocha"}, format='json')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.travel.refresh_from_db()
        self.assertEqual(self.travel.origin, "Atocha")

    def test_a_second_travel_cannot_be_started_while_another_is_in_progress(self):
        started = create_travel(self.driver)
        started.state = TravelStates.objects.get(code='started')
        started.save()

        response = self.client.patch(
            f"/api/v1/travel/{self.travel.pk}/", {"state": "started"}, format='json')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.TRAVEL_ALREADY_STARTED)

    def test_someone_else_cannot_update_the_travel(self):
        intruder = create_user("intrusa")
        self.client.force_authenticate(user=intruder)

        response = self.client.patch(
            f"/api/v1/travel/{self.travel.pk}/", {"origin": "Atocha"}, format='json')

        self.assertIn(
            response.status_code,
            (status.HTTP_403_FORBIDDEN, status.HTTP_404_NOT_FOUND),
        )
