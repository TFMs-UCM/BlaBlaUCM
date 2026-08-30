"""
Pruebas del FORMATO ADMITIDO EN EL NOMBRE DE USUARIO (USERNAME_REGEX).
    AuthService.assert_username_is_acceptable        (la regla en si)
    POST  /api/v1/register/                          (alta con usuario y contraseña)
    POST  /api/v1/auth/google/register/              (alta con Google)
    PATCH /api/v1/users/{id}/                        (cambio de nombre desde el perfil)
"""
from unittest.mock import patch

from django.test import TestCase, override_settings
from rest_framework import status
from rest_framework.test import APITestCase

from api.errors import ErrorCodes
from travels.tests.factories import create_user
from users.models import USERNAME_ERROR_MESSAGE, Users
from users.services.auth_service import AuthService
from users.services.exceptions import InvalidUsernameError

# Contraseña que cumple los cuatro validadores de AUTH_PASSWORD_VALIDATORS
GOOD_PASSWORD = "Kx7pq2"

ANY_DOMAIN = override_settings(ALLOWED_DOMAINS=['*'])

# Nombres que no cumplen `^[\w.-]{3,20}$`, cada uno por un motivo distinto
REJECTED = {
    'demasiado_corto': "ab",
    'demasiado_largo': "a" * 21,
    'con_arroba': "ana@ucm.es",
    'con_espacio': "con espacio",
    'vacio': "",
    'solo_espacios': "   ",
}


class UsernameFormatRuleTest(TestCase):
    """La regla en el servicio, que es donde se decide"""

    def test_the_rejected_names_raise(self):
        for motivo, username in REJECTED.items():
            with self.subTest(motivo=motivo):
                with self.assertRaises(InvalidUsernameError):
                    AuthService.assert_username_is_acceptable(username)

    def test_a_missing_name_is_rejected_and_does_not_blow_up(self):
        """
        None llega cuando la peticion no trae el campo
        """
        with self.assertRaises(InvalidUsernameError):
            AuthService.assert_username_is_acceptable(None)

    def test_the_accepted_names_do_not_raise(self):
        """
        Contrapartida obligatoria, la regla no se aprueba rechazandolo todo
        """
        for username in ["ana", "ana.garcia", "ana-garcia", "ana_garcia_99", "a" * 20]:
            with self.subTest(username=username):
                # No lanza
                AuthService.assert_username_is_acceptable(username)


@ANY_DOMAIN
class RegistrationUsernameFormatTest(APITestCase):
    """Puerta 1: el alta con usuario y contraseña."""

    def register(self, username, email="nuevo@ucm.es"):
        return self.client.post("/api/v1/register/", {
            "username": username,
            "email": email,
            "password": GOOD_PASSWORD,
            "password_confirm": GOOD_PASSWORD,
            "name": "Nombre",
            "surname1": "Apellido",
            "user_type": "std",
        }, format='json')

    def test_a_name_with_an_at_sign_is_rejected(self):
        """
        El caso que motiva la regla: username y email son intercambiables al
        iniciar sesion, asi que una cuenta llamada otro@ucm.es se pondria por
        delante del correo de otra persona en find_by_username_or_email
        """
        response = self.register("ana@ucm.es")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.INVALID_USERNAME)
        self.assertFalse(Users.objects.filter(email="nuevo@ucm.es").exists())

    def test_a_name_with_spaces_is_rejected(self):
        response = self.register("con espacio")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.INVALID_USERNAME)

    def test_a_name_that_is_too_short_is_rejected(self):
        response = self.register("ab")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.INVALID_USERNAME)

    def test_the_message_explains_the_format(self):
        response = self.register("ana@ucm.es")

        self.assertEqual(response.data['message'], USERNAME_ERROR_MESSAGE)

    def test_a_well_formed_name_still_registers(self):
        response = self.register("ana.garcia")

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_the_format_is_checked_before_the_email_domain(self):
        with override_settings(ALLOWED_DOMAINS=['ucm.es']):
            response = self.register("ana@ucm.es", email="nuevo@gmail.com")

        self.assertEqual(response.data['error_code'], ErrorCodes.INVALID_USERNAME)

    def test_a_rejected_name_does_not_discard_a_pending_registration(self):
        pendiente = create_user("pendiente")
        pendiente.is_verify = False
        pendiente.save()

        self.register("ab")

        pendiente.refresh_from_db()
        self.assertFalse(pendiente.is_deleted)


@ANY_DOMAIN
class GoogleRegisterUsernameFormatTest(APITestCase):
    """
    El alta con Google, el correo lo acredita Google, pero el nombre
    de usuario lo sigue escribiendo la persona en el formulario
    """

    def google_register(self, **payload):
        return self.client.post("/api/v1/auth/google/register/", payload, format='json')

    @patch('users.services.auth_service.id_token.verify_oauth2_token')
    def test_a_badly_formed_name_returns_400_and_creates_nothing(self, verify):
        verify.return_value = {
            'email': "nuevo@gmail.com", 'email_verified': True, 'given_name': "Ana",
        }

        response = self.google_register(
            id_token="t", username="ana@ucm.es", user_type='std'
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error'], USERNAME_ERROR_MESSAGE)
        self.assertFalse(Users.objects.filter(email="nuevo@gmail.com").exists())

    @patch('users.services.auth_service.id_token.verify_oauth2_token')
    def test_a_well_formed_name_still_registers(self, verify):
        verify.return_value = {
            'email': "nuevo@gmail.com", 'email_verified': True, 'given_name': "Ana",
        }

        response = self.google_register(
            id_token="t", username="ana.garcia", user_type='std'
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)


class ProfileUsernameFormatTest(APITestCase):
    """
    El cambio de nombre desde el perfil, es la que de verdad cierra la
    regla, sin ella bastaria con registrarse con un nombre valido y renombrarse
    despues a uno con arroba
    """

    def setUp(self):
        self.user = create_user("dueño_perfil")
        self.client.force_authenticate(user=self.user)

    def rename(self, username):
        return self.client.patch(
            f"/api/v1/users/{self.user.id}/", {'username': username}, format='json'
        )

    def test_the_name_cannot_be_changed_to_one_with_an_at_sign(self):
        response = self.rename("otro@ucm.es")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.INVALID_USERNAME)
        self.user.refresh_from_db()
        self.assertEqual(self.user.username, "dueño_perfil")

    def test_the_name_cannot_be_changed_to_one_with_spaces(self):
        response = self.rename("con espacio")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.INVALID_USERNAME)

    def test_the_format_is_checked_before_the_uniqueness(self):
        create_user("ab")

        response = self.rename("ab")

        self.assertEqual(response.data['error_code'], ErrorCodes.INVALID_USERNAME)

    def test_a_well_formed_name_is_still_accepted(self):
        response = self.rename("nombre.nuevo")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertEqual(self.user.username, "nombre.nuevo")
