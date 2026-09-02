"""
La documentacion de la API solo se abre con sesion de administrador
"""
from django.conf import settings
from django.contrib.auth.models import AnonymousUser, User
from django.http import Http404, HttpResponse
from django.test import RequestFactory, TestCase
from django.urls import reverse

from api.docs_access import staff_only

DOCS = '/api/v1/docs/'
SCHEMA = '/api/v1/schema/'
ROUTES = (DOCS, SCHEMA)

# Una ruta que no existe ni existira. Sirve de patron de comparacion: la
# documentacion tiene que responder igual que esto a quien no sea administrador.
MISSING_ROUTE = '/api/v1/esta-ruta-no-existe/'


class AnonymousDocsAccessTest(TestCase):
    """Sin sesion, la documentacion no existe."""

    def test_neither_route_answers_without_a_session(self):
        for route in ROUTES:
            with self.subTest(route=route):
                response = self.client.get(route)

                self.assertEqual(response.status_code, 404)

    def test_the_answer_is_the_same_as_for_a_route_that_does_not_exist(self):
        baseline = self.client.get(MISSING_ROUTE)

        for route in ROUTES:
            with self.subTest(route=route):
                response = self.client.get(route)

                self.assertEqual(response.status_code, baseline.status_code)
                self.assertEqual(response.content, baseline.content)

    def test_nothing_leaks_the_admin_url(self):
        # La razon de que esto no sea `staff_member_required`: aquel decorador
        # respondia con un 302 y `Location: /<ADMIN_URL>login/?next=...`, es decir,
        # regalaba la ruta del panel a quien pidiera una ruta previsible.
        admin_path = settings.ADMIN_URL.strip('/')

        for route in ROUTES:
            with self.subTest(route=route):
                response = self.client.get(route)

                self.assertNotIn('Location', response)
                self.assertNotIn(admin_path.encode(), response.content)

    def test_the_schema_body_never_leaks(self):
        response = self.client.get(SCHEMA)

        self.assertNotIn(b'openapi', response.content)


class NonStaffDocsAccessTest(TestCase):
    """Tener cuenta en Django no basta; hay que ser administrador."""

    def setUp(self):
        User.objects.create_user('curioso', 'curioso@example.com', 'clave-larga-123')
        self.client.login(username='curioso', password='clave-larga-123')

    def test_a_user_without_is_staff_is_turned_away(self):
        for route in ROUTES:
            with self.subTest(route=route):
                response = self.client.get(route)

                self.assertEqual(response.status_code, 404)


class DecoratorTest(TestCase):

    def setUp(self):
        self.factory = RequestFactory()
        self.view = staff_only(lambda http_request: HttpResponse(b'contenido secreto'))

    def _request(self, user_account):
        http_request = self.factory.get(DOCS)
        http_request.user = user_account
        return self.view(http_request)

    def test_it_lets_an_active_staff_user_through(self):
        user_account = User.objects.create_superuser(
            'jefa', 'jefa@example.com', 'clave-larga-123'
        )

        self.assertEqual(self._request(user_account).status_code, 200)

    def test_it_hides_from_a_deactivated_administrator(self):
        user_account = User.objects.create_superuser(
            'exjefe', 'exjefe@example.com', 'clave-larga-123'
        )
        user_account.is_active = False

        with self.assertRaises(Http404):
            self._request(user_account)

    def test_it_hides_from_a_user_without_is_staff(self):
        user_account = User.objects.create_user(
            'curiosa', 'curiosa@example.com', 'clave-larga-123'
        )

        with self.assertRaises(Http404):
            self._request(user_account)

    def test_it_hides_from_an_anonymous_visitor(self):
        with self.assertRaises(Http404):
            self._request(AnonymousUser())


class AppUserDocsAccessTest(TestCase):
    """
    Un token de la aplicacion no vale aqui.

    Es la comprobacion que justifica el diseño: la documentacion queda detras de
    un juego de credenciales distinto del de los usuarios finales.
    """

    def test_a_bearer_token_does_not_open_the_schema(self):
        # Ni siquiera hace falta que el token sea valido para lo que se prueba:
        # las vistas de la documentacion solo aceptan `SessionAuthentication`, asi
        # que la cabecera `Authorization` no se mira. Un token bueno acabaria
        # igual, y montarlo aqui solo ataria la prueba al emisor de tokens.
        response = self.client.get(SCHEMA, HTTP_AUTHORIZATION='Bearer lo-que-sea')

        self.assertEqual(response.status_code, 404)


class StaffDocsAccessTest(TestCase):
    """Con sesion de superusuario la documentacion funciona entera."""

    def setUp(self):
        User.objects.create_superuser('jefe', 'jefe@example.com', 'clave-larga-123')
        self.client.login(username='jefe', password='clave-larga-123')

    def test_a_superuser_opens_the_swagger_page(self):
        response = self.client.get(DOCS)

        self.assertEqual(response.status_code, 200)

    def test_a_superuser_opens_the_schema(self):
        response = self.client.get(SCHEMA)

        self.assertEqual(response.status_code, 200)
        self.assertIn(b'openapi', response.content)

    def test_the_admin_panel_offers_the_link(self):
        # El enlace de la barra superior (templates/admin/base_site.html). Es la
        # unica via prevista para llegar a la documentacion, asi que si alguien
        # renombra la ruta o el bloque de la plantilla, esto se entera.
        response = self.client.get(reverse('admin:index'))

        self.assertContains(response, f'href="{DOCS}"')
