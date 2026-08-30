"""
Pruebas de la POLITICA DE CONTRASEÑAS
"""
import re

from django.core import mail
from django.test import TestCase, override_settings
from rest_framework import status
from rest_framework.test import APITestCase

from travels.tests.factories import create_user
from users.services.auth_service import AuthService
from users.services.user_service import UserService

# Debil por dos motivos a la vez: esta en la lista de contraseñas comunes de
# Django y es solo numerica. Se usa la misma en las tres puertas a proposito,
# para que la comparacion entre ellas sea directa.
WEAK = "123456"

# Cumple los cuatro validadores y tiene 6 caracteres, que es el minimo
# sirve de contrapartida para comprobar que el arreglo no se aprueba rechazandolo todo.
GOOD = "Kx7pq2"

LOCMEM_EMAIL = override_settings(
    EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend'
)


class RegistrationPasswordPolicyTest(APITestCase):
    """Puerta 1: el alta."""

    def payload(self, password):
        return {
            "username": "nuevo",
            "email": "nuevo@ucm.es",
            "password": password,
            "password_confirm": password,
            "name": "Nombre",
            "surname1": "Apellido",
            "user_type": "std",
        }

    def test_a_weak_password_is_rejected_on_registration(self):
        response = self.client.post("/api/v1/register/", self.payload(WEAK), format='json')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_a_good_password_still_registers(self):
        response = self.client.post("/api/v1/register/", self.payload(GOOD), format='json')

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_the_minimum_length_is_still_six(self):
        """
        Esta prueba fija esa decision: si alguien retirase el `OPTIONS: 
        {'min_length': 6}` de settings, el defecto de la libreria pasaria a 
        8 y `GOOD` dejaria de valer sin que nadie lo hubiera decidido.
        """
        too_short = self.client.post("/api/v1/register/", self.payload("Kx7p2"), format='json')
        self.assertEqual(too_short.status_code, status.HTTP_400_BAD_REQUEST)

        exact_limit = self.client.post("/api/v1/register/", self.payload(GOOD), format='json')
        self.assertEqual(exact_limit.status_code, status.HTTP_201_CREATED)


class ChangePasswordPolicyTest(TestCase):
    """
    Puerta 2: el cambio desde el perfil.
    No exigia NADA: `request.data.get('new_password')` iba directo a
    `set_password`.
    """

    def setUp(self):
        self.user = create_user("dueño")
        self.user.set_password("actual-buena")
        self.user.save()

    def test_a_weak_password_is_rejected_on_change(self):
        with self.assertRaises(Exception) as ctx:
            UserService.change_password(self.user, "actual-buena", WEAK)

        # La ValidationError de Django la traduce el manejador unico a un 400 con
        # el campo aqui, a nivel de servicio, basta con que no pase de largo
        self.assertIn("ValidationError", type(ctx.exception).__name__)

        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("actual-buena"))

    def test_a_good_password_still_changes(self):
        UserService.change_password(self.user, "actual-buena", GOOD)

        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password(GOOD))

    def test_the_current_password_is_still_checked_first(self):
        """
        Contrapartida: la comprobacion nueva no puede haberse comido la que ya
        habia. Con la contraseña actual mal, el error tiene que seguir siendo
        `IncorrectPasswordError`, no el de politica.
        """
        from users.services.exceptions import IncorrectPasswordError

        with self.assertRaises(IncorrectPasswordError):
            UserService.change_password(self.user, "equivocada", GOOD)


@LOCMEM_EMAIL
class ResetPasswordPolicyTest(APITestCase):
    """
    Puerta 3: el canje del codigo, que es la que mas importa.

    Es la de "he olvidado la contraseña", la que se usa justo despues de un
    incidente, y era de las que no comprobaban nada.
    """

    def setUp(self):
        self.user = create_user("olvidadizo")
        self.user.email = "olvidadizo@ucm.es"
        self.user.set_password("la-de-siempre")
        self.user.has_2FA = False
        self.user.save()
        mail.outbox = []

    def request_code(self):
        response = self.client.post(
            "/api/v1/users/verification_email/",
            {"username": self.user.username},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)

        # El mismo patron que `test_token_purpose.py`: el codigo va dentro de un
        # <div> concreto de la plantilla. Un `\b[A-Za-z0-9]{6}\b` a secas se lleva
        # la primera palabra de seis letras del HTML, no el codigo, y entonces
        # TODOS los canjes dan 400 y las pruebas de rechazo pasan por el motivo
        # equivocado
        body = mail.outbox[-1].body
        match = re.search(r'margin:16px 0;">\s*([A-Za-z0-9]{6})\s*</div>', body)
        self.assertIsNotNone(match, f"No se encontro el token en el correo:\n{body}")
        return match.group(1)

    def redeem(self, code, password):
        return self.client.post(
            "/api/v1/users/verify_code/",
            {"username": self.user.username, "token": code, "password": password},
            format='json',
        )

    def test_a_weak_password_is_rejected_on_reset(self):
        response = self.redeem(self.request_code(), WEAK)

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("la-de-siempre"))

    def test_a_good_password_still_resets(self):
        response = self.redeem(self.request_code(), GOOD)

        self.assertEqual(response.status_code, status.HTTP_200_OK)

        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password(GOOD))

    def test_a_rejected_reset_does_not_consume_the_code(self):
        """
        El codigo es de un solo uso, asi que si una contraseña debil lo gastara,
        al usuario le tocaria pedir otro por haberse equivocado escribiendo. La
        validacion tiene que ir ANTES de consumirlo.
        """
        code = self.request_code()

        self.assertEqual(self.redeem(code, WEAK).status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(self.redeem(code, GOOD).status_code, status.HTTP_200_OK)


class ValidatorsAreWiredTest(TestCase):
    """
    La prueba que explica el fallo, y no la que lo comprueba.
    """

    def test_the_service_rejects_a_common_password(self):
        from django.core.exceptions import ValidationError

        with self.assertRaises(ValidationError):
            AuthService.assert_password_is_acceptable("password")

    def test_the_service_rejects_a_numeric_only_password(self):
        from django.core.exceptions import ValidationError

        with self.assertRaises(ValidationError):
            AuthService.assert_password_is_acceptable("948573926")

    def test_the_service_rejects_a_password_that_looks_like_the_user(self):
        from django.core.exceptions import ValidationError

        user = create_user("melocoton")

        with self.assertRaises(ValidationError):
            AuthService.assert_password_is_acceptable("melocoton", user=user)

    def test_the_service_accepts_a_reasonable_one(self):
        AuthService.assert_password_is_acceptable(GOOD)
