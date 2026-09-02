"""
Pruebas de CARACTERIZACION de la autenticacion.
    POST /api/v1/login/
    POST /api/v1/register/
    POST /api/v1/auth/refresh/
    POST /api/v1/auth/google/login/
    POST /api/v1/auth/google/register/
"""
import hashlib
from datetime import timedelta
from unittest.mock import patch

from django.core import mail
from django.test import override_settings
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from api.errors import ErrorCodes
from travels.tests.factories import create_user
from users.models import UserType, Users

LOCMEM_EMAIL = override_settings(
    EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend'
)

def error_code(response):
    payload = response.data
    if isinstance(payload.get('error'), dict):
        return int(payload['error']['code'])
    if 'error_code' in payload:
        return int(payload['error_code'])
    raise AssertionError(f"Formato de error no reconocido: {payload!r}")


def create_user_with_password(username, password, has_2fa=False):
    user = create_user(username)
    user.set_password(password)
    user.has_2FA = has_2fa
    user.save()
    return user


class LoginTest(APITestCase):

    def setUp(self):
        self.user = create_user_with_password("piloto", "contrasena")

    def login(self, **payload):
        return self.client.post("/api/v1/login/", payload, format='json')

    def test_login_with_username_returns_the_tokens(self):
        response = self.login(username="piloto", password="contrasena")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('access', response.data)
        self.assertIn('refresh', response.data)
        self.assertEqual(response.data['user']['username'], "piloto")

    def test_login_with_email_also_works(self):
        response = self.login(username=self.user.email, password="contrasena")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('access', response.data)

    def test_wrong_password_returns_invalid_credentials(self):
        response = self.login(username="piloto", password="equivocada")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(error_code(response), ErrorCodes.INVALID_CREDENTIALS)

    def test_unknown_user_returns_user_dont_exist(self):
        response = self.login(username="fantasma", password="contrasena")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(error_code(response), ErrorCodes.USER_DONT_EXIST)

    def test_an_unverified_user_is_reported_as_nonexistent(self):
        """
        Decision de diseño deliberada: a un usuario sin verificar se le responde
        lo mismo que a uno que no existe, para no revelar que la cuenta esta
        creada. El propio codigo lo comenta.
        """
        self.user.is_verify = False
        self.user.save()

        response = self.login(username="piloto", password="contrasena")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(error_code(response), ErrorCodes.USER_DONT_EXIST)

    def test_missing_fields_return_insufficient_credentials(self):
        response = self.login(username="piloto")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_a_deleted_user_cannot_log_in(self):
        self.user.is_deleted = True
        self.user.save()

        response = self.login(username="piloto", password="contrasena")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(error_code(response), ErrorCodes.USER_DONT_EXIST)


@LOCMEM_EMAIL
class LoginWith2FATest(APITestCase):
    """
    `has_2FA` viene activado por defecto en el modelo, asi que este es el camino
    normal de la aplicacion: primera llamada envia el codigo, segunda lo canjea.
    """

    def setUp(self):
        self.user = create_user_with_password("piloto", "contrasena", has_2fa=True)
        mail.outbox = []

    def login(self, **payload):
        return self.client.post("/api/v1/login/", payload, format='json')

    def test_first_call_sends_the_code_and_does_not_return_tokens(self):
        response = self.login(username="piloto", password="contrasena")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['requires_2fa'])
        self.assertNotIn('access', response.data)

        # El codigo se manda al correo del propio usuario, no a uno elegido
        self.assertEqual(len(mail.outbox), 1)
        self.assertEqual(mail.outbox[0].to, [self.user.email])

    def test_second_call_with_the_right_code_returns_the_tokens(self):
        code = "AB12cd"
        self.user.token = hashlib.sha256(code.encode()).hexdigest()
        self.user.token_expiration = timezone.now() + timedelta(minutes=5)
        self.user.save()

        response = self.login(username="piloto", password="contrasena", code=code)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('access', response.data)

    def test_the_2fa_code_is_invalidated_after_use(self):
        """
        Aqui SI se limpian `token` y `token_expiration` tras canjear el codigo.
        El flujo de `verify_code` de recuperacion de cuenta NO lo hace, y por eso
        alli el codigo se puede reutilizar. La forma correcta ya existe en el
        proyecto, 200 lineas mas alla.
        """
        code = "AB12cd"
        self.user.token = hashlib.sha256(code.encode()).hexdigest()
        self.user.token_expiration = timezone.now() + timedelta(minutes=5)
        self.user.save()

        self.login(username="piloto", password="contrasena", code=code)

        self.user.refresh_from_db()
        self.assertIsNone(self.user.token)
        self.assertIsNone(self.user.token_expiration)

    def test_a_wrong_code_is_rejected(self):
        self.user.token = hashlib.sha256("correcto".encode()).hexdigest()
        self.user.token_expiration = timezone.now() + timedelta(minutes=5)
        self.user.save()

        response = self.login(username="piloto", password="contrasena", code="ERRONEO")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(error_code(response), ErrorCodes.INCORRECT_TOKEN)

    def test_an_expired_code_is_rejected(self):
        code = "AB12cd"
        self.user.token = hashlib.sha256(code.encode()).hexdigest()
        self.user.token_expiration = timezone.now() - timedelta(minutes=1)
        self.user.save()

        response = self.login(username="piloto", password="contrasena", code=code)

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(error_code(response), ErrorCodes.TOKEN_EXPIRED)


class RegisterTest(APITestCase):

    def payload(self, **overrides):
        data = {
            'username': "nuevo",
            'email': "nuevo@ucm.es",
            'password': "contrasena-de-alta",
            'password_confirm': "contrasena-de-alta",
            'name': "Nombre",
            'surname1': "Apellido",
            'user_type': 'std',
        }
        data.update(overrides)
        return data

    def register(self, **overrides):
        return self.client.post("/api/v1/register/", self.payload(**overrides), format='json')

    def test_registering_a_new_user_returns_201(self):
        response = self.register()

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data['user']['username'], "nuevo")

        user = Users.objects.get(username="nuevo")
        # La contraseña se guarda hasheada, nunca en claro
        self.assertNotEqual(user.password, "contrasena-de-alta")
        self.assertTrue(user.check_password("contrasena-de-alta"))

    def test_a_new_user_starts_unverified(self):
        self.register()

        self.assertFalse(Users.objects.get(username="nuevo").is_verify)

    def test_mismatched_passwords_are_rejected(self):
        # La confirmacion debe pasar antes el min_length del campo, si no se
        # queda en la validacion de formato y nunca se comparan
        response = self.register(password_confirm="otradistinta")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(error_code(response), ErrorCodes.PASSWORD_MISMATCH)

    def test_a_short_password_now_uses_the_same_format_as_everything_else(self):

        response = self.register(password="abc", password_confirm="abc")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(error_code(response), ErrorCodes.VALIDATION_ERROR)
        self.assertIn('password', response.data)        # compatibilidad
        self.assertIn('password', response.data['fields'])

    def test_an_existing_verified_username_is_rejected(self):
        create_user("nuevo")

        response = self.register()

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)
        self.assertEqual(error_code(response), ErrorCodes.USERNAME_ALREADY_EXISTS)

    def test_an_existing_unverified_username_is_replaced(self):
        """
        Si habia un registro a medias sin verificar, se descarta y se deja
        continuar: evita que un registro abandonado bloquee el nombre.
        """
        stale = create_user("nuevo")
        stale.is_verify = False
        stale.save()

        response = self.register()

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

        # La fila antigua sigue ahi, marcada como borrada
        stale.refresh_from_db()
        self.assertTrue(stale.is_deleted)

        # Y la cuenta nueva es otra, con el mismo nombre y sin verificar
        fresh = Users.objects.get(username="nuevo", is_deleted=False)
        self.assertNotEqual(fresh.pk, stale.pk)
        self.assertFalse(fresh.is_verify)


class TokenRefreshTest(APITestCase):

    def setUp(self):
        self.user = create_user_with_password("piloto", "contrasena")
        login = self.client.post(
            "/api/v1/login/", {'username': "piloto", 'password': "contrasena"}, format='json'
        )
        self.refresh_token = login.data['refresh']

    def refresh(self, token):
        return self.client.post("/api/v1/auth/refresh/", {'refresh': token}, format='json')

    def test_a_valid_refresh_returns_a_new_access_token(self):
        response = self.refresh(self.refresh_token)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('access', response.data)

    def test_a_malformed_token_is_rejected(self):
        response = self.refresh("esto-no-es-un-token")

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_the_token_of_a_deleted_user_is_rejected(self):
        """
        Comprobacion explicita del serializer: la firma puede ser valida pero el
        usuario ya no estar. Sin ella se emitirian access tokens en bucle para
        un usuario inexistente.
        """
        self.user.is_deleted = True
        self.user.save()

        response = self.refresh(self.refresh_token)

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)


class GoogleLoginTest(APITestCase):

    def setUp(self):
        self.user = create_user("googler")

    def google_login(self, **payload):
        return self.client.post("/api/v1/auth/google/login/", payload, format='json')

    def test_missing_id_token_returns_400(self):
        response = self.google_login()

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    @patch('users.services.auth_service.id_token.verify_oauth2_token')
    def test_an_existing_user_gets_their_tokens(self, verify):
        verify.return_value = {'email': self.user.email, 'email_verified': True}

        response = self.google_login(id_token="token-de-google")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('access', response.data)
        self.assertEqual(response.data['user']['username'], "googler")

    @patch('users.services.auth_service.id_token.verify_oauth2_token')
    def test_an_unknown_email_returns_404(self, verify):
        verify.return_value = {'email': "desconocido@gmail.com", 'email_verified': True}

        response = self.google_login(id_token="token-de-google")

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    @patch('users.services.auth_service.id_token.verify_oauth2_token')
    def test_an_invalid_google_token_returns_401(self, verify):
        verify.side_effect = ValueError("firma invalida")

        response = self.google_login(id_token="token-falso")

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    @patch('users.services.auth_service.id_token.verify_oauth2_token')
    def test_a_payload_without_email_returns_400(self, verify):
        verify.return_value = {'given_name': "Sin correo"}

        response = self.google_login(id_token="token-de-google")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    @patch('users.services.auth_service.id_token.verify_oauth2_token')
    def test_an_email_that_google_does_not_vouch_for_returns_403(self, verify):
        """
        El token es valido; lo que no vale es el correo que trae. Sin esta
        comprobacion, un id_token con el correo de otra persona abria su cuenta.
        """
        verify.return_value = {'email': self.user.email, 'email_verified': False}

        response = self.google_login(id_token="token-de-google")

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertNotIn('access', response.data)

    @patch('users.services.auth_service.id_token.verify_oauth2_token')
    def test_a_payload_without_the_claim_also_returns_403(self, verify):
        verify.return_value = {'email': self.user.email}

        response = self.google_login(id_token="token-de-google")

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    @patch('users.services.auth_service.id_token.verify_oauth2_token')
    def test_entering_leaves_a_half_finished_account_usable(self, verify):
        """
        Una cuenta sin verificar recibia los JWT y despues fallaba en todos los
        endpoints protegidos, porque `Users.is_authenticated` los rechaza.
        """
        self.user.is_verify = False
        self.user.save()
        verify.return_value = {'email': self.user.email, 'email_verified': True}

        response = self.google_login(id_token="token-de-google")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertTrue(self.user.is_verify)


@override_settings(ALLOWED_DOMAINS=['*'])
class GoogleRegisterTest(APITestCase):

    def google_register(self, **payload):
        return self.client.post("/api/v1/auth/google/register/", payload, format='json')

    @patch('users.services.auth_service.id_token.verify_oauth2_token')
    def test_registering_creates_a_verified_user_without_password(self, verify):
        verify.return_value = {
            'email': "nuevo@gmail.com", 'email_verified': True,
            'given_name': "Ana", 'family_name': "Garcia"
        }

        response = self.google_register(
            id_token="token-de-google", username="ana", user_type='std'
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('access', response.data)

        user = Users.objects.get(username="ana")
        self.assertTrue(user.is_verify)   # no hace falta verificar el correo
        self.assertFalse(user.has_2FA)    # ni segundo factor
        self.assertIsNone(user.password)  # ni contraseña
        self.assertEqual(user.name, "Ana")
        self.assertEqual(user.surname1, "Garcia")

    @patch('users.services.auth_service.id_token.verify_oauth2_token')
    def test_the_surname_falls_back_to_the_given_name(self, verify):
        verify.return_value = {
            'email': "solo@gmail.com", 'email_verified': True, 'given_name': "Ana"
        }

        self.google_register(id_token="t", username="ana", user_type='std')

        self.assertEqual(Users.objects.get(username="ana").surname1, "Ana")

    @patch('users.services.auth_service.id_token.verify_oauth2_token')
    def test_an_email_already_registered_returns_409(self, verify):
        existing = create_user("existente")
        verify.return_value = {
            'email': existing.email, 'email_verified': True, 'given_name': "Ana"
        }

        response = self.google_register(id_token="t", username="otro", user_type='std')

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)

    @patch('users.services.auth_service.id_token.verify_oauth2_token')
    def test_a_username_already_taken_returns_409(self, verify):
        create_user("ocupado")
        verify.return_value = {
            'email': "libre@gmail.com", 'email_verified': True, 'given_name': "Ana"
        }

        response = self.google_register(id_token="t", username="ocupado", user_type='std')

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)

    @patch('users.services.auth_service.id_token.verify_oauth2_token')
    def test_an_unknown_user_type_returns_400(self, verify):
        verify.return_value = {
            'email': "libre@gmail.com", 'email_verified': True, 'given_name': "Ana"
        }

        response = self.google_register(id_token="t", username="ana", user_type='NO_EXISTE')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(UserType.objects.filter(code='NO_EXISTE').count(), 0)

    @patch('users.services.auth_service.id_token.verify_oauth2_token')
    def test_an_unverified_email_returns_403_and_creates_nothing(self, verify):
        """
        La cuenta que crea este endpoint nace verificada. Si el correo no lo
        estuviera, naceria dada por buena sobre una direccion que nadie ha
        comprobado.
        """
        verify.return_value = {
            'email': "sin-verificar@gmail.com", 'email_verified': False, 'given_name': "Ana"
        }

        response = self.google_register(id_token="t", username="ana", user_type='std')

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertFalse(Users.objects.filter(username="ana").exists())

    def test_the_mandatory_fields_are_checked_before_talking_to_google(self):
        # Sin parchear nada: si llegara a Google, la prueba fallaria por red
        self.assertEqual(
            self.google_register(id_token="t", user_type='std').status_code,
            status.HTTP_400_BAD_REQUEST,
        )
        self.assertEqual(
            self.google_register(id_token="t", username="ana").status_code,
            status.HTTP_400_BAD_REQUEST,
        )
