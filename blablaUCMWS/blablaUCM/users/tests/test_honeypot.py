"""
Pruebas del señuelo de `/admin/` y del calculo de la IP del cliente
"""
from django.contrib.auth.models import User
from django.core import mail
from django.core.cache import cache
from django.test import Client, RequestFactory, SimpleTestCase, TestCase, override_settings

from api.client_ip import get_client_ip

HONEYPOT_URL = '/admin/'

# El correo se queda en memoria y se consulta con `mail.outbox`
IN_MEMORY_EMAIL = dict(
    EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend',
    HONEYPOT_NOTIFY_EMAIL='avisos@example.com',
    HONEYPOT_EMAIL_COOLDOWN=3600,
    HONEYPOT_MAX_EMAILS_HOUR=20,
    HONEYPOT_NOTIFY_ON_GET=False,
)


class ClientIpTest(SimpleTestCase):
    """
    `get_client_ip` con la regla de `NUM_PROXIES`. Sin base de datos.
    """

    def setUp(self):
        self.factory = RequestFactory()

    @override_settings(REST_FRAMEWORK={'NUM_PROXIES': 1})
    def test_takes_the_last_entry_of_forwarded_for(self):
        # La primera entrada la pone el cliente, la ultima el proxy de confianza
        http_request = self.factory.get(
            HONEYPOT_URL,
            HTTP_X_FORWARDED_FOR='1.2.3.4, 203.0.113.7',
            REMOTE_ADDR='10.0.0.5',
        )
        self.assertEqual(get_client_ip(http_request), '203.0.113.7')

    @override_settings(REST_FRAMEWORK={'NUM_PROXIES': 1})
    def test_falls_back_to_remote_addr_without_the_header(self):
        http_request = self.factory.get(HONEYPOT_URL, REMOTE_ADDR='10.0.0.5')
        self.assertEqual(get_client_ip(http_request), '10.0.0.5')

    @override_settings(REST_FRAMEWORK={'NUM_PROXIES': 0})
    def test_without_proxies_it_uses_remote_addr(self):
        http_request = self.factory.get(
            HONEYPOT_URL,
            HTTP_X_FORWARDED_FOR='1.2.3.4',
            REMOTE_ADDR='10.0.0.5',
        )
        self.assertEqual(get_client_ip(http_request), '10.0.0.5')


@override_settings(**IN_MEMORY_EMAIL)
class HoneypotViewTest(TestCase):
    """
    Comportamiento visible del señuelo.
    """

    def setUp(self):
        cache.clear()
        mail.outbox = []
        self.client = Client()

    def test_a_visit_returns_a_login_screen_and_never_a_404(self):
        # Un 404 delataria que ahi no hay panel
        response = self.client.get(HONEYPOT_URL)

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'Administración de Django')
        self.assertContains(response, 'name="username"')

    def test_a_visit_alone_does_not_send_an_email(self):
        self.client.get(HONEYPOT_URL)

        self.assertEqual(len(mail.outbox), 0)

    def test_a_login_attempt_always_fails_and_shows_the_error(self):
        response = self.client.post(
            HONEYPOT_URL, {'username': 'admin', 'password': 'admin'}
        )

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'cuenta de staff')

    def test_a_login_attempt_sends_one_email(self):
        self.client.post(HONEYPOT_URL, {'username': 'admin', 'password': 'admin'},
                         REMOTE_ADDR='198.51.100.9')

        self.assertEqual(len(mail.outbox), 1)
        self.assertIn('198.51.100.9', mail.outbox[0].subject)
        self.assertIn('admin', mail.outbox[0].body)

    def test_the_password_is_never_recorded(self):
        with self.assertLogs('api.honeypot', level='WARNING') as record:
            self.client.post(
                HONEYPOT_URL,
                {'username': 'admin', 'password': 'contraseniaSuperSecreta'},
            )

        registered = '\n'.join(record.output)
        self.assertIn('admin', registered)
        self.assertNotIn('contraseniaSuperSecreta', registered)
        self.assertNotIn('contraseniaSuperSecreta', mail.outbox[0].body)

    def test_the_attempt_is_recorded_even_without_a_csrf_token(self):
        # Sin `csrf_exempt`, el middleware devolveria 403 antes de llegar a la
        # vista y el señuelo no veria a la mayoria de los automatizados
        client = Client(enforce_csrf_checks=True)

        response = client.post(HONEYPOT_URL, {'username': 'root', 'password': 'x'})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(mail.outbox), 1)


@override_settings(**IN_MEMORY_EMAIL)
class EmailRateLimitTest(TestCase):
    """
    Un aviso por IP y hora, mas el tope global.
    """

    def setUp(self):
        cache.clear()
        mail.outbox = []
        self.client = Client()

    def _try(self, ip):
        return self.client.post(
            HONEYPOT_URL, {'username': 'admin', 'password': 'x'}, REMOTE_ADDR=ip
        )

    def test_the_same_ip_only_warns_once(self):
        for _ in range(5):
            self._try('198.51.100.9')

        self.assertEqual(len(mail.outbox), 1)

    def test_a_different_ip_warns_again(self):
        self._try('198.51.100.9')
        self._try('198.51.100.10')

        self.assertEqual(len(mail.outbox), 2)

    @override_settings(HONEYPOT_MAX_EMAILS_HOUR=1)
    def test_the_hourly_cap_stops_a_distributed_scan(self):
        self._try('198.51.100.11')
        self._try('198.51.100.12')

        self.assertEqual(len(mail.outbox), 1)

    @override_settings(HONEYPOT_NOTIFY_EMAIL='')
    def test_without_a_recipient_nothing_is_sent_but_it_still_logs(self):
        with self.assertLogs('api.honeypot', level='WARNING') as record:
            self._try('198.51.100.13')

        self.assertEqual(len(mail.outbox), 0)
        self.assertIn('198.51.100.13', '\n'.join(record.output))

@override_settings(**IN_MEMORY_EMAIL)
class SpoofedIpTest(TestCase):
    """
    La IP no se puede elegir desde fuera.

    daphne arranca con `--proxy-headers` y sustituye `REMOTE_ADDR` por la PRIMERA
    entrada de `X-Forwarded-For`, que la escribe el cliente. Si el señuelo leyera
    ese valor, bastaria con cambiarlo en cada peticion para tener una clave nueva
    y saltarse el limite de avisos.
    """

    def setUp(self):
        cache.clear()
        mail.outbox = []
        self.client = Client()

    @override_settings(REST_FRAMEWORK={'NUM_PROXIES': 1})
    def test_a_forged_forwarded_for_does_not_bypass_the_limit(self):
        for made_up in ('1.1.1.1', '2.2.2.2', '3.3.3.3', '4.4.4.4'):
            self.client.post(
                HONEYPOT_URL,
                {'username': 'admin', 'password': 'x'},
                # La real, la que añade Caddy, es siempre la ultima
                HTTP_X_FORWARDED_FOR=f'{made_up}, 203.0.113.7',
                REMOTE_ADDR=made_up,
            )

        self.assertEqual(len(mail.outbox), 1)
        self.assertIn('203.0.113.7', mail.outbox[0].subject)


class RealAdminTest(TestCase):
    """
    El panel real sigue existiendo, pero en otra ruta.
    """

    def test_the_honeypot_is_not_the_real_admin(self):
        # El señuelo responde 200 con su pantalla, no redirige al login de Django
        response = self.client.get(HONEYPOT_URL)

        self.assertEqual(response.status_code, 200)
        self.assertNotIn('Location', response.headers)

    def test_the_real_admin_answers_on_its_own_route(self):
        from django.conf import settings

        response = self.client.get(f'/{settings.ADMIN_URL}', follow=True)

        # Sin sesion, el panel real redirige a SU login (que si es el de Django)
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'name="username"')

    def test_a_superuser_gets_into_the_real_admin(self):
        from django.conf import settings

        User.objects.create_superuser('jefe', 'jefe@example.com', 'clave-larga-123')
        self.client.login(username='jefe', password='clave-larga-123')

        response = self.client.get(f'/{settings.ADMIN_URL}')

        self.assertEqual(response.status_code, 200)
