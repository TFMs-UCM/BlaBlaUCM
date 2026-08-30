"""
Pruebas del FORMATO DE ERROR UNIFICADO de la API (IMPORTANTE.md §3.7).

La API devolvia los errores en tres formatos distintos y el cliente tenia que
saber cual le tocaba segun el endpoint y el tipo de fallo:
    1. La mayoria de endpoints     {"status": "error", "message": ..., "error_code": 6}
    2. CustomAPIException          {"error": {"code": "6", "message": ...}}
    3. Validacion de campo de DRF  {"password": ["Asegurese de que..."]}
"""
from django.test import override_settings
from rest_framework import status
from rest_framework.test import APITestCase

from api.errors import ErrorCodes
from travels.tests.factories import create_travel, create_user

LOCMEM_EMAIL = override_settings(
    EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend'
)

class UnifiedErrorFormatTest(APITestCase):
    """El formato canonico: lo que deberia leer un cliente nuevo."""

    def setUp(self):
        self.user = create_user("piloto")
        self.user.set_password("contrasena")
        self.user.has_2FA = False
        self.user.save()

    def assert_canonical(self, response):
        """Las cuatro claves que un cliente nuevo puede dar por seguras."""
        self.assertEqual(response.data['status'], 'error')
        self.assertIsInstance(response.data['error_code'], int)
        self.assertTrue(response.data['message'])
        self.assertIn('error', response.data)

    def test_a_failed_login_uses_the_canonical_format(self):
        """Antes salia solo como {"error": {"code": "6", ...}}."""
        response = self.client.post(
            "/api/v1/login/",
            {"username": "piloto", "password": "equivocada"},
            format='json',
        )

        # 400 y no 401: `CustomAPIException` lleva 400 por defecto y el login no
        # lo cambia. Es el contrato actual y el manejador no lo toca.
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assert_canonical(response)
        self.assertEqual(response.data['error_code'], ErrorCodes.INVALID_CREDENTIALS)

    @LOCMEM_EMAIL
    def test_a_field_validation_error_uses_the_canonical_format(self):
        """Antes salia solo como {"password": ["..."]}, sin ningun codigo."""
        response = self.client.post(
            "/api/v1/register/",
            {
                "username": "nuevo", "email": "nuevo@ucm.es",
                "password": "abc", "password_confirm": "abc",
                "name": "Nuevo", "surname1": "Apellido", "user_type": 1,
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assert_canonical(response)
        self.assertEqual(response.data['error_code'], ErrorCodes.VALIDATION_ERROR)

    def test_a_missing_required_field_is_told_apart_from_a_malformed_one(self):
        """
        Un campo que falta y un campo con formato malo son cosas distintas para
        quien pinta la pantalla, y el manejador los distingue por el `code` que
        DRF pone en cada `ErrorDetail`.
        """
        response = self.client.post(
            "/api/v1/register/",
            {"username": "nuevo"},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.MISSING_REQUIRED_FIELD)

    def test_an_unauthenticated_request_uses_the_canonical_format(self):
        """No lo lanza el codigo del proyecto, lo lanza DRF. Tambien se normaliza."""
        response = self.client.get("/api/v1/travel/")

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
        self.assert_canonical(response)

    def test_a_not_found_uses_the_canonical_format(self):
        """
        El 404 de DRF traia {"detail": "..."} , un cuarto formato que ni siquiera
        estaba en la lista de §3.7 porque solo aparece al pedir algo que no hay.
        """
        self.client.force_authenticate(user=self.user)

        response = self.client.get("/api/v1/users/00000000-0000-0000-0000-000000000000/")

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assert_canonical(response)
        self.assertEqual(response.data['error_code'], ErrorCodes.NOT_FOUND)

    def test_a_forbidden_action_uses_the_canonical_format(self):
        """Un metodo no permitido sobre un catalogo de solo lectura"""
        self.client.force_authenticate(user=self.user)

        response = self.client.post("/api/v1/usertypes/", {"name": "inventado"}, format='json')

        self.assertEqual(response.status_code, status.HTTP_405_METHOD_NOT_ALLOWED)
        self.assert_canonical(response)
        self.assertEqual(response.data['error_code'], ErrorCodes.METHOD_NOT_ALLOWED)

    def test_the_handler_does_not_touch_a_successful_response(self):
        """
        Comprobacion de que el manejador no se ha llevado nada por delante: solo
        actua sobre excepciones, no sobre respuestas correctas.
        """
        self.client.force_authenticate(user=self.user)

        response = self.client.get(f"/api/v1/users/{self.user.pk}/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertNotIn('error_code', response.data)


class BackwardsCompatibilityTest(APITestCase):
    """
    Lo que permite desplegar sin coordinar con la app
    """

    def setUp(self):
        self.user = create_user("piloto")
        self.user.set_password("contrasena")
        self.user.has_2FA = False
        self.user.save()

    def test_the_old_error_block_of_custom_api_exception_survives(self):
        """La app lee `error.code` en login y registro."""
        response = self.client.post(
            "/api/v1/login/",
            {"username": "piloto", "password": "equivocada"},
            format='json',
        )

        self.assertEqual(int(response.data['error']['code']), ErrorCodes.INVALID_CREDENTIALS)
        self.assertTrue(response.data['error']['message'])

    def test_the_code_of_the_old_block_is_still_a_string(self):
        response = self.client.post(
            "/api/v1/login/",
            {"username": "piloto", "password": "equivocada"},
            format='json',
        )

        self.assertIsInstance(response.data['error']['code'], str)
        self.assertIsInstance(response.data['error_code'], int)

    @LOCMEM_EMAIL
    def test_the_field_key_of_a_validation_error_survives(self):
        """La app pinta el mensaje debajo del campo, leyendo `response['password']`."""
        response = self.client.post(
            "/api/v1/register/",
            {
                "username": "nuevo", "email": "nuevo@ucm.es",
                "password": "abc", "password_confirm": "abc",
                "name": "Nuevo", "surname1": "Apellido", "user_type": 1,
            },
            format='json',
        )

        self.assertIn('password', response.data)
        self.assertIsInstance(response.data['password'], list)
        # Y ademas agrupados, que es como deberia leerlos un cliente nuevo
        self.assertEqual(response.data['fields']['password'], response.data['password'])

    def test_a_field_called_error_or_status_does_not_shadow_the_envelope(self):
        """
        Trampa de mezclar las claves del campo con las del sobre: si un
        serializer tuviera un campo llamado `status` o `error`, la copia de
        compatibilidad podria pisar el sobre y dejar la respuesta sin formato.
        El manejador usa `setdefault`, asi que el sobre gana.
        """
        response = self.client.post(
            "/api/v1/login/",
            {"username": "piloto", "password": "equivocada"},
            format='json',
        )

        self.assertEqual(response.data['status'], 'error')
        self.assertIsInstance(response.data['error'], dict)


class ViewsThatBuildTheirOwnResponseTest(APITestCase):
    """
    Las vistas que construyen la Response a mano NO pasan por el manejador: por
    eso el formato canonico se eligio igual al suyo, y no al reves.

    Si se hubiera elegido otro, habria habido que tocar todas las vistas.
    """

    def setUp(self):
        self.user = create_user("piloto")
        self.other = create_user("otro")
        self.client.force_authenticate(user=self.user)

    def test_a_hand_built_error_already_matches_the_canonical_format(self):
        travel = create_travel(self.other)

        response = self.client.post(f"/api/v1/travel/{travel.pk}/finish_travel/")

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data['status'], 'error')
        self.assertEqual(response.data['error_code'], ErrorCodes.INSUFICIENT_CREDENTIALS)
        self.assertTrue(response.data['message'])
