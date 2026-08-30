"""
Pruebas de UN CODIGO, UN PROPOSITO
"""
import re

from django.core import mail
from django.test import override_settings
from rest_framework import status
from rest_framework.test import APITestCase

from api.errors import ErrorCodes
from travels.tests.factories import create_user
from users.services.auth_service import (
    PURPOSE_CHANGE_EMAIL,
    PURPOSE_LOGIN_2FA,
    PURPOSE_RESET_PASSWORD,
    PURPOSE_VERIFY_EMAIL,
    AuthService,
)

LOCMEM_EMAIL = override_settings(
    EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend'
)

@LOCMEM_EMAIL
class BaseTokenPurposeTest(APITestCase):

    def setUp(self):
        self.user = create_user("piloto")
        self.user.email = "piloto@ucm.es"
        self.user.set_password("contrasena-original")
        self.user.has_2FA = False
        self.user.save()
        mail.outbox = []

    def token_from_last_email(self):
        body = mail.outbox[-1].body
        match = re.search(r'margin:16px 0;">\s*([A-Za-z0-9]{6})\s*</div>', body)
        self.assertIsNotNone(match, f"No se encontro el token en el correo:\n{body}")
        return match.group(1)

    def request_code(self, **extra):
        payload = {'username': "piloto"}
        payload.update(extra)
        return self.client.post("/api/v1/users/verification_email/", payload, format='json')

    def verify(self, **extra):
        payload = {'username': "piloto", 'token': self.token_from_last_email()}
        payload.update(extra)
        return self.client.post("/api/v1/users/verify_code/", payload, format='json')


class PurposeInferenceTest(BaseTokenPurposeTest):
    """
    El cliente no manda el proposito y no se le puede pedir sin tocar la app: la
    peticion de "verifica tu cuenta" y la de "he olvidado la contraseña" son
    identicas. Se deduce del estado de la cuenta y de quien llama.
    """

    def test_an_unverified_account_gets_a_verification_code(self):
        self.user.is_verify = False
        self.user.save()

        self.request_code()

        self.user.refresh_from_db()
        self.assertEqual(self.user.token_purpose, PURPOSE_VERIFY_EMAIL)

    def test_a_verified_account_gets_a_password_reset_code(self):
        self.request_code()

        self.user.refresh_from_db()
        self.assertEqual(self.user.token_purpose, PURPOSE_RESET_PASSWORD)

    def test_asking_for_another_address_gets_an_email_change_code(self):
        self.client.force_authenticate(user=self.user)

        self.request_code(email="nuevo@ucm.es")

        self.user.refresh_from_db()
        self.assertEqual(self.user.token_purpose, PURPOSE_CHANGE_EMAIL)

    def test_the_login_second_factor_gets_its_own_purpose(self):
        self.user.has_2FA = True
        self.user.save()

        self.client.post(
            "/api/v1/login/",
            {'username': "piloto", 'password': "contrasena-original"},
            format='json',
        )

        self.user.refresh_from_db()
        self.assertEqual(self.user.token_purpose, PURPOSE_LOGIN_2FA)


class PurposeIsolationTest(BaseTokenPurposeTest):
    """Los cruces que ahora se rechazan"""

    def test_a_login_code_cannot_be_used_to_change_the_password(self):
        """
        El cruce que de verdad importa: al usuario se le pide ese codigo para
        "entrar en tu cuenta", asi que es el que esta acostumbrado a teclear y el
        mas facil de sacarle con engaños. Antes servia tambien para dejarle
        fuera cambiandole la contraseña.
        """
        self.user.has_2FA = True
        self.user.save()
        self.client.post(
            "/api/v1/login/",
            {'username': "piloto", 'password': "contrasena-original"},
            format='json',
        )

        response = self.verify(password="la-del-atacante")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.INCORRECT_TOKEN)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("contrasena-original"))

    def test_a_password_reset_code_cannot_be_used_to_log_in(self):
        """El cruce inverso, que es el que permitiria saltarse el segundo factor."""
        self.user.has_2FA = True
        self.user.save()
        self.request_code()          # codigo de restablecer contraseña
        token = self.token_from_last_email()

        response = self.client.post(
            "/api/v1/login/",
            {'username': "piloto", 'password': "contrasena-original", 'code': token},
            format='json',
        )

        self.assertNotEqual(response.status_code, status.HTTP_200_OK)
        self.assertNotIn('access', response.data)

    def test_a_password_reset_code_cannot_be_used_to_change_the_email(self):
        self.client.force_authenticate(user=self.user)
        self.request_code()          # sin `email`: sale como restablecer contraseña

        response = self.verify(email="otro@ucm.es")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.user.refresh_from_db()
        self.assertEqual(self.user.email, "piloto@ucm.es")

    def test_an_email_change_code_cannot_be_used_to_change_the_password(self):
        self.client.force_authenticate(user=self.user)
        self.request_code(email="nuevo@ucm.es")

        response = self.verify(password="la-del-atacante")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("contrasena-original"))


class TheFourFlowsStillWorkTest(BaseTokenPurposeTest):
    """
    Contrapartida obligatoria de la clase anterior: sin esto, el aislamiento se
    podria "aprobar" rechazandolo todo. Son los cuatro flujos que usa la app.
    """

    def test_registering_and_verifying_the_account_still_works(self):
        self.user.is_verify = False
        self.user.save()
        self.request_code()

        response = self.verify(validate=True)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertTrue(self.user.is_verify)

    def test_the_forgotten_password_flow_still_works(self):
        self.request_code()

        response = self.verify(password="contrasena-nueva")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("contrasena-nueva"))

    def test_changing_the_email_from_the_profile_still_works(self):
        self.client.force_authenticate(user=self.user)
        self.request_code(email="nuevo@ucm.es")

        response = self.verify(email="nuevo@ucm.es")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertEqual(self.user.email, "nuevo@ucm.es")

    def test_the_login_with_second_factor_still_works(self):
        self.user.has_2FA = True
        self.user.save()
        self.client.post(
            "/api/v1/login/",
            {'username': "piloto", 'password': "contrasena-original"},
            format='json',
        )
        token = self.token_from_last_email()

        response = self.client.post(
            "/api/v1/login/",
            {'username': "piloto", 'password': "contrasena-original", 'code': token},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('access', response.data)


class EmailUniquenessOnVerifyCodeTest(BaseTokenPurposeTest):
    """
    `consume_verification_code` asignaba el correo nuevo sin comprobar que
    estuviera libre, mientras que el registro y la edicion del perfil si lo
    comprueban. Era el cuarto sitio de la misma regla, y el unico que se
    la saltaba.
    """

    def test_the_new_address_cannot_belong_to_another_account(self):
        other_user = create_user("otro")
        other_user.email = "ocupado@ucm.es"
        other_user.save()
        self.client.force_authenticate(user=self.user)
        self.request_code(email="ocupado@ucm.es")

        response = self.verify(email="ocupado@ucm.es")

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)
        self.assertEqual(response.data['error_code'], ErrorCodes.EMAIL_ALREADY_EXISTS)
        self.user.refresh_from_db()
        self.assertEqual(self.user.email, "piloto@ucm.es")

    def test_the_address_of_a_deleted_account_can_be_reused(self):
        """
        Coherente con la restriccion unica del modelo, que es condicional a
        `is_deleted=False`. Sin esta prueba, la comprobacion podria ser mas
        estricta que la base de datos y bloquear correos que si estan libres.
        """
        deleted = create_user("borrado")
        deleted.email = "libre@ucm.es"
        deleted.is_deleted = True
        deleted.save()
        self.client.force_authenticate(user=self.user)
        self.request_code(email="libre@ucm.es")

        response = self.verify(email="libre@ucm.es")

        self.assertEqual(response.status_code, status.HTTP_200_OK)


class LegacyTokensTest(BaseTokenPurposeTest):
    """
    Las cuentas que tuvieran un codigo pendiente en el momento de migrar lo
    tienen sin proposito (`null`). Rechazarlos habria dejado a esos usuarios a
    medias de un flujo sin explicacion; se dejan pasar y el problema se agota
    solo, porque caducan en minutos.
    """

    def test_a_token_without_purpose_is_still_accepted(self):
        self.request_code()
        self.user.refresh_from_db()
        self.user.token_purpose = None      # como lo dejaria la migracion
        self.user.save()

        response = self.verify(password="contrasena-nueva")

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_consuming_a_code_clears_its_purpose(self):
        """Si no se limpiara, el proposito del codigo anterior mandaria sobre el siguiente."""
        self.request_code()
        self.verify(password="contrasena-nueva")

        self.user.refresh_from_db()
        self.assertIsNone(self.user.token_purpose)
        self.assertIsNone(self.user.token)


class TokenStrengthTest(BaseTokenPurposeTest):

    def test_the_alphabet_is_not_only_digits(self):
        codes = {AuthService.generate_token()[0] for _ in range(200)}
        alphabet = set(''.join(codes))

        self.assertTrue(any(c.isalpha() for c in alphabet))
        self.assertTrue(any(c.isupper() for c in alphabet))
        self.assertTrue(any(c.islower() for c in alphabet))
        self.assertTrue(any(c.isdigit() for c in alphabet))

    def test_two_codes_in_a_row_are_not_the_same(self):
        """Comprobacion minima de que hay aleatoriedad de verdad detras."""
        codes = {AuthService.generate_token()[0] for _ in range(200)}

        self.assertGreater(len(codes), 190)
