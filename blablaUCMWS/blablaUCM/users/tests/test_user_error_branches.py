"""
Ramas de error de los endpoints de usuario.
"""
import io
import tempfile
from unittest.mock import patch

from django.core.files.uploadedfile import SimpleUploadedFile
from django.http import Http404
from django.test import override_settings
from PIL import Image
from rest_framework import status
from rest_framework.test import APITestCase

from api.errors import ErrorCodes
from travels.tests.factories import create_user

FAILURE = RuntimeError("fallo inesperado dentro del servicio")

def build_image(name="foto.png"):
    """PNG valido en memoria: `ImageField` lo valida con Pillow antes del servicio."""
    buffer = io.BytesIO()
    Image.new("RGB", (10, 10), color="red").save(buffer, format="PNG")
    buffer.seek(0)
    return SimpleUploadedFile(name, buffer.read(), content_type="image/png")


class BaseErrorBranchTest(APITestCase):

    def setUp(self):
        self.user = create_user("titular")
        self.client.force_authenticate(user=self.user)

    def url(self, suffix=""):
        return f"/api/v1/users/{self.user.id}/{suffix}"

    def call(self, method, url, payload=None):
        send = getattr(self.client, method)
        if payload is None:
            return send(url)
        return send(url, payload, format='json')

    def assert_unexpected_becomes_500(self, target, method, url, payload=None):
        """Un fallo no previsto sale como 500 controlado, no como excepcion cruda."""
        with patch(target, side_effect=FAILURE):
            response = self.call(method, url, payload)

        self.assertEqual(response.status_code, status.HTTP_500_INTERNAL_SERVER_ERROR)
        self.assertEqual(response.data['error_code'], ErrorCodes.INTERNAL_SERVER_ERROR)

    def assert_not_found_is_not_swallowed(self, target, method, url, payload=None):
        """El 404 del framework llega al cliente como 404, no como 500."""
        with patch(target, side_effect=Http404):
            response = self.call(method, url, payload)

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(response.data['error_code'], ErrorCodes.NOT_FOUND)


class UserListAndRetrieveErrorsTest(BaseErrorBranchTest):
    """`list` y `retrieve`, que envuelven a los de DRF."""

    QUERYSET = "api.views.user_views.UsersViewSet.get_queryset"

    def test_the_list_returns_500_when_something_unexpected_fails(self):
        self.assert_unexpected_becomes_500(self.QUERYSET, 'get', "/api/v1/users/")

    def test_the_list_does_not_turn_a_404_into_a_500(self):
        self.assert_not_found_is_not_swallowed(self.QUERYSET, 'get', "/api/v1/users/")

    def test_the_detail_returns_500_when_something_unexpected_fails(self):
        self.assert_unexpected_becomes_500(self.QUERYSET, 'get', self.url())


@override_settings(MEDIA_ROOT=tempfile.mkdtemp())
class ProfilePictureErrorsTest(BaseErrorBranchTest):

    TARGET = "api.views.user_views.UserService.update_profile_picture"

    def test_uploading_returns_500_when_something_unexpected_fails(self):
        # El serializer de imagen valida antes, asi que hay que mandar un fichero
        # valido para llegar hasta el servicio.
        with patch(self.TARGET, side_effect=FAILURE):
            response = self.client.patch(
                self.url("upload-profile_picture/"),
                {"profile_picture": build_image()},
                format='multipart',
            )

        self.assertEqual(response.status_code, status.HTTP_500_INTERNAL_SERVER_ERROR)
        self.assertEqual(response.data['error_code'], ErrorCodes.INTERNAL_SERVER_ERROR)


class OwnedListsErrorsTest(BaseErrorBranchTest):
    """
    Los cinco listados de datos propios. Comparten estructura, y cada uno llama a
    un metodo distinto de `UserService`.
    """

    def test_vehicles_returns_500_when_something_unexpected_fails(self):
        self.assert_unexpected_becomes_500(
            "api.views.user_views.UserService.list_vehicles", 'get', self.url("vehicles/"))

    def test_vehicles_does_not_turn_a_404_into_a_500(self):
        self.assert_not_found_is_not_swallowed(
            "api.views.user_views.UserService.list_vehicles", 'get', self.url("vehicles/"))

    def test_notifications_returns_500_when_something_unexpected_fails(self):
        self.assert_unexpected_becomes_500(
            "api.views.user_views.UserService.list_notifications", 'get', self.url("notifications/"))

    def test_notifications_does_not_turn_a_404_into_a_500(self):
        self.assert_not_found_is_not_swallowed(
            "api.views.user_views.UserService.list_notifications", 'get', self.url("notifications/"))

    def test_the_unread_count_returns_500_when_something_unexpected_fails(self):
        self.assert_unexpected_becomes_500(
            "api.views.user_views.UserService.count_unread_notifications",
            'get', self.url("notifications/unread-count/"))

    def test_the_unread_count_does_not_turn_a_404_into_a_500(self):
        self.assert_not_found_is_not_swallowed(
            "api.views.user_views.UserService.count_unread_notifications",
            'get', self.url("notifications/unread-count/"))

    def test_driver_ratings_returns_500_when_something_unexpected_fails(self):
        self.assert_unexpected_becomes_500(
            "api.views.user_views.UserService.get_driver_ratings", 'get', self.url("driverratings/"))

    def test_driver_ratings_does_not_turn_a_404_into_a_500(self):
        self.assert_not_found_is_not_swallowed(
            "api.views.user_views.UserService.get_driver_ratings", 'get', self.url("driverratings/"))

    def test_preferences_returns_500_when_something_unexpected_fails(self):
        self.assert_unexpected_becomes_500(
            "api.views.user_views.UserService.list_preferences", 'get', self.url("preferences/"))

    def test_preferences_does_not_turn_a_404_into_a_500(self):
        self.assert_not_found_is_not_swallowed(
            "api.views.user_views.UserService.list_preferences", 'get', self.url("preferences/"))


class PreferenceWritesErrorsTest(BaseErrorBranchTest):

    TARGET = "api.views.user_views.UserService.update_preferences"

    def test_updating_preferences_returns_500_when_something_unexpected_fails(self):
        self.assert_unexpected_becomes_500(
            self.TARGET, 'patch', self.url("update-preferences/"), {"preferences": ["music"]})

    def test_updating_preferences_does_not_turn_a_404_into_a_500(self):
        self.assert_not_found_is_not_swallowed(
            self.TARGET, 'patch', self.url("update-preferences/"), {"preferences": ["music"]})


class UserTravelsErrorsTest(BaseErrorBranchTest):
    """Los tres listados de viajes y solicitudes."""

    def test_created_travels_returns_500_when_something_unexpected_fails(self):
        self.assert_unexpected_becomes_500(
            "api.views.user_views.UserService.list_created_travels", 'get', self.url("travel/"))

    def test_created_travels_does_not_turn_a_404_into_a_500(self):
        self.assert_not_found_is_not_swallowed(
            "api.views.user_views.UserService.list_created_travels", 'get', self.url("travel/"))

    def test_my_requests_returns_500_when_something_unexpected_fails(self):
        self.assert_unexpected_becomes_500(
            "api.views.user_views.UserService.list_own_requests", 'get', self.url("my-requests/"))

    def test_my_requests_does_not_turn_a_404_into_a_500(self):
        self.assert_not_found_is_not_swallowed(
            "api.views.user_views.UserService.list_own_requests", 'get', self.url("my-requests/"))

    def test_received_requests_returns_500_when_something_unexpected_fails(self):
        self.assert_unexpected_becomes_500(
            "api.views.user_views.UserService.list_received_requests",
            'get', self.url("received-requests/"))

    def test_received_requests_does_not_turn_a_404_into_a_500(self):
        self.assert_not_found_is_not_swallowed(
            "api.views.user_views.UserService.list_received_requests",
            'get', self.url("received-requests/"))

    def test_the_next_travel_returns_500_when_something_unexpected_fails(self):
        self.assert_unexpected_becomes_500(
            "api.views.user_views.UserService.get_next_travels", 'get', self.url("next_travel/"))

    def test_the_next_travel_does_not_turn_a_404_into_a_500(self):
        self.assert_not_found_is_not_swallowed(
            "api.views.user_views.UserService.get_next_travels", 'get', self.url("next_travel/"))


class RateADriverErrorsTest(BaseErrorBranchTest):

    TARGET = "api.views.user_views.UserService.rate_driver"

    def payload(self):
        return {"results": [{"criteria": "punctuality", "value": 5}], "request_travel": 1}

    def test_rating_returns_500_when_something_unexpected_fails(self):
        self.assert_unexpected_becomes_500(
            self.TARGET, 'post', self.url("rate_a_driver/"), self.payload())

    def test_rating_does_not_turn_a_404_into_a_500(self):
        self.assert_not_found_is_not_swallowed(
            self.TARGET, 'post', self.url("rate_a_driver/"), self.payload())
