"""
Estado de la base de datos y de las migraciones.
Estas pruebas no ejercitan ningun endpoint: comprueban que el esquema es el que el codigo cree que es
"""
from io import StringIO

from django.core.management import call_command
from django.db import connection
from django.test import TestCase

from travels.models import RequestStates, TravelStates
from users.models import Criteria, EnvTypes, PrefTypes, UserType


def db_object_exists(query, name):
    with connection.cursor() as cursor:
        cursor.execute(query, [name])
        return cursor.fetchone() is not None


class MigrationsAreUpToDateTest(TestCase):

    def test_there_are_no_model_changes_without_a_migration(self):
        output = StringIO()

        try:
            call_command(
                'makemigrations', '--check', '--dry-run', stdout=output, stderr=output)
        except SystemExit:
            self.fail(
                "Hay cambios en los modelos sin migracion. Ejecuta "
                "`manage.py makemigrations`:\n" + output.getvalue()
            )

    def test_the_abstract_base_model_does_not_add_a_table(self):
        """
        `BaseModel` es abstracto: Django copia sus campos en cada hijo y no crea
        tabla propia. Si alguien le quitara el `abstract = True`, aparecerian una
        tabla y una migracion nuevas.
        """
        self.assertNotIn('api_basemodel', connection.introspection.table_names())


class SqlObjectsFromMigrationsTest(TestCase):
    """Lo que crean las migraciones `RunSQL` y Django no sabe reconstruir."""

    FUNCTION = "SELECT 1 FROM pg_proc WHERE proname = %s"
    TRIGGER = "SELECT 1 FROM pg_trigger WHERE tgname = %s AND NOT tgisinternal"

    def test_the_periodic_travels_function_exists(self):
        self.assertTrue(db_object_exists(self.FUNCTION, 'create_periodic_travels'))

    def test_the_periodic_travels_trigger_is_installed(self):
        self.assertTrue(db_object_exists(self.TRIGGER, 'trigger_generate_periodic_travels'))

    def test_the_driver_ratings_function_exists(self):
        """La usa `get_travel_details` con un `cursor.execute` directo."""
        self.assertTrue(db_object_exists(self.FUNCTION, 'getdriverratings'))

    def test_the_cascade_soft_delete_trigger_is_installed(self):
        self.assertTrue(db_object_exists(self.TRIGGER, 'trigger_sp_delete_travels'))

    def test_postgis_is_installed(self):
        """
        Sin PostGIS no existen los `PointField` ni `ST_DWithin`, y la busqueda
        geoespacial no es sustituible por SQLite.
        """
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1 FROM pg_extension WHERE extname = 'postgis'")
            self.assertIsNotNone(cursor.fetchone())


class SeedCatalogsTest(TestCase):
    """
    Los catalogos los siembran `users.0010_seed_catalog` y
    `travels.0012_seed_catalog` como *data migrations*, para que no haya ningun
    paso manual de carga en ningun entorno
    """

    def test_the_user_types_are_seeded(self):
        self.assertTrue(UserType.objects.filter(code='std').exists())

    def test_the_travel_states_are_seeded(self):
        for code in ('active', 'started', 'fnd'):
            with self.subTest(code=code):
                self.assertTrue(TravelStates.objects.filter(code=code).exists())

    def test_the_request_states_are_seeded(self):
        for code in ('pending', 'accepted', 'validated', 'unvalidated'):
            with self.subTest(code=code):
                self.assertTrue(RequestStates.objects.filter(code=code).exists())

    def test_the_remaining_catalogs_are_seeded(self):
        self.assertTrue(EnvTypes.objects.exists())
        self.assertTrue(PrefTypes.objects.exists())
        self.assertTrue(Criteria.objects.exists())
