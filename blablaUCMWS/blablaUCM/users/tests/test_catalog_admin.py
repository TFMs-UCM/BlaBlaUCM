"""
Pruebas del panel de administracion de los catalogos
"""
from django.contrib import admin
from django.contrib.auth.models import User
from django.test import RequestFactory, TestCase
from django.urls import reverse

from travels.models import RequestStates, TravelStates
from users.models import Criteria, EnvTypes, PrefTypes, UserType

CATALOGS = [UserType, PrefTypes, Criteria, EnvTypes, TravelStates, RequestStates]


class CatalogRegistrationTest(TestCase):
    """
    Los seis catalogos estan en el panel, y nada mas del dominio.
    """

    def test_the_six_catalogs_are_registered(self):
        for model in CATALOGS:
            with self.subTest(model=model.__name__):
                self.assertIn(model, admin.site._registry)

    def test_the_domain_models_are_not_registered(self):
        # Registrarlos daria acceso a datos personales y saltaria la capa de servicios
        from travels.models import RequestTravels, Travel
        from users.models import Users, Vehicles

        for model in (Users, Vehicles, Travel, RequestTravels):
            with self.subTest(model=model.__name__):
                self.assertNotIn(model, admin.site._registry)


class CatalogDeletionTest(TestCase):
    """
    El panel no borra de verdad.
    """
    def setUp(self):
        self.factory = RequestFactory()

    def test_the_admin_cannot_hard_delete_a_catalog(self):
        for model in CATALOGS:
            with self.subTest(model=model.__name__):
                panel = admin.site._registry[model]
                http_request = self.factory.get('/')

                self.assertFalse(panel.has_delete_permission(http_request))

    def test_marking_it_deleted_fills_in_the_date(self):
        state_row = TravelStates.objects.create(code='tmp', description='Temporal')
        panel = admin.site._registry[TravelStates]

        state_row.is_deleted = True
        panel.save_model(self.factory.get('/'), state_row, None, change=True)

        state_row.refresh_from_db()
        self.assertTrue(state_row.is_deleted)
        self.assertIsNotNone(state_row.deleted_at)

    def test_unmarking_it_clears_the_date(self):
        state_row = TravelStates.objects.create(code='tmp2', description='Temporal')
        panel = admin.site._registry[TravelStates]

        state_row.is_deleted = True
        panel.save_model(self.factory.get('/'), state_row, None, change=True)

        state_row.is_deleted = False
        panel.save_model(self.factory.get('/'), state_row, None, change=True)

        state_row.refresh_from_db()
        self.assertFalse(state_row.is_deleted)
        self.assertIsNone(state_row.deleted_at)


class CatalogAccessTest(TestCase):
    """
    Solo entra un superusuario de Django, que es una poblacion distinta de los
    usuarios de la aplicacion.
    """

    def setUp(self):
        self.superuser = User.objects.create_superuser(
            'jefe', 'jefe@example.com', 'clave-larga-123'
        )

    def test_a_superuser_sees_the_catalog_list(self):
        self.client.login(username='jefe', password='clave-larga-123')

        response = self.client.get(reverse('admin:users_usertype_changelist'))

        self.assertEqual(response.status_code, 200)

    def test_without_a_session_it_redirects_to_the_login(self):
        response = self.client.get(reverse('admin:users_usertype_changelist'))

        self.assertEqual(response.status_code, 302)

    def test_a_superuser_can_create_a_catalog_entry(self):
        self.client.login(username='jefe', password='clave-larga-123')

        response = self.client.post(
            reverse('admin:users_usertype_add'),
            {'code': 'PAS', 'name': 'Personal de administracion'},
        )

        self.assertEqual(response.status_code, 302)
        self.assertTrue(UserType.objects.filter(code='PAS').exists())
