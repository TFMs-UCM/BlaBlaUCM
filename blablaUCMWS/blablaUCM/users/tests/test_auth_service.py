"""
Pruebas UNITARIAS de `AuthService`
Atacan al servicio directamente, sin pasar por HTTP. Documentan el contrato de la
parte de credenciales: generacion y consumo del codigo de verificacion,
disponibilidad de correo y usuario, y alta con Google.
"""
import hashlib
from datetime import timedelta
from unittest.mock import patch

from django.core import mail
from django.test import TestCase, override_settings
from django.utils import timezone

from travels.tests.factories import create_user
from users.models import Users
from users.services.auth_service import AuthService
from users.services.exceptions import (
    EmailAlreadyRegisteredError,
    EmailDeliveryError,
    GoogleEmailMissingError,
    InvalidGoogleTokenError,
    InvalidTokenError,
    InvalidUserTypeError,
    TokenExpiredError,
    UnverifiedEmailError,
    UsernameAlreadyTakenError,
    UserNotFoundError,
)

# El backend en memoria deja los correos en django.core.mail.outbox
LOCMEM_EMAIL = override_settings(
    EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend'
)

class GenerateTokenTest(TestCase):

    def test_the_code_is_six_alphanumeric_characters(self):
        token, _ = AuthService.generate_token()

        self.assertEqual(len(token), 6)
        self.assertTrue(token.isalnum())

    def test_the_hash_matches_the_code(self):
        token, token_hash = AuthService.generate_token()

        self.assertEqual(token_hash, hashlib.sha256(token.encode()).hexdigest())
        self.assertTrue(AuthService.verify_token(token, token_hash))

    def test_a_different_code_does_not_verify(self):
        _, token_hash = AuthService.generate_token()

        self.assertFalse(AuthService.verify_token("XXXXXX", token_hash))

    def test_two_calls_do_not_give_the_same_code(self):
        codes = {AuthService.generate_token()[0] for _ in range(20)}

        # Con 62^6 combinaciones, 20 repeticiones no deberian colisionar
        self.assertEqual(len(codes), 20)


@LOCMEM_EMAIL
class SendVerificationCodeTest(TestCase):

    def setUp(self):
        self.user = create_user("destinatario")
        mail.outbox = []

    def test_it_sends_to_the_address_of_the_account(self):
        AuthService.send_verification_code(self.user)

        self.assertEqual(mail.outbox[0].to, [self.user.email])

    def test_it_sends_to_another_address_when_one_is_given(self):
        """
        Solo lo usa el cambio de correo desde el perfil, y el view ya ha
        comprobado antes que quien lo pide es el dueño
        """
        AuthService.send_verification_code(self.user, to_email="nuevo@ucm.es")

        self.assertEqual(mail.outbox[0].to, ["nuevo@ucm.es"])

    def test_only_the_hash_is_stored_never_the_code(self):
        AuthService.send_verification_code(self.user)

        self.user.refresh_from_db()
        self.assertEqual(len(self.user.token), 64)   # sha256 en hexadecimal
        self.assertNotIn(self.user.token, mail.outbox[0].body)

    def test_the_expiration_is_set_in_the_future(self):
        AuthService.send_verification_code(self.user)

        self.user.refresh_from_db()
        self.assertGreater(self.user.token_expiration, timezone.now())

    @patch('users.services.auth_service.Email')
    def test_a_delivery_failure_raises_and_stores_no_token(self, email_class):
        email_class.return_value.send_verification_email.side_effect = OSError("smtp caido")

        with self.assertRaises(EmailDeliveryError):
            AuthService.send_verification_code(self.user)

        self.user.refresh_from_db()
        self.assertIsNone(self.user.token)


class ConsumeVerificationCodeTest(TestCase):

    def setUp(self):
        self.user = create_user("verificando")

    def give_token(self, expires_in=timedelta(minutes=5)):
        token, token_hash = AuthService.generate_token()
        self.user.token = token_hash
        self.user.token_expiration = timezone.now() + expires_in
        self.user.save()
        return token

    def test_an_account_without_a_pending_code_raises(self):
        with self.assertRaises(InvalidTokenError):
            AuthService.consume_verification_code(self.user, "ABC123")

    def test_an_expired_code_raises(self):
        token = self.give_token(expires_in=timedelta(minutes=-1))

        with self.assertRaises(TokenExpiredError):
            AuthService.consume_verification_code(self.user, token)

    def test_a_wrong_code_raises(self):
        self.give_token()

        with self.assertRaises(InvalidTokenError):
            AuthService.consume_verification_code(self.user, "XXXXXX")

    def test_a_valid_code_applies_the_changes(self):
        token = self.give_token()
        # "nueva" tenia 5 caracteres y exige 6. Lo que fija esta prueba es que el codigo
        # aplica los tres cambios a la vez, no la longitud
        AuthService.consume_verification_code(
            self.user, token, email="otro@ucm.es", password="nueva-clave", validate=True
        )

        self.user.refresh_from_db()
        self.assertEqual(self.user.email, "otro@ucm.es")
        self.assertTrue(self.user.check_password("nueva-clave"))
        self.assertTrue(self.user.is_verify)

    def test_the_code_is_consumed_even_without_any_change(self):
        token = self.give_token()

        AuthService.consume_verification_code(self.user, token)

        self.user.refresh_from_db()
        self.assertIsNone(self.user.token)
        self.assertIsNone(self.user.token_expiration)

    def test_the_code_does_not_work_a_second_time(self):
        token = self.give_token()
        AuthService.consume_verification_code(self.user, token, password="primera")

        with self.assertRaises(InvalidTokenError):
            AuthService.consume_verification_code(self.user, token, password="segunda")

        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("primera"))

    def test_a_wrong_code_does_not_burn_the_good_one(self):
        token = self.give_token()

        with self.assertRaises(InvalidTokenError):
            AuthService.consume_verification_code(self.user, "XXXXXX")

        # El codigo bueno sigue sirviendo
        AuthService.consume_verification_code(self.user, token, validate=True)
        self.user.refresh_from_db()
        self.assertTrue(self.user.is_verify)


class AvailabilityTest(TestCase):

    def setUp(self):
        self.user = create_user("ocupado")

    def test_an_email_in_use_is_reported_as_taken(self):
        self.assertTrue(AuthService.email_is_taken(self.user.email))

    def test_a_free_email_is_not_taken(self):
        self.assertFalse(AuthService.email_is_taken("libre@ucm.es"))

    def test_a_username_in_use_is_reported_as_taken(self):
        self.assertTrue(AuthService.username_is_taken("ocupado"))

    def test_a_deleted_account_frees_its_email_and_username(self):
        self.user.is_deleted = True
        self.user.save()

        self.assertFalse(AuthService.email_is_taken(self.user.email))
        self.assertFalse(AuthService.username_is_taken("ocupado"))

    def test_a_user_does_not_collide_with_itself(self):
        """
        `excluding` es lo que permite guardar el perfil sin cambiar el nombre.
        Sin esto, mandar el propio nombre daba 409
        """
        self.assertFalse(AuthService.username_is_taken("ocupado", excluding=self.user))
        self.assertFalse(AuthService.email_is_taken(self.user.email, excluding=self.user))

    def test_excluding_does_not_hide_a_real_conflict(self):
        other_user = create_user("otro")

        self.assertTrue(AuthService.username_is_taken("ocupado", excluding=other_user))


class PrepareRegistrationTest(TestCase):
    """
    La regla de "un alta a medias no bloquea el nombre", que estaba metida dentro
    del `validate` del serializer de registro.
    """

    def test_a_free_username_and_email_pass(self):
        AuthService.prepare_registration("libre", "libre@ucm.es")

    def test_a_verified_username_is_rejected(self):
        create_user("tomado")

        with self.assertRaises(UsernameAlreadyTakenError):
            AuthService.prepare_registration("tomado", "otro@ucm.es")

    def test_a_taken_email_is_rejected(self):
        existing = create_user("existente")

        with self.assertRaises(EmailAlreadyRegisteredError):
            AuthService.prepare_registration("libre", existing.email)

    def test_an_unverified_account_is_discarded_with_a_soft_delete(self):
        """
        Antes se hacia un borrado duro desde un endpoint sin autenticacion. 
        El nombre queda libre igual porque la restriccion unica es condicional 
        a `is_deleted=False`.
        """
        half_done = create_user("a_medias")
        half_done.is_verify = False
        half_done.save()

        AuthService.prepare_registration("a_medias", "nuevo@ucm.es")

        half_done.refresh_from_db()
        self.assertTrue(half_done.is_deleted)
        self.assertFalse(AuthService.username_is_taken("a_medias"))

    def test_discarding_an_unverified_account_does_not_free_a_taken_email(self):
        """
        El nombre se libera, pero el correo de OTRA cuenta sigue ocupado: son dos
        comprobaciones independientes y el orden importa.
        """
        half_done = create_user("a_medias")
        half_done.is_verify = False
        half_done.save()
        other_user = create_user("otro")

        with self.assertRaises(EmailAlreadyRegisteredError):
            AuthService.prepare_registration("a_medias", other_user.email)


class SecondFactorTest(TestCase):
    """
    El segundo factor del login, estaba reimplementado en
    `login_serializer.py` con su propia copia del hasheado y la caducidad.
    """

    def setUp(self):
        self.user = create_user("piloto")

    def test_a_user_without_a_code_has_none_pending(self):
        self.assertFalse(AuthService.has_pending_code(self.user))

    @LOCMEM_EMAIL
    def test_starting_it_reports_the_method_and_leaves_a_pending_code(self):
        """
        Devuelve el metodo empleado a proposito: es el punto donde ramificar
        cuando haya TOTP, y asi quien llama no tiene que suponerlo.
        """
        mail.outbox = []

        method = AuthService.start_second_factor(self.user)

        self.assertEqual(method, 'email')
        self.assertEqual(mail.outbox[0].to, [self.user.email])
        self.user.refresh_from_db()
        self.assertTrue(AuthService.has_pending_code(self.user))

    def test_checking_it_consumes_the_code(self):
        token, token_hash = AuthService.generate_token()
        self.user.token = token_hash
        self.user.token_expiration = timezone.now() + timedelta(minutes=5)
        self.user.save()

        AuthService.check_second_factor(self.user, token)

        self.user.refresh_from_db()
        self.assertFalse(AuthService.has_pending_code(self.user))

    def test_a_wrong_code_raises(self):
        self.user.token = AuthService.generate_token()[1]
        self.user.token_expiration = timezone.now() + timedelta(minutes=5)
        self.user.save()

        with self.assertRaises(InvalidTokenError):
            AuthService.check_second_factor(self.user, "XXXXXX")


class AuthPayloadTest(TestCase):

    def test_it_carries_both_tokens_and_the_user_data(self):
        user = create_user("entrando")

        payload = AuthService.build_auth_payload(user)

        self.assertIn('access', payload)
        self.assertIn('refresh', payload)
        self.assertEqual(payload['user']['username'], "entrando")
        # El id va como cadena, no como UUID
        self.assertIsInstance(payload['user']['id'], str)


def google_payload(email, **extra):
    """
    Payload de Google tal y como llega cuando todo va bien.
    El `email_verified` va aqui y no suelto en cada prueba porque es la
    situacion normal: las pruebas que van a por el caso sin verificar lo quitan
    o lo ponen a False a proposito.
    """
    return {'email': email, 'email_verified': True, **extra}

@override_settings(ALLOWED_DOMAINS=['*'])
class GoogleTest(TestCase):

    @patch('users.services.auth_service.id_token.verify_oauth2_token')
    def test_a_token_google_rejects_raises(self, verify):
        verify.side_effect = ValueError("firma invalida")

        with self.assertRaises(InvalidGoogleTokenError):
            AuthService.verify_google_token("token-falso")

    def test_a_payload_without_email_raises(self):
        with self.assertRaises(GoogleEmailMissingError):
            AuthService.find_google_user({'given_name': "Sin correo"})

    def test_an_unknown_email_raises(self):
        with self.assertRaises(UserNotFoundError):
            AuthService.find_google_user(google_payload("desconocido@gmail.com"))

    def test_an_existing_account_is_found(self):
        user = create_user("googler")

        self.assertEqual(AuthService.find_google_user(google_payload(user.email)), user)

    def test_an_email_that_google_does_not_vouch_for_does_not_open_the_account(self):
        """
        El correo es lo unico que identifica la cuenta en este flujo, asi que un
        `email_verified: false` no puede dar acceso a la cuenta de otro.
        """
        user = create_user("victima")

        with self.assertRaises(UnverifiedEmailError):
            AuthService.find_google_user({'email': user.email, 'email_verified': False})

    def test_a_payload_without_the_claim_counts_as_unverified(self):
        """La ausencia de prueba no es prueba: sin el claim, no se pasa."""
        user = create_user("victima")

        with self.assertRaises(UnverifiedEmailError):
            AuthService.find_google_user({'email': user.email})

    def test_registering_with_an_unverified_email_raises(self):
        with self.assertRaises(UnverifiedEmailError):
            AuthService.register_google_user(
                {'email': "sin-verificar@gmail.com", 'email_verified': False}, "ana", 'std'
            )

        self.assertFalse(Users.objects.filter(username="ana").exists())

    def test_entering_verifies_an_account_that_never_confirmed_its_email(self):
        """
        Antes se devolvian los JWT sin tocar `is_verify`, y la sesion resultante
        no servia para nada: `Users.is_authenticated` la rechazaba en todos los
        endpoints protegidos.
        """
        user = create_user("a-medias")
        user.is_verify = False
        user.save()

        AuthService.find_google_user(google_payload(user.email))

        user.refresh_from_db()
        self.assertTrue(user.is_verify)

    def test_claiming_an_unverified_account_invalidates_its_password(self):
        """
        Cualquiera puede registrar una direccion que no es suya el alta crea la
        fila antes de comprobar el correo y esperar a que su dueño entre por
        Google. La contraseña que dejo puesta el impostor no puede sobrevivir a
        ese momento account pre-hijacking.
        """
        user = create_user("pre-registrada")
        user.is_verify = False
        user.set_password("la-del-impostor")
        user.save()

        AuthService.find_google_user(google_payload(user.email))

        user.refresh_from_db()
        self.assertIsNone(user.password)
        self.assertFalse(user.check_password("la-del-impostor"))

    def test_a_verified_account_keeps_its_password(self):
        """Contraparte: quien ya estaba verificado no pierde nada por entrar con Google."""
        user = create_user("de-toda-la-vida")
        user.set_password("la-suya")
        user.save()

        AuthService.find_google_user(google_payload(user.email))

        user.refresh_from_db()
        self.assertTrue(user.check_password("la-suya"))

    def test_registering_creates_a_verified_account_without_password(self):
        payload = google_payload("nueva@gmail.com", given_name="Ana", family_name="Garcia")

        user = AuthService.register_google_user(payload, "ana", 'std')

        self.assertTrue(user.is_verify)   # Google ya acredita el correo
        self.assertFalse(user.has_2FA)
        self.assertIsNone(user.password)
        self.assertEqual(user.surname1, "Garcia")

    def test_the_surname_falls_back_to_the_given_name(self):
        payload = google_payload("sola@gmail.com", given_name="Ana")

        user = AuthService.register_google_user(payload, "ana", 'std')

        self.assertEqual(user.surname1, "Ana")

    def test_an_email_already_registered_raises(self):
        existing = create_user("existente")

        with self.assertRaises(EmailAlreadyRegisteredError):
            AuthService.register_google_user(google_payload(existing.email), "otro", 'std')

    def test_a_username_already_taken_raises(self):
        create_user("tomado")

        with self.assertRaises(UsernameAlreadyTakenError):
            AuthService.register_google_user(google_payload("libre@gmail.com"), "tomado", 'std')

    def test_an_unknown_user_type_raises_and_creates_nothing(self):
        with self.assertRaises(InvalidUserTypeError):
            AuthService.register_google_user(google_payload("libre@gmail.com"), "ana", 'NO_EXISTE')

        self.assertFalse(Users.objects.filter(username="ana").exists())
