"""
Pruebas de REGRESION DE SEGURIDAD del flujo de verificacion por email.
    POST /api/v1/users/verification_email/   (sin autenticacion)
    POST /api/v1/users/verify_code/          (sin autenticacion)
"""
import re

from django.core import mail
from django.test import override_settings
from rest_framework import status
from rest_framework.test import APITestCase

from api.errors import ErrorCodes
from travels.tests.factories import create_user
from users.models import Users

# El backend en memoria deja los correos en django.core.mail.outbox
LOCMEM_EMAIL = override_settings(
    EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend'
)


@LOCMEM_EMAIL
class AccountTakeoverTest(APITestCase):

    def setUp(self):
        self.victim = create_user("victim")
        self.victim.email = "victim@ucm.es"
        self.victim.set_password("contrasena-original")
        self.victim.save()
        mail.outbox = []

    def request_verification_email(self, username, email=None):
        payload = {'username': username}
        if email:
            payload['email'] = email
        return self.client.post(
            "/api/v1/users/verification_email/", payload, format='json'
        )

    def token_from_last_email(self):
        """Extrae el codigo de 6 caracteres del cuerpo del correo."""
        body = mail.outbox[-1].body
        match = re.search(r'margin:16px 0;">\s*([A-Za-z0-9]{6})\s*</div>', body)
        self.assertIsNotNone(match, f"No se encontro el token en el correo:\n{body}")
        return match.group(1)

    def test_the_token_is_only_sent_to_the_address_of_the_account(self):
        """
        Primer eslabon de la cadena, ya cortado: pedir el codigo de una cuenta
        ajena mandandolo a otra direccion se rechaza sin enviar nada.
        """
        response = self.request_verification_email("victim", email="atacante@evil.com")

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data['error_code'], ErrorCodes.INSUFICIENT_CREDENTIALS)

        # Ni se manda el correo ni se genera un token aprovechable
        self.assertEqual(len(mail.outbox), 0)
        self.victim.refresh_from_db()
        self.assertIsNone(self.victim.token)

    def test_the_account_takeover_chain_is_broken(self):
        """
        La cadena completa que antes bastaba para quedarse con la cuenta:

        1. pedir el codigo de la victima y mandarlo al correo del atacante;
        2. usar ese codigo para cambiar la contraseña.

        Ahora el paso 1 no llega a ninguna parte, asi que no hay codigo que
        robar y la contraseña sigue siendo la de la victima.
        """
        self.request_verification_email("victim", email="atacante@evil.com")

        self.assertEqual(len(mail.outbox), 0)

        response = self.client.post(
            "/api/v1/users/verify_code/",
            {
                'username': "victim",
                'token': "ABC123",
                'password': "contrasena-del-atacante",
                'validate': True,
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.INCORRECT_TOKEN)

        self.victim.refresh_from_db()
        self.assertTrue(self.victim.check_password("contrasena-original"))

    def test_changing_the_email_requires_being_the_owner(self):
        """
        Contrapartida en `verify_code`: aunque alguien consiguiera un codigo,
        no puede mover el correo de la cuenta sin estar autenticado como dueño.
        """
        self.request_verification_email("victim")
        token = self.token_from_last_email()

        response = self.client.post(
            "/api/v1/users/verify_code/",
            {'username': "victim", 'token': token, 'email': "atacante@evil.com"},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.victim.refresh_from_db()
        self.assertEqual(self.victim.email, "victim@ucm.es")

    def test_the_code_is_single_use(self):
        """
        Antes el codigo seguia sirviendo hasta caducar, asi que un unico robo
        daba pie a varios cambios. Ahora se consume al usarlo.
        """
        self.request_verification_email("victim")
        token = self.token_from_last_email()

        first_use = self.client.post(
            "/api/v1/users/verify_code/",
            {'username': "victim", 'token': token, 'password': "primera"},
            format='json',
        )
        second_use = self.client.post(
            "/api/v1/users/verify_code/",
            {'username': "victim", 'token': token, 'password': "segunda"},
            format='json',
        )

        self.assertEqual(first_use.status_code, status.HTTP_200_OK)
        self.assertEqual(second_use.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(second_use.data['error_code'], ErrorCodes.INCORRECT_TOKEN)

        self.victim.refresh_from_db()
        self.assertTrue(self.victim.check_password("primera"))

    def test_the_password_reset_still_works(self):
        """
        Contraparte imprescindible: el flujo legitimo de "he olvidado mi
        contraseña" es el mismo que se explotaba, y tiene que seguir vivo.
        """
        self.request_verification_email("victim")

        self.assertEqual(mail.outbox[0].to, ["victim@ucm.es"])
        token = self.token_from_last_email()

        response = self.client.post(
            "/api/v1/users/verify_code/",
            {'username': "victim", 'token': token, 'password': "contrasena-nueva", 'validate': True},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.victim.refresh_from_db()
        self.assertTrue(self.victim.check_password("contrasena-nueva"))
        self.assertTrue(self.victim.is_verify)

    def test_verifying_and_resetting_share_purpose_on_purpose(self):
        self.request_verification_email("victim")
        token = self.token_from_last_email()

        response = self.client.post(
            "/api/v1/users/verify_code/",
            {'username': "victim", 'token': token, 'password': "otra-clave", 'validate': True},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.victim.refresh_from_db()
        self.assertTrue(self.victim.is_verify)
        self.assertTrue(self.victim.check_password("otra-clave"))


@LOCMEM_EMAIL
class EmailChangeByTheOwnerTest(APITestCase):
    """
    El caso legitimo que justifica que el parametro `email` exista: cambiar el
    correo de la cuenta desde el perfil, mandando el codigo a la direccion nueva
    para comprobar que es de quien dice.
    """

    def setUp(self):
        self.user = create_user("owner")
        self.user.email = "owner@ucm.es"
        self.user.save()
        self.client.force_authenticate(user=self.user)
        mail.outbox = []

    def token_from_last_email(self):
        body = mail.outbox[-1].body
        match = re.search(r'margin:16px 0;">\s*([A-Za-z0-9]{6})\s*</div>', body)
        self.assertIsNotNone(match, f"No se encontro el token en el correo:\n{body}")
        return match.group(1)

    def test_the_owner_can_send_the_code_to_the_new_address(self):
        response = self.client.post(
            "/api/v1/users/verification_email/",
            {'username': "owner", 'email': "nuevo@ucm.es"},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(mail.outbox[0].to, ["nuevo@ucm.es"])

    def test_the_owner_can_complete_the_email_change(self):
        self.client.post(
            "/api/v1/users/verification_email/",
            {'username': "owner", 'email': "nuevo@ucm.es"},
            format='json',
        )
        token = self.token_from_last_email()

        response = self.client.post(
            "/api/v1/users/verify_code/",
            {'username': "owner", 'token': token, 'email': "nuevo@ucm.es"},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertEqual(self.user.email, "nuevo@ucm.es")

    def test_the_owner_cannot_redirect_the_code_of_another_account(self):
        """Estar autenticado no basta: tiene que ser su propia cuenta."""
        create_user("otra_cuenta")

        response = self.client.post(
            "/api/v1/users/verification_email/",
            {'username': "otra_cuenta", 'email': "nuevo@ucm.es"},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(len(mail.outbox), 0)


@LOCMEM_EMAIL
class VerifyCodeEdgeCasesTest(APITestCase):

    def test_verify_code_without_a_pending_token_returns_400(self):
        """
        Si el usuario nunca pidio un codigo, `token_expiration` es None. Antes se
        comparaba `None < timezone.now()`, saltaba un TypeError que ningun except
        recogia y salia un 500. Ahora se comprueba antes.
        """
        create_user("sin_token")

        response = self.client.post(
            "/api/v1/users/verify_code/",
            {'username': "sin_token", 'token': "ABC123"},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.INCORRECT_TOKEN)


class UserEnumerationTest(APITestCase):

    def test_verify_user_allows_enumeration_without_authentication(self):
        user = create_user("existente")

        response = self.client.get(
            f"/api/v1/users/verify_user/?email={user.email}&username=libre"
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['email_taken'])
        self.assertFalse(response.data['username_taken'])
        self.assertEqual(Users.objects.filter(email=user.email).count(), 1)
