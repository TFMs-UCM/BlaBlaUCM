"""
Pruebas de REGRESION del ajuste del segundo factor.
    PATCH /api/v1/users/{id}/                        {"has_2FA": false}   <- ya NO
    POST  /api/v1/users/{id}/two_factor/challenge/
    POST  /api/v1/users/{id}/two_factor/             {"enabled": ..., credencial}
"""
import hashlib
from datetime import timedelta

from django.core import mail
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from api.errors import ErrorCodes
from travels.tests.factories import create_user
from users.services.auth_service import PURPOSE_CHANGE_2FA, PURPOSE_LOGIN_2FA
from users.tests.test_auth_characterization import (
    LOCMEM_EMAIL,
    create_user_with_password,
    error_code,
)

def give_code(user, code, purpose):
    """Deja un codigo pendiente en la cuenta, como si acabara de salir por correo."""
    user.token = hashlib.sha256(code.encode()).hexdigest()
    user.token_expiration = timezone.now() + timedelta(minutes=5)
    user.token_purpose = purpose
    user.save()

class SecondFactorIsNotWritableTest(APITestCase):
    """El PATCH del perfil ya no toca el ajuste."""

    def setUp(self):
        self.user = create_user_with_password("con_2fa", "contrasena", has_2fa=True)
        self.client.force_authenticate(user=self.user)

    def patch_me(self, **payload):
        return self.client.patch(f"/api/v1/users/{self.user.id}/", payload, format='json')

    def test_the_model_enables_the_second_factor_by_default(self):
        """`has_2FA = models.BooleanField(default=True)`."""
        self.assertTrue(create_user("recien_creado").has_2FA)

    def test_a_plain_patch_no_longer_disables_the_second_factor(self):
        """
        LA REGRESION. El campo es de solo lectura, y DRF descarta en silencio lo
        que llegue para uno de esos: la peticion sigue respondiendo 200 —no es un
        error del cliente pedir cambiar el nombre y de paso mandar `has_2FA`—,
        pero el ajuste se queda como estaba.
        """
        response = self.patch_me(has_2FA=False)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertTrue(self.user.has_2FA)

    def test_the_patch_still_changes_the_fields_that_are_writable(self):
        """El campo se cierra sin llevarse por delante el resto del perfil."""
        response = self.patch_me(name="Nombre nuevo", has_2FA=False)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertEqual(self.user.name, "Nombre nuevo")
        self.assertTrue(self.user.has_2FA)

    def test_the_flag_is_reported_in_the_profile(self):
        """La app lo lee para pintar el ajuste, asi que no puede desaparecer."""
        response = self.client.get(f"/api/v1/users/{self.user.id}/")

        self.assertIn('has_2FA', response.data)
        self.assertTrue(response.data['has_2FA'])


@LOCMEM_EMAIL
class SecondFactorChangeWithPasswordTest(APITestCase):
    """Cuenta con contraseña: la credencial es la contraseña."""

    def setUp(self):
        self.user = create_user_with_password("con_2fa", "contrasena", has_2fa=True)
        self.client.force_authenticate(user=self.user)
        mail.outbox = []

    def challenge(self):
        return self.client.post(f"/api/v1/users/{self.user.id}/two_factor/challenge/", {}, format='json')

    def set_2fa(self, **payload):
        return self.client.post(f"/api/v1/users/{self.user.id}/two_factor/", payload, format='json')

    def test_the_challenge_asks_for_the_password_and_sends_nothing(self):
        response = self.challenge()

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['method'], 'password')
        self.assertEqual(len(mail.outbox), 0)

    def test_the_right_password_disables_it(self):
        response = self.set_2fa(enabled=False, password="contrasena")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(response.data['has_2FA'])
        self.user.refresh_from_db()
        self.assertFalse(self.user.has_2FA)

    def test_a_wrong_password_leaves_it_as_it_was(self):
        response = self.set_2fa(enabled=False, password="la-que-no-es")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(error_code(response), ErrorCodes.INVALID_CREDENTIALS)
        self.user.refresh_from_db()
        self.assertTrue(self.user.has_2FA)

    def test_without_any_credential_it_is_not_touched(self):
        """Es el PATCH de antes con otra ruta: sin credencial no se hace nada."""
        response = self.set_2fa(enabled=False)

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(error_code(response), ErrorCodes.INVALID_CREDENTIALS)
        self.user.refresh_from_db()
        self.assertTrue(self.user.has_2FA)

    def test_a_code_does_not_replace_the_password(self):
        """
        La cuenta tiene contraseña, asi que el camino del codigo no esta abierto
        para ella: no se puede elegir el metodo mas debil desde el cliente.
        """
        give_code(self.user, "AB12cd", PURPOSE_CHANGE_2FA)

        response = self.set_2fa(enabled=False, code="AB12cd")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(error_code(response), ErrorCodes.INVALID_CREDENTIALS)
        self.user.refresh_from_db()
        self.assertTrue(self.user.has_2FA)

    def test_enabling_it_again_also_asks_for_the_password(self):
        """
        Activarlo tambien se acredita: con una sesion robada no se puede dejar al
        dueño fuera de su propia cuenta.
        """
        self.set_2fa(enabled=False, password="contrasena")

        without_credential = self.set_2fa(enabled=True)
        with_credential = self.set_2fa(enabled=True, password="contrasena")

        self.assertEqual(without_credential.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(with_credential.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertTrue(self.user.has_2FA)

    def test_enabled_is_required_and_has_to_be_a_boolean(self):
        without_field = self.set_2fa(password="contrasena")
        not_a_boolean = self.set_2fa(enabled="false", password="contrasena")

        for response in (without_field, not_a_boolean):
            self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
            self.assertEqual(error_code(response), ErrorCodes.MISSING_REQUIRED_FIELD)

        self.user.refresh_from_db()
        self.assertTrue(self.user.has_2FA)


@LOCMEM_EMAIL
class SecondFactorChangeWithEmailCodeTest(APITestCase):
    """
    Cuenta sin contraseña (la que se da de alta con Google): la credencial es un
    codigo que llega a su buzon, que es lo unico que identifica a esa cuenta.
    """

    def setUp(self):
        # `create_user` no llama a set_password, asi que la cuenta nace con el
        # campo a NULL, que es como quedan las que se dan de alta con Google
        self.user = create_user("solo_google")
        self.user.has_2FA = True
        self.user.save()
        self.client.force_authenticate(user=self.user)
        mail.outbox = []

    def challenge(self):
        return self.client.post(f"/api/v1/users/{self.user.id}/two_factor/challenge/", {}, format='json')

    def set_2fa(self, **payload):
        return self.client.post(f"/api/v1/users/{self.user.id}/two_factor/", payload, format='json')

    def test_the_challenge_sends_a_code_to_the_address_of_the_account(self):
        response = self.challenge()

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['method'], 'email')
        self.assertEqual(len(mail.outbox), 1)
        self.assertEqual(mail.outbox[0].to, [self.user.email])

    def test_the_code_is_issued_for_this_and_only_for_this(self):
        self.challenge()

        self.user.refresh_from_db()
        self.assertEqual(self.user.token_purpose, PURPOSE_CHANGE_2FA)

    def test_the_right_code_disables_it_and_is_spent(self):
        give_code(self.user, "AB12cd", PURPOSE_CHANGE_2FA)

        response = self.set_2fa(enabled=False, code="AB12cd")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertFalse(self.user.has_2FA)
        self.assertIsNone(self.user.token)

        # El codigo es de un solo uso: no sirve para volver a activarlo
        retry = self.set_2fa(enabled=True, code="AB12cd")
        self.assertEqual(retry.status_code, status.HTTP_400_BAD_REQUEST)
        self.user.refresh_from_db()
        self.assertFalse(self.user.has_2FA)

    def test_a_wrong_code_leaves_it_as_it_was(self):
        give_code(self.user, "AB12cd", PURPOSE_CHANGE_2FA)

        response = self.set_2fa(enabled=False, code="XXXXXX")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(error_code(response), ErrorCodes.INCORRECT_TOKEN)
        self.user.refresh_from_db()
        self.assertTrue(self.user.has_2FA)

    def test_without_any_pending_code_there_is_nothing_to_spend(self):
        response = self.set_2fa(enabled=False, code="AB12cd")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(error_code(response), ErrorCodes.INCORRECT_TOKEN)
        self.user.refresh_from_db()
        self.assertTrue(self.user.has_2FA)

    def test_an_expired_code_does_not_work(self):
        give_code(self.user, "AB12cd", PURPOSE_CHANGE_2FA)
        self.user.token_expiration = timezone.now() - timedelta(minutes=1)
        self.user.save()

        response = self.set_2fa(enabled=False, code="AB12cd")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(error_code(response), ErrorCodes.TOKEN_EXPIRED)
        self.user.refresh_from_db()
        self.assertTrue(self.user.has_2FA)

    def test_the_code_of_the_login_does_not_disable_the_second_factor(self):
        """
        Un codigo, un proposito. Si el del login valiera aqui, el propio
        segundo factor daria la llave para apagarse.
        """
        give_code(self.user, "AB12cd", PURPOSE_LOGIN_2FA)

        response = self.set_2fa(enabled=False, code="AB12cd")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(error_code(response), ErrorCodes.INCORRECT_TOKEN)
        self.user.refresh_from_db()
        self.assertTrue(self.user.has_2FA)

    def test_this_code_does_not_change_the_password_either(self):
        """La contraparte: el codigo de este ajuste no vale para otra cosa."""
        give_code(self.user, "AB12cd", PURPOSE_CHANGE_2FA)

        response = self.client.post(
            "/api/v1/users/verify_code/",
            {'username': "solo_google", 'token': "AB12cd", 'password': "nueva-contrasena"},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(error_code(response), ErrorCodes.INCORRECT_TOKEN)

    def test_enabling_it_again_also_needs_a_code(self):
        give_code(self.user, "AB12cd", PURPOSE_CHANGE_2FA)
        self.set_2fa(enabled=False, code="AB12cd")

        without_code = self.set_2fa(enabled=True)

        self.assertEqual(without_code.status_code, status.HTTP_400_BAD_REQUEST)
        self.user.refresh_from_db()
        self.assertFalse(self.user.has_2FA)

        give_code(self.user, "EF34gh", PURPOSE_CHANGE_2FA)
        with_code = self.set_2fa(enabled=True, code="EF34gh")

        self.assertEqual(with_code.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertTrue(self.user.has_2FA)


@LOCMEM_EMAIL
class SecondFactorChangeOfSomeoneElseTest(APITestCase):
    """
    REGRESION DE SEGURIDAD.

    El queryset de `UsersViewSet` esta limitado a la cuenta propia, asi que la
    URL de otro usuario no resuelve. Vale para las acciones nuevas igual que
    para el PATCH, porque las dos salen de `get_object()`.
    """

    def setUp(self):
        self.user = create_user_with_password("atacante", "contrasena")
        self.victim = create_user_with_password("victima", "la-suya", has_2fa=True)
        self.client.force_authenticate(user=self.user)
        mail.outbox = []

    def test_the_challenge_of_another_account_does_not_resolve(self):
        response = self.client.post(f"/api/v1/users/{self.victim.id}/two_factor/challenge/", {}, format='json')

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(len(mail.outbox), 0)

    def test_the_second_factor_of_another_user_cannot_be_touched(self):
        response = self.client.post(
            f"/api/v1/users/{self.victim.id}/two_factor/",
            {'enabled': False, 'password': "la-suya"},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.victim.refresh_from_db()
        self.assertTrue(self.victim.has_2FA)

    def test_a_plain_patch_on_another_user_does_not_either(self):
        response = self.client.patch(
            f"/api/v1/users/{self.victim.id}/", {'has_2FA': False}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.victim.refresh_from_db()
        self.assertTrue(self.victim.has_2FA)


class SecondFactorChangeWithoutASessionTest(APITestCase):
    """Los dos endpoints son de la cuenta propia: sin sesion no hay cuenta."""

    def setUp(self):
        self.user = create_user_with_password("con_2fa", "contrasena", has_2fa=True)

    def test_both_endpoints_require_authentication(self):
        challenge = self.client.post(f"/api/v1/users/{self.user.id}/two_factor/challenge/", {}, format='json')
        change = self.client.post(
            f"/api/v1/users/{self.user.id}/two_factor/",
            {'enabled': False, 'password': "contrasena"},
            format='json',
        )

        self.assertEqual(challenge.status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertEqual(change.status_code, status.HTTP_401_UNAUTHORIZED)
        self.user.refresh_from_db()
        self.assertTrue(self.user.has_2FA)
