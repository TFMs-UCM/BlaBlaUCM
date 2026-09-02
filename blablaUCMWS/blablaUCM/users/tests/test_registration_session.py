"""
Pruebas de LA SESION QUE DEVUELVE EL ALTA.
    POST /api/v1/users/verify_code/   (con validate=true)
"""
import re

from django.core import mail
from django.test import override_settings
from rest_framework import status
from rest_framework.test import APITestCase

from travels.tests.factories import create_user

LOCMEM_EMAIL = override_settings(
    EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend'
)

@LOCMEM_EMAIL
class RegistrationSessionTest(APITestCase):

    def setUp(self):
        self.user = create_user("piloto")
        self.user.email = "piloto@ucm.es"
        self.user.set_password("contrasena")
        self.user.save()
        mail.outbox = []

    def token_from_last_email(self):
        body = mail.outbox[-1].body
        match = re.search(r'margin:16px 0;">\s*([A-Za-z0-9]{6})\s*</div>', body)
        self.assertIsNotNone(match, f"No se encontro el token en el correo:\n{body}")
        return match.group(1)

    def request_code(self):
        return self.client.post(
            "/api/v1/users/verification_email/", {'username': "piloto"}, format='json'
        )

    def verify(self, **extra):
        payload = {'username': "piloto", 'token': self.token_from_last_email()}
        payload.update(extra)
        return self.client.post("/api/v1/users/verify_code/", payload, format='json')

    def unverify(self):
        """Deja la cuenta como recien registrada: creada pero sin validar."""
        self.user.is_verify = False
        self.user.save()

    def test_completing_the_registration_returns_the_session(self):
        self.unverify()
        self.request_code()

        response = self.verify(validate=True)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('access', response.data)
        self.assertIn('refresh', response.data)
        self.assertEqual(response.data['user']['username'], "piloto")

    def test_the_account_is_verified_and_the_answer_keeps_saying_OK(self):
        """
        La clave `status` se mantiene: es la que mira la app para dar la
        operacion por buena, y la usan tambien los otros flujos del endpoint.
        """
        self.unverify()
        self.request_code()

        response = self.verify(validate=True)

        self.assertEqual(response.data['status'], "OK")
        self.user.refresh_from_db()
        self.assertTrue(self.user.is_verify)

    def test_an_already_verified_account_does_not_get_a_session(self):
        """
        Aqui esta el limite. La cuenta ya esta en uso y el codigo se pide sin
        autenticacion, asi que canjearlo no puede valer como iniciar sesion.
        """
        self.request_code()

        response = self.verify(validate=True)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertNotIn('access', response.data)
        self.assertNotIn('refresh', response.data)

    def test_resetting_the_password_does_not_get_a_session(self):
        """
        Recuperar la contraseña usa el mismo endpoint y llega igual de lejos
        —cambia la credencial—, pero termina en la pantalla de inicio de sesion.
        """
        self.request_code()

        response = self.verify(password="contrasena-nueva")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertNotIn('access', response.data)

    def test_the_session_returned_works_against_the_api(self):
        """
        No basta con que vengan los tokens: tienen que servir para llamar a la
        api, que es lo que hace la app en cuanto entra al menu.
        """
        self.unverify()
        self.request_code()

        access = self.verify(validate=True).data['access']

        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
        me = self.client.get(f"/api/v1/users/{self.user.id}/")

        self.assertEqual(me.status_code, status.HTTP_200_OK)
