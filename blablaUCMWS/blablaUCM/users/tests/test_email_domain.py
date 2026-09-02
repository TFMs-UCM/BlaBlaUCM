"""
Pruebas de LA RESTRICCION POR DOMINIO DE CORREO y de LA NORMALIZACION.
    POST /api/v1/register/                    (alta con usuario y contraseña)
    POST /api/v1/users/verification_email/    (paso 1 del cambio de correo)
    POST /api/v1/users/verify_code/           (paso 2 del cambio de correo)
    POST /api/v1/login/                       (aqui NO se aplica, a proposito)
"""
import re

from django.core import mail
from django.db import IntegrityError, transaction
from django.test import TestCase, override_settings
from rest_framework import status
from rest_framework.test import APITestCase

from api.errors import ErrorCodes
from travels.tests.factories import create_user
from users.models import Users, normalize_email
from users.services.auth_service import AuthService
from users.services.exceptions import EmailDomainNotAllowedError
from users.services.user_service import UserService

# Contraseña que cumple los cuatro validadores de AUTH_PASSWORD_VALIDATORS
GOOD_PASSWORD = "Kx7pq2"

LOCMEM_EMAIL = override_settings(
    EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend'
)

ONLY_UCM = override_settings(ALLOWED_DOMAINS=['ucm.es'])
ANY_DOMAIN = override_settings(ALLOWED_DOMAINS=['*'])

@ONLY_UCM
class RegistrationDomainTest(APITestCase):
    """Puerta 1: el alta con usuario y contraseña."""

    def payload(self, email, username="nuevo"):
        return {
            "username": username,
            "email": email,
            "password": GOOD_PASSWORD,
            "password_confirm": GOOD_PASSWORD,
            "name": "Nombre",
            "surname1": "Apellido",
            "user_type": "std",
        }

    def register(self, email, username="nuevo"):
        return self.client.post(
            "/api/v1/register/", self.payload(email, username), format='json'
        )

    def test_a_foreign_domain_is_rejected(self):
        response = self.register("nuevo@gmail.com")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.EMAIL_DOMAIN_NOT_ALLOWED)
        self.assertFalse(Users.objects.filter(username="nuevo").exists())

    def test_the_allowed_domain_still_registers(self):
        """
        La contrapartida: la restriccion no se aprueba rechazandolo todo.
        """
        response = self.register("nuevo@ucm.es")

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_a_lookalike_domain_is_rejected(self):
        """
        El caso que separa comparar por igualdad de comparar por sufijo: con
        `email.endswith('ucm.es')` esta direccion, que es de un dominio ajeno,
        pasaria el filtro.
        """
        response = self.register("nuevo@ucm.es.dominio-de-otro.com")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.EMAIL_DOMAIN_NOT_ALLOWED)

    def test_the_error_explains_itself_without_naming_the_domains(self):
        """
        El mensaje lo pone el servidor, para que la aplicacion no tenga que
        traducir el codigo 12 por su cuenta. Y no nombra los dominios admitidos:
        el usuario legitimo ya sabe cual es su correo de la universidad, y
        decirlos convertiria un registro fallido en la forma de averiguar que
        direcciones tienen cuenta aqui.
        """
        response = self.register("nuevo@gmail.com")

        self.assertEqual(
            response.data['message'],
            "El correo no pertenece al dominio permitido, utiliza otro"
        )
        self.assertNotIn("ucm.es", response.data['message'])

    def test_several_domains_are_admitted(self):
        with override_settings(ALLOWED_DOMAINS=['ucm.es', 'estudiante.ucm.es']):
            primero = self.register("uno@ucm.es", username="uno")
            segundo = self.register("dos@estudiante.ucm.es", username="dos")

        self.assertEqual(primero.status_code, status.HTTP_201_CREATED)
        self.assertEqual(segundo.status_code, status.HTTP_201_CREATED)

    def test_a_rejected_registration_does_not_discard_a_pending_one(self):
        """
        `prepare_registration` descarta las altas a medias que ocupen el nombre
        de usuario. Por eso la comprobacion del dominio va la PRIMERA: si fuera
        despues, un alta que se va a rechazar igualmente habria borrado por el
        camino el registro pendiente de otra persona.
        """
        pendiente = create_user("nuevo")
        pendiente.is_verify = False
        pendiente.save()

        response = self.register("nuevo@gmail.com")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        pendiente.refresh_from_db()
        self.assertFalse(pendiente.is_deleted)


@ANY_DOMAIN
class NoRestrictionByDefaultTest(APITestCase):
    """
    El valor por defecto de `ALLOWED_DOMAINS` es '*'
    """

    def test_any_domain_registers_when_the_list_is_the_wildcard(self):
        response = self.client.post("/api/v1/register/", {
            "username": "nuevo",
            "email": "nuevo@gmail.com",
            "password": GOOD_PASSWORD,
            "password_confirm": GOOD_PASSWORD,
            "name": "Nombre",
            "surname1": "Apellido",
            "user_type": "std",
        }, format='json')

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_the_service_lets_anything_through(self):
        # No lanza
        AuthService.assert_email_domain_is_allowed("cualquiera@dominio.com")


@ONLY_UCM
@LOCMEM_EMAIL
class EmailChangeDomainTest(APITestCase):
    """
    Puerta 2: el cambio de correo desde el perfil
    Es la que de verdad cierra la restriccion
    """

    def setUp(self):
        self.user = create_user("dueño")
        self.user.email = "dueño@ucm.es"
        self.user.save()
        self.client.force_authenticate(user=self.user)
        mail.outbox = []

    def token_from_last_email(self):
        body = mail.outbox[-1].body
        match = re.search(r'margin:16px 0;">\s*([A-Za-z0-9]{6})\s*</div>', body)
        self.assertIsNotNone(match, f"No se encontro el token en el correo:\n{body}")
        return match.group(1)

    def request_code(self, email=None):
        payload = {'username': "dueño"}
        if email:
            payload['email'] = email
        return self.client.post(
            "/api/v1/users/verification_email/", payload, format='json'
        )

    def test_the_code_is_not_sent_to_an_address_outside_the_domain(self):
        """
        Se rechaza ya en el primer paso para no mandar un codigo a un buzon de
        fuera y decirle al usuario que no vale despues de ir a buscarlo.
        """
        response = self.request_code(email="dueño@gmail.com")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.EMAIL_DOMAIN_NOT_ALLOWED)
        self.assertEqual(len(mail.outbox), 0)

    def test_the_email_cannot_be_moved_outside_the_domain(self):
        """
        La comprobacion que cuenta, y el motivo de que no baste con la del primer
        paso: el codigo se pide para una direccion admitida
        """
        self.request_code(email="nuevo@ucm.es")

        response = self.client.post("/api/v1/users/verify_code/", {
            'username': "dueño",
            'token': self.token_from_last_email(),
            'email': "dueño@gmail.com",
        }, format='json')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.EMAIL_DOMAIN_NOT_ALLOWED)
        self.user.refresh_from_db()
        self.assertEqual(self.user.email, "dueño@ucm.es")

    def test_the_code_survives_a_rejected_change(self):
        """
        El codigo es de un solo uso, pero un cambio rechazado por el dominio no
        lo gasta: el rechazo va ANTES de consumirlo, igual que la politica de
        contraseñas
        """
        self.request_code(email="otro@ucm.es")
        token = self.token_from_last_email()

        self.client.post("/api/v1/users/verify_code/", {
            'username': "dueño", 'token': token, 'email': "dueño@gmail.com",
        }, format='json')

        segundo_intento = self.client.post("/api/v1/users/verify_code/", {
            'username': "dueño", 'token': token, 'email': "otro@ucm.es",
        }, format='json')

        self.assertEqual(segundo_intento.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertEqual(self.user.email, "otro@ucm.es")

    def test_a_change_within_the_domain_still_works(self):
        self.request_code(email="nuevo@ucm.es")
        response = self.client.post("/api/v1/users/verify_code/", {
            'username': "dueño",
            'token': self.token_from_last_email(),
            'email': "nuevo@ucm.es",
        }, format='json')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertEqual(self.user.email, "nuevo@ucm.es")


@ONLY_UCM
class LoginIsNotRestrictedTest(APITestCase):

    def setUp(self):
        self.user = create_user("veterano")
        self.user.email = "veterano@gmail.com"
        self.user.has_2FA = False
        self.user.set_password(GOOD_PASSWORD)
        self.user.save()

    def test_an_account_with_a_foreign_domain_still_logs_in(self):
        response = self.client.post("/api/v1/login/", {
            'username': "veterano", 'password': GOOD_PASSWORD,
        }, format='json')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('access', response.data)

    def test_it_also_logs_in_using_the_foreign_email(self):
        response = self.client.post("/api/v1/login/", {
            'username': "veterano@gmail.com", 'password': GOOD_PASSWORD,
        }, format='json')

        self.assertEqual(response.status_code, status.HTTP_200_OK)


class EmailNormalizationTest(TestCase):
    """
    `Pepe@ucm.es` y `pepe@ucm.es` son el mismo buzon y ahora tambien el mismo
    correo para la aplicacion.
    """

    def test_the_stored_email_is_lowercased(self):
        user = create_user("mayusculas")
        user.email = "  Pepe@UCM.es  "
        user.save()

        user.refresh_from_db()
        self.assertEqual(user.email, "pepe@ucm.es")

    def test_an_address_is_taken_regardless_of_case(self):
        create_user("pepe").email  # el factory crea pepe@ucm.es
        Users.objects.filter(username="pepe").update(email="pepe@ucm.es")

        self.assertTrue(AuthService.email_is_taken("PEPE@ucm.es"))

    def test_the_account_is_found_regardless_of_case(self):
        user = create_user("pepe")

        encontrado = UserService.find_by_username_or_email("PePe@UCM.ES")

        self.assertEqual(encontrado.pk, user.pk)

    def test_the_database_refuses_two_addresses_that_differ_only_in_case(self):
        """
        La restriccion unica compara con `Lower`, asi que la regla se cumple
        tambien para lo que no pase por `Users.save()`
        """
        create_user("primero")
        Users.objects.filter(username="primero").update(email="choque@ucm.es")
        otro = create_user("segundo")

        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                Users.objects.filter(pk=otro.pk).update(email="CHOQUE@ucm.es")

    def test_a_deleted_account_does_not_block_the_address(self):
        """
        La restriccion sigue siendo condicional a `is_deleted=False`: pasar a
        comparar en minusculas no cambia esa parte.
        """
        borrado = create_user("borrado")
        Users.objects.filter(pk=borrado.pk).update(
            email="reutilizable@ucm.es", is_deleted=True
        )
        nuevo = create_user("nuevo")

        Users.objects.filter(pk=nuevo.pk).update(email="Reutilizable@ucm.es")

        self.assertFalse(AuthService.email_is_taken("reutilizable@ucm.es", excluding=nuevo))

    def test_normalize_email_tolerates_the_empty_value(self):
        self.assertEqual(normalize_email(None), "")
        self.assertEqual(normalize_email(""), "")


@ONLY_UCM
class DomainCheckIsCaseInsensitiveTest(TestCase):
    """
    El dominio se compara ya normalizado, asi que escribirlo en mayusculas no
    esquiva la lista ni rechaza a quien si tiene derecho a entrar.
    """

    def test_an_allowed_domain_in_capitals_is_accepted(self):
        # No lanza
        AuthService.assert_email_domain_is_allowed("Pepe@UCM.ES")

    def test_a_foreign_domain_in_capitals_is_still_rejected(self):
        with self.assertRaises(EmailDomainNotAllowedError):
            AuthService.assert_email_domain_is_allowed("Pepe@GMAIL.COM")
