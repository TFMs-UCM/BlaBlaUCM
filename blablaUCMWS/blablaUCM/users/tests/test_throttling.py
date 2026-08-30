"""
Pruebas de la LIMITACION DE PETICIONES (throttling).
    POST /api/v1/login/                              ambito 'login'
    POST /api/v1/users/verification_email/            ambito 'verification_email'
    POST /api/v1/users/verify_code/                   ambito 'verify_code'
    GET  /api/v1/users/verify_user/                   ambito 'user_lookup'
    POST /api/v1/users/{id}/two_factor/               ambito 'two_factor'
    POST /api/v1/travel/{id}/validate_passenger/      ambito 'validation_code'
    POST /api/v1/auth/google/{login,register}/        ambito 'oauth_login'
"""
from unittest.mock import patch

from django.conf import settings
from django.core.cache import cache
from django.test import override_settings
from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework.throttling import SimpleRateThrottle

from travels.tests.factories import create_request, create_travel, create_user

# Ritmos bajos para no tener que hacer cientos de peticiones en las pruebas
TEST_THROTTLES = {
    'verification_email': '2/hour',
    'verify_code': '2/hour',
    'user_lookup': '2/hour',
    'login': '3/minute',
    'validation_code': '3/minute',
    'oauth_login': '3/minute',
    'register': '3/hour',
    'token_refresh': '3/hour',
    'two_factor': '2/hour',
}


class BaseThrottleTest(APITestCase):
    """Enciende el throttling con ritmos bajos y lo deja como estaba al terminar."""

    def setUp(self):
        # El historial de peticiones vive en la cache: sin esto, una prueba
        # arrastraria el recuento de la anterior
        cache.clear()

        # Se modifica el diccionario en el sitio, no se sustituye: la clase de DRF
        # guarda una referencia a este mismo objeto desde que se importo
        self._original_throttles = dict(SimpleRateThrottle.THROTTLE_RATES)
        SimpleRateThrottle.THROTTLE_RATES.update(TEST_THROTTLES)

    def tearDown(self):
        SimpleRateThrottle.THROTTLE_RATES.clear()
        SimpleRateThrottle.THROTTLE_RATES.update(self._original_throttles)
        cache.clear()


class LoginThrottleTest(BaseThrottleTest):
    """
    El caso mas importante: `login` no tenia ningun limite, asi que se podian
    probar contraseñas en bucle contra cualquier cuenta.
    """

    def setUp(self):
        super().setUp()
        self.user = create_user("victima")
        self.user.set_password("la-buena")
        # Sin segundo factor: aqui se prueba el limite de peticiones, no el 2FA
        self.user.has_2FA = False
        self.user.save()

    def login(self, password):
        return self.client.post(
            "/api/v1/login/",
            {'username': "victima", 'password': password},
            format='json',
        )

    def test_repeated_failed_attempts_end_in_429(self):
        # El limite de prueba es 3/minute
        for _ in range(3):
            self.assertEqual(self.login("mal").status_code, status.HTTP_400_BAD_REQUEST)

        response = self.login("mal")

        self.assertEqual(response.status_code, status.HTTP_429_TOO_MANY_REQUESTS)

    def test_the_limit_also_applies_to_correct_attempts(self):
        """
        Los intentos acertados cuentan igual. Es lo que evita que se use el propio
        login como oraculo dando con la contraseña al cuarto intento.
        """
        for _ in range(3):
            self.login("mal")

        response = self.login("la-buena")

        self.assertEqual(response.status_code, status.HTTP_429_TOO_MANY_REQUESTS)
        self.assertNotIn('access', response.data)

    def test_below_the_limit_the_login_still_works(self):
        """Contraparte: el limite no puede estorbar al uso normal."""
        response = self.login("la-buena")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('access', response.data)


class VerificationEmailThrottleTest(BaseThrottleTest):

    def setUp(self):
        super().setUp()
        create_user("objetivo")

    def request_code(self):
        return self.client.post(
            "/api/v1/users/verification_email/", {'username': "objetivo"}, format='json'
        )

    @override_settings(EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend')
    def test_asking_for_codes_in_a_loop_ends_in_429(self):
        """
        Sin limite se podia inundar el buzon de cualquiera conociendo su nombre
        de usuario, y renovar el codigo indefinidamente.
        """
        for _ in range(2):
            self.assertEqual(self.request_code().status_code, status.HTTP_200_OK)

        self.assertEqual(self.request_code().status_code, status.HTTP_429_TOO_MANY_REQUESTS)

class VerifyCodeThrottleTest(BaseThrottleTest):

    def setUp(self):
        super().setUp()
        create_user("objetivo")

    def try_code(self, code):
        return self.client.post(
            "/api/v1/users/verify_code/",
            {'username': "objetivo", 'token': code},
            format='json',
        )

    def test_trying_codes_in_a_loop_ends_in_429(self):
        """
        El codigo son 6 caracteres: sin limite es atacable por fuerza bruta
        mientras siga vivo.
        """
        for _ in range(2):
            self.assertEqual(self.try_code("XXXXXX").status_code, status.HTTP_400_BAD_REQUEST)

        self.assertEqual(
            self.try_code("XXXXXX").status_code, status.HTTP_429_TOO_MANY_REQUESTS
        )


class UserLookupThrottleTest(BaseThrottleTest):
    """
    `verify_user` no se puede cerrar sin romper el registro,
    asi que el limite es la unica mitigacion: no impide comprobar un usuario
    concreto, pero si barrer una lista.
    """

    def lookup(self, username):
        return self.client.get(
            f"/api/v1/users/verify_user/?email={username}@ucm.es&username={username}"
        )

    def test_enumerating_in_a_loop_ends_in_429(self):
        for i in range(2):
            self.assertEqual(self.lookup(f"tanteo{i}").status_code, status.HTTP_200_OK)

        self.assertEqual(self.lookup("tanteo3").status_code, status.HTTP_429_TOO_MANY_REQUESTS)


class ValidationCodeThrottleTest(BaseThrottleTest):
    """
    El codigo de validacion del pasajero son 8 caracteres alfanumericos y el
    conductor lo teclea, asi que un numero bajo de intentos por minuto no molesta
    al uso real.
    """

    def setUp(self):
        super().setUp()
        self.driver = create_user("driver")
        self.travel = create_travel(self.driver, num_seats=3, remaining_seats=2)
        request_travel = create_request(self.travel, create_user("passenger"), 'accepted')
        request_travel.validation_code = "ABCD1234"
        request_travel.save()
        self.client.force_authenticate(user=self.driver)

    def validate_code(self, code):
        return self.client.post(
            f"/api/v1/travel/{self.travel.pk}/validate_passenger/",
            {'code': code},
            format='json',
        )

    def test_trying_codes_in_a_loop_ends_in_429(self):
        for _ in range(3):
            self.assertEqual(self.validate_code("NOEXISTE").status_code, status.HTTP_404_NOT_FOUND)

        self.assertEqual(self.validate_code("NOEXISTE").status_code, status.HTTP_429_TOO_MANY_REQUESTS)

    def test_below_the_limit_a_valid_code_still_validates(self):
        response = self.validate_code("ABCD1234")

        self.assertEqual(response.status_code, status.HTTP_200_OK)


class OAuthThrottleTest(BaseThrottleTest):
    """
    Los dos endpoints de Google se quedaron sin limite cuando se puso el del
    login con contraseña: son igual de publicos, no exigen autenticacion y cada
    llamada obliga al servidor a hablar con Google.
    """

    def setUp(self):
        super().setUp()
        self.user = create_user("googler")

    def google_login(self):
        return self.client.post(
            "/api/v1/auth/google/login/", {'id_token': "t"}, format='json'
        )

    @patch('users.services.auth_service.id_token.verify_oauth2_token')
    def test_repeated_attempts_end_in_429(self, verify):
        verify.return_value = {'email': "desconocido@gmail.com", 'email_verified': True}

        # El limite de prueba es 3/minute
        for _ in range(3):
            self.assertEqual(self.google_login().status_code, status.HTTP_404_NOT_FOUND)

        self.assertEqual(self.google_login().status_code, status.HTTP_429_TOO_MANY_REQUESTS)

    @patch('users.services.auth_service.id_token.verify_oauth2_token')
    def test_below_the_limit_the_login_still_works(self, verify):
        """Contraparte: el limite no puede estorbar al uso normal."""
        verify.return_value = {'email': self.user.email, 'email_verified': True}

        response = self.google_login()

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('access', response.data)

    @patch('users.services.auth_service.id_token.verify_oauth2_token')
    def test_the_registration_endpoint_shares_the_same_counter(self, verify):
        """
        Los dos endpoints cuentan en el mismo ambito: si no, se saltaria el
        limite alternando entre uno y otro.
        """
        verify.return_value = {'email': "desconocido@gmail.com", 'email_verified': True}
        for _ in range(3):
            self.google_login()

        response = self.client.post(
            "/api/v1/auth/google/register/",
            {'id_token': "t", 'username': "ana", 'user_type': 'std'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_429_TOO_MANY_REQUESTS)


class RegisterThrottleTest(BaseThrottleTest):

    def sign_up(self, n):
        return self.client.post(
            "/api/v1/register/",
            {
                'username': f"nuevo{n}",
                'email': f"nuevo{n}@ucm.es",
                'password': "contrasenia-larga",
                'password_confirm': "contrasenia-larga",
                'name': "Nombre",
                'surname1': "Apellido",
                # La FK va por `to_field='code'`, no por la clave primaria
                'user_type': 'std',
            },
            format='json',
        )

    def test_repeated_signups_end_in_429(self):
        # El limite de prueba es 3/hour
        for n in range(3):
            self.assertEqual(self.sign_up(n).status_code, status.HTTP_201_CREATED)

        response = self.sign_up(99)

        self.assertEqual(response.status_code, status.HTTP_429_TOO_MANY_REQUESTS)

    def test_below_the_limit_signing_up_still_works(self):
        response = self.sign_up(0)

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)


class TokenRefreshThrottleTest(BaseThrottleTest):
    """
    Renovar es publico y **cada llamada escribe**: rota el token y mete el
    anterior en la lista negra
    """

    def setUp(self):
        super().setUp()
        self.user = create_user("quien-renueva")

    def refresh(self):
        # No hace falta un token valido: el limite se aplica antes de mirarlo,
        # que es justo lo que interesa comprobar
        return self.client.post(
            "/api/v1/auth/refresh/", {'refresh': "lo-que-sea"}, format='json'
        )

    def test_repeated_refreshes_end_in_429(self):
        for _ in range(3):
            self.refresh()

        response = self.refresh()

        self.assertEqual(response.status_code, status.HTTP_429_TOO_MANY_REQUESTS)


class TwoFactorThrottleTest(BaseThrottleTest):
    """
    Activar y desactivar la verificacion en dos pasos admite probar contraseñas
    (y codigos, en las cuentas de Google) contra la cuenta propia, ademas de
    mandar correo. Sin limite seria otra vez el problema del login: un bucle
    contra la puerta que protege a todas las demas.
    """

    def setUp(self):
        super().setUp()
        self.user = create_user("con_2fa")
        self.user.set_password("la-buena")
        self.user.has_2FA = True
        self.user.save()
        self.client.force_authenticate(user=self.user)

    def disable(self, password):
        return self.client.post(
            f"/api/v1/users/{self.user.id}/two_factor/",
            {'enabled': False, 'password': password},
            format='json',
        )

    def test_trying_passwords_in_a_loop_ends_in_429(self):
        # El limite de prueba es 2/hour
        for _ in range(2):
            self.assertEqual(self.disable("mal").status_code, status.HTTP_400_BAD_REQUEST)

        response = self.disable("mal")

        self.assertEqual(response.status_code, status.HTTP_429_TOO_MANY_REQUESTS)
        self.user.refresh_from_db()
        self.assertTrue(self.user.has_2FA)


class ThrottlingIsOffInTheTestSuiteTest(APITestCase):
    """
    Fija la decision de infraestructura, para que no se descubra por sorpresa: en
    la suite el throttling esta apagado (`THROTTLE_ENABLED=False` en `.env.test`)
    porque muchas pruebas encadenan peticiones. Si alguien lo enciende sin querer,
    esta prueba avisa antes de que empiecen a fallar decenas de otras.
    """

    def test_the_rates_are_disabled(self):
        throttles = settings.REST_FRAMEWORK['DEFAULT_THROTTLE_RATES']

        self.assertEqual(set(throttles), {
            'verification_email', 'verify_code', 'user_lookup', 'login', 'validation_code',
            'oauth_login', 'register', 'token_refresh', 'two_factor',
        })
        for scope, throttle in throttles.items():
            with self.subTest(scope=scope):
                self.assertIsNone(throttle, "El throttling deberia estar apagado en las pruebas")
