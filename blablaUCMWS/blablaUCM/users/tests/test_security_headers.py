"""
Pruebas de las CABECERAS DE SEGURIDAD.
"""
from rest_framework import status
from rest_framework.test import APITestCase

from travels.tests.factories import create_user


class ContentSecurityPolicyTest(APITestCase):

    def setUp(self):
        self.user = create_user("piloto")

    def test_the_response_carries_the_csp_header(self):
        """
        Lo que fija el fallo: que la cabecera SALE. Con
        `SECURE_CONTENT_SECURITY_POLICY` no salia ninguna.
        """
        self.client.force_authenticate(user=self.user)

        response = self.client.get("/api/v1/chats/")

        self.assertIn('Content-Security-Policy', response.headers)

    def test_the_policy_restricts_the_default_source(self):
        self.client.force_authenticate(user=self.user)

        response = self.client.get("/api/v1/chats/")

        self.assertIn("default-src 'self'", response.headers['Content-Security-Policy'])

    def test_it_also_applies_to_unauthenticated_responses(self):
        """
        La cabecera la pone un middleware, asi que no depende de que la peticion
        llegue a autenticarse. Importa porque el HTML que de verdad sirve este
        proyecto —el señuelo del panel— es anonimo.
        """
        response = self.client.get("/api/v1/chats/")

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertIn('Content-Security-Policy', response.headers)

    def test_the_xss_filter_header_is_gone(self):
        self.client.force_authenticate(user=self.user)

        response = self.client.get("/api/v1/chats/")

        self.assertNotIn('X-XSS-Protection', response.headers)
