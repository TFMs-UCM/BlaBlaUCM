"""
Autorizacion por defecto: ningun endpoint del router queda abierto
"""
import uuid

from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import AccessToken

from api.urls import travelRouter, userRouter
from travels.tests.factories import create_user
from users.models import Users

ROUTERS = (userRouter, travelRouter)
FAKE_ID = "00000000-0000-0000-0000-000000000000"

# Los tres endpoints del flujo de verificacion y recuperacion de cuenta. Son
# publicos por necesidad: quien recupera su cuenta no puede estar autenticado
INTENTIONALLY_PUBLIC = {'verification_email', 'verify_code', 'verify_user'}

def registered_viewsets():
    for router in ROUTERS:
        for prefix, viewset, _basename in router.registry:
            yield prefix, viewset

class AnonymousAccessTest(APITestCase):
    """Sin credenciales no se entra a ningun sitio."""

    def test_no_registered_list_endpoint_answers_an_anonymous_caller(self):
        for prefix, _viewset in registered_viewsets():
            url = f"/api/v1/{prefix}/"
            with self.subTest(endpoint=url):
                response = self.client.get(url)
                self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_no_registered_detail_endpoint_answers_an_anonymous_caller(self):
        for prefix, _viewset in registered_viewsets():
            url = f"/api/v1/{prefix}/{FAKE_ID}/"
            with self.subTest(endpoint=url):
                response = self.client.get(url)
                # 401 antes que 404: no se filtra si el recurso existe o no
                self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_no_registered_endpoint_accepts_an_anonymous_write(self):
        for prefix, _viewset in registered_viewsets():
            url = f"/api/v1/{prefix}/"
            with self.subTest(endpoint=url):
                response = self.client.post(url, {}, format='json')
                self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_no_custom_action_answers_an_anonymous_caller_except_the_public_ones(self):
        checked = 0
        for prefix, viewset in registered_viewsets():
            for action in viewset.get_extra_actions():
                method = list(action.mapping.keys())[0]
                if action.detail:
                    url = f"/api/v1/{prefix}/{FAKE_ID}/{action.url_path}/"
                else:
                    url = f"/api/v1/{prefix}/{action.url_path}/"

                if action.url_path in INTENTIONALLY_PUBLIC:
                    continue

                with self.subTest(endpoint=url, method=method):
                    response = getattr(self.client, method)(url)
                    self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
                checked += 1

        # Que el bucle no se quede vacio por un cambio de API de DRF
        self.assertGreater(checked, 15)

    def test_the_public_endpoints_are_exactly_the_three_of_the_recovery_flow(self):
        """
        Contraparte de la lista blanca: que no sobre ni falte ninguno
        """
        public_ones = {
            action.url_path
            for _prefix, viewset in registered_viewsets()
            for action in viewset.get_extra_actions()
            if action.kwargs.get('permission_classes') == []
        }

        self.assertEqual(public_ones, INTENTIONALLY_PUBLIC)

    def test_the_public_endpoints_are_rate_limited(self):
        for _prefix, viewset in registered_viewsets():
            for action in viewset.get_extra_actions():
                if action.url_path not in INTENTIONALLY_PUBLIC:
                    continue
                with self.subTest(endpoint=action.url_path):
                    self.assertIsNotNone(action.kwargs.get('throttle_scope'))

    def test_an_authenticated_caller_does_get_through(self):
        """Contraparte: el 401 de arriba es por falta de credenciales, no porque este todo roto."""
        self.client.force_authenticate(user=create_user("legitima"))

        response = self.client.get("/api/v1/vehicles/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)


class JwtAuthenticationFailureTest(APITestCase):
    """
    `api/authentication.py`. El resto de la suite usa `force_authenticate`, que
    se salta esta clase entera; `test_jwt_end_to_end.py` cubre el camino feliz,
    pero sus tres rutas de fallo no las ejercitaba nadie.

    Importan porque son las que deciden que hacer con un token **valido
    criptograficamente** cuyo usuario ya no sirve.
    """

    def setUp(self):
        self.user = create_user("portadora")
        self.url = "/api/v1/vehicles/"

    def authenticate_with(self, token):
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")

    def test_a_valid_token_is_accepted(self):
        self.authenticate_with(AccessToken.for_user(self.user))

        self.assertEqual(self.client.get(self.url).status_code, status.HTTP_200_OK)

    def test_a_token_without_the_user_claim_is_rejected(self):
        token = AccessToken.for_user(self.user)
        del token['user_id']

        self.authenticate_with(token)

        self.assertEqual(self.client.get(self.url).status_code, status.HTTP_401_UNAUTHORIZED)

    def test_a_token_of_a_user_that_no_longer_exists_is_rejected(self):
        token = AccessToken.for_user(self.user)
        Users.objects.filter(pk=self.user.pk).delete()

        self.authenticate_with(token)

        self.assertEqual(self.client.get(self.url).status_code, status.HTTP_401_UNAUTHORIZED)

    def test_a_token_pointing_at_an_unknown_id_is_rejected(self):
        token = AccessToken.for_user(self.user)
        token['user_id'] = str(uuid.uuid4())

        self.authenticate_with(token)

        self.assertEqual(self.client.get(self.url).status_code, status.HTTP_401_UNAUTHORIZED)

    def test_a_forged_token_is_rejected(self):
        self.authenticate_with("esto.no.es.un.token")

        self.assertEqual(self.client.get(self.url).status_code, status.HTTP_401_UNAUTHORIZED)
