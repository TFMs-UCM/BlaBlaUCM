"""
Pruebas de los filtros no geográficos de la busqueda de viajes.
    TravelService.search_travels  -> fechas, roles denegados, distintivo
                                     ambiental, tipo de viaje y ordenacion
"""
from datetime import datetime, timedelta, timezone as dt_timezone

from django.test import TestCase

from travels.models import Travel, UsersDenied
from travels.services.travel_service import TravelService
from travels.tests.factories import (
    create_periodic_travel,
    create_travel,
    create_user,
)
from users.models import UserType


# Fecha de referencia de las pruebas de fechas
SEPT_15 = datetime(2026, 9, 15, 8, 0, tzinfo=dt_timezone.utc)


class BaseFilterSearchTest(TestCase):

    def setUp(self):
        self.driver = create_user("driver")
        self.searcher = create_user("searcher")

    def search(self, **data):
        """Lanza la busqueda con el queryset base que usa el view."""
        queryset = Travel.objects.filter(is_deleted=False)
        return list(TravelService.search_travels(queryset, self.searcher, data))


class DateFromFilterTest(BaseFilterSearchTest):

    def setUp(self):
        super().setUp()
        self.before = create_travel(self.driver, travel_date=SEPT_15 - timedelta(days=5))
        self.after = create_travel(self.driver, travel_date=SEPT_15 + timedelta(days=5))

    def test_a_travel_before_the_starting_date_is_left_out(self):
        found_travels = self.search(date_from='2026-09-15T08:00:00')

        self.assertEqual(found_travels, [self.after])

    def test_the_starting_date_is_inclusive(self):
        """
        El filtro es `gte`, no `gt`: un viaje que sale exactamente a la hora
        pedida cuenta. Es el limite en el que se equivoca casi siempre.
        """
        exact_edge = create_travel(self.driver, travel_date=SEPT_15)

        found_travels = self.search(date_from='2026-09-15T08:00:00')

        self.assertIn(exact_edge, found_travels)

    def test_a_date_without_a_time_is_accepted_as_midnight(self):
        """
        La app manda 'YYYY-MM-DD' a secas. `parse_datetime` lo acepta como ISO y
        lo interpreta como las 00:00, asi que el dia entero entra.
        """
        found_travels = self.search(date_from='2026-09-15')

        self.assertEqual(found_travels, [self.after])

    def test_a_naive_date_is_made_aware_instead_of_breaking(self):
        """
        Sin el `make_aware`, comparar una fecha sin zona con `travel_date` (que
        si la tiene) avisaria con un RuntimeWarning y compararia en UTC por su
        cuenta. Aqui se comprueba que la rama existe y filtra bien.
        """
        found_travels = self.search(date_from='2026-09-18T00:00:00')

        self.assertEqual(found_travels, [self.after])

    def test_a_date_with_an_offset_keeps_its_own_timezone(self):
        """
        La otra rama del `is_naive`: si la cadena trae desfase, se respeta tal
        cual. '2026-09-20T12:00:00+02:00' son las 10:00 UTC, asi que un viaje de
        las 11:00 UTC de ese mismo dia entra y uno de las 09:00 no.
        """
        early_travel = create_travel(
            self.driver, travel_date=datetime(2026, 9, 20, 9, 0, tzinfo=dt_timezone.utc))
        late = create_travel(
            self.driver, travel_date=datetime(2026, 9, 20, 11, 0, tzinfo=dt_timezone.utc))

        found_travels = self.search(date_from='2026-09-20T12:00:00+02:00')

        self.assertIn(late, found_travels)
        self.assertNotIn(early_travel, found_travels)

    def test_an_unparseable_starting_date_is_silently_ignored(self):
        """
        `parse_datetime('manana')` devuelve None y el filtro se salta entero: la
        busqueda responde 200 con todos los viajes, no con un error.
        """
        found_travels = self.search(date_from='manana')

        self.assertCountEqual(found_travels, [self.before, self.after])


class DateUntilFilterTest(BaseFilterSearchTest):
    """
    `date_until` -> `travel_date__lt`, sobre la fecha pedida mas un dia

    Ese +1 es lo que hace que el limite sea inclusivo: quien busca "hasta el 15"
    espera que le salgan los viajes del 15, no los del 15 antes de las 00:00.
    """

    def setUp(self):
        super().setUp()
        self.that_day = create_travel(
            self.driver, travel_date=datetime(2026, 9, 15, 23, 30, tzinfo=dt_timezone.utc))
        self.next_day = create_travel(
            self.driver, travel_date=datetime(2026, 9, 16, 0, 30, tzinfo=dt_timezone.utc))

    def test_the_last_day_is_included_whole(self):
        """Un viaje a las 23:30 del dia pedido entra: es para lo que esta el +1 dia."""
        found_travels = self.search(date_until='2026-09-15')

        self.assertEqual(found_travels, [self.that_day])

    def test_the_next_day_is_left_out(self):
        """Y una hora despues, ya no. El corte cae en la medianoche siguiente."""
        found_travels = self.search(date_until='2026-09-15')

        self.assertNotIn(self.next_day, found_travels)

    def test_only_the_date_part_of_the_string_is_used(self):
        """
        El codigo corta la cadena por `[:10]`, asi que la hora que mande el
        cliente se ignora. Pidiendo 'hasta el 15 a las 06:00' sigue saliendo el
        viaje de las 23:30 de ese dia.
        """
        found_travels = self.search(date_until='2026-09-15T06:00:00')

        self.assertEqual(found_travels, [self.that_day])

    def test_both_dates_together_bound_the_range(self):
        """Las dos a la vez, que es como las manda el buscador de la app."""
        out_below = create_travel(
            self.driver, travel_date=datetime(2026, 9, 10, 8, 0, tzinfo=dt_timezone.utc))

        found_travels = self.search(date_from='2026-09-14', date_until='2026-09-15')

        self.assertEqual(found_travels, [self.that_day])
        self.assertNotIn(out_below, found_travels)


class BlockedForMeTest(BaseFilterSearchTest):
    """
    La anotacion `is_blocked_for_me`: un viaje que deniega MI tipo de usuario no
    me sale en la busqueda.

    Que el bloqueo funciona ya lo comprueba `test_search_smoke.py`. Aqui se
    cubren las dos ramas que quedaban fuera: el `is_deleted=False` del subquery y
    que el bloqueo sea por tipo y no general.
    """

    def test_a_removed_block_no_longer_hides_the_travel(self):
        """
        Los bloqueos se quitan con borrado logico, asi que la fila sigue en la
        tabla. Sin el `is_deleted=False` del `Exists`, un viaje al que le
        quitaron la restriccion seguiria invisible para siempre.
        """
        travel = create_travel(self.driver)
        UsersDenied.objects.create(
            id_travel=travel, user_type=self.searcher.user_type, is_deleted=True)

        self.assertEqual(self.search(), [travel])

    def test_a_block_for_another_user_type_does_not_affect_me(self):
        """El buscador es 'std'; el viaje solo deniega a los profesores."""
        travel = create_travel(self.driver)
        UsersDenied.objects.create(
            id_travel=travel, user_type=UserType.objects.get(code='prof'))

        self.assertEqual(self.search(), [travel])


class UsersDenyFilterTest(BaseFilterSearchTest):
    """
    El filtro `users_deny`, que es el mas raro de la consulta y por eso el que
    mas falta hacia probar.

    NO significa "escondeme los viajes de esa gente". Significa **"quiero viajes
    que denieguen a esos tipos de usuario"**, y hace dos cosas a la vez:

      1. excluye los viajes creados por alguien de esos tipos, y
      2. exige que el viaje tenga un bloqueo activo para **cada** codigo pedido.

    Es lo que usa quien quiere viajar solo con gente de su grupo. La semantica
    con varios codigos es Y, no O —igual que el filtro de preferencias—, y es una
    decision, no una consecuencia: se deja escrita aqui porque no se deduce
    leyendo el `__in`.
    """

    def setUp(self):
        super().setUp()
        self.teacher_type = UserType.objects.get(code='prof')
        self.staff = UserType.objects.get(code='unStf')

    def deny(self, travel, user_type, is_deleted=False):
        return UsersDenied.objects.create(
            id_travel=travel, user_type=user_type, is_deleted=is_deleted)

    def test_it_only_returns_travels_that_deny_the_requested_type(self):
        with_deny = create_travel(self.driver)
        self.deny(with_deny, self.teacher_type)
        create_travel(self.driver)   # abierto a todo el mundo

        found_travels = self.search(users_deny=['prof'])

        self.assertEqual(found_travels, [with_deny])

    def test_a_travel_created_by_a_denied_user_type_is_excluded(self):
        """
        Un profesor que deniega a los profesores en su propio viaje no vale: la
        peticion es "no quiero coincidir con profesores", y el conductor tambien
        cuenta. De ahi el `exclude(creation_user__user_type__code__in=...)`, que
        es facil de perder de vista porque el otro filtro parece bastar.
        """
        teacher = create_user("profesor", user_type='prof')
        of_the_teacher = create_travel(teacher)
        self.deny(of_the_teacher, self.teacher_type)

        found_travels = self.search(users_deny=['prof'])

        self.assertEqual(found_travels, [])

    def test_asking_for_two_types_requires_both(self):
        """La semantica Y, ejecutada: cumplir uno de los dos no basta."""
        both = create_travel(self.driver)
        self.deny(both, self.teacher_type)
        self.deny(both, self.staff)

        only_one = create_travel(self.driver)
        self.deny(only_one, self.teacher_type)

        found_travels = self.search(users_deny=['prof', 'unStf'])

        self.assertEqual(found_travels, [both])

    def test_a_removed_deny_does_not_count(self):
        """
        Mismo borrado logico que en `BlockedForMeTest`, pero por el otro lado de
        la consulta: un veto retirado no puede seguir haciendo que el viaje
        aparezca como restringido.
        """
        travel = create_travel(self.driver)
        self.deny(travel, self.teacher_type, is_deleted=True)

        found_travels = self.search(users_deny=['prof'])

        self.assertEqual(found_travels, [])

    def test_repeating_a_type_does_not_break_the_count(self):
        """
        El recuento comparaba con `len(users_deny)` en vez de con el del
        conjunto: si el cliente mandaba el mismo tipo dos veces —una casilla
        marcada dos veces, un envio duplicado—, el `Count(distinct=True)` valia 1,
        el `len` valia 2 y la busqueda devolvia cero resultados sin error
        """
        travel = create_travel(self.driver)
        self.deny(travel, self.teacher_type)

        found_travels = self.search(users_deny=['prof', 'prof'])

        self.assertEqual(found_travels, [travel])

    def test_an_extra_deny_of_the_travel_does_not_get_in_the_way(self):
        """
        Que tenga TODOS los pedidos no significa que tenga SOLO esos. Es el fallo
        tipico del truco del Count: contar de mas y dejar fuera al viaje que si
        cumple.
        """
        travel = create_travel(self.driver)
        self.deny(travel, self.teacher_type)
        self.deny(travel, self.staff)

        found_travels = self.search(users_deny=['prof'])

        self.assertEqual(found_travels, [travel])


class EnvStickerFilterTest(BaseFilterSearchTest):

    def test_it_only_returns_vehicles_with_that_sticker(self):
        echo = create_travel(self.driver, env_sticker='eco')
        create_travel(self.driver, env_sticker='b')

        found_travels = self.search(env_sticker='eco')

        self.assertEqual(found_travels, [echo])

    def test_the_value_all_does_not_filter(self):
        """
        'all' es un codigo real de EnvTypes (la etiqueta ' - '), asi que sin el
        `!= 'all'` la busqueda por defecto de la app no devolveria nada.
        """
        echo = create_travel(self.driver, env_sticker='eco')
        zero = create_travel(self.driver, env_sticker='cero')

        self.assertCountEqual(self.search(env_sticker='all'), [echo, zero])

    def test_without_the_field_nothing_is_filtered(self):
        echo = create_travel(self.driver, env_sticker='eco')
        zero = create_travel(self.driver, env_sticker='cero')

        self.assertCountEqual(self.search(), [echo, zero])


class TravelTypeFilterTest(BaseFilterSearchTest):
    """
    `travel_type` -> `is_periodic`.
    """

    def setUp(self):
        super().setUp()
        self.punctual = create_travel(self.driver)
        self.periodic = create_periodic_travel(self.driver, weeks=1)

    def test_periodic_only_returns_the_series(self):
        found_travels = self.search(travel_type='periodic')

        self.assertIn(self.periodic, found_travels)
        self.assertNotIn(self.punctual, found_travels)
        self.assertTrue(all(t.is_periodic for t in found_travels))

    def test_punctual_only_returns_the_one_off_travels(self):
        found_travels = self.search(travel_type='punctual')

        self.assertEqual(found_travels, [self.punctual])

    def test_the_value_all_returns_both(self):
        found_travels = self.search(travel_type='all')

        self.assertIn(self.punctual, found_travels)
        self.assertIn(self.periodic, found_travels)

    def test_an_unknown_type_does_not_filter(self):
        """
        El `if` solo conoce 'periodic' y 'punctual': cualquier otra cosa cae sin
        aplicar filtro, en vez de dejar la busqueda vacia.
        """
        found_travels = self.search(travel_type='loQueSea')

        self.assertIn(self.punctual, found_travels)
        self.assertIn(self.periodic, found_travels)


class SortingTest(BaseFilterSearchTest):
    """
    Las ramas de `sort_by` que no dependen de la geografia. Las dos por distancia
    estan en `test_search_geo.py`, que es donde hay coordenadas que ordenar.
    """

    def setUp(self):
        super().setUp()
        self.early = create_travel(self.driver, travel_date=SEPT_15)
        self.late = create_travel(self.driver, travel_date=SEPT_15 + timedelta(days=10))

    def test_late_sorts_from_the_furthest_date(self):
        self.assertEqual(self.search(sort_by='late'), [self.late, self.early])

    def test_the_default_is_the_closest_date_first(self):
        self.assertEqual(self.search(), [self.early, self.late])

    def test_sorting_by_destination_is_ignored_without_a_destination(self):
        """
        Sin coordenada de destino no existe la anotacion `dist_dest`. Sin el
        `and has_dest` la consulta reventaria al ordenar por un campo que no esta
        en el SELECT; con el, cae al orden por fecha.
        """
        self.assertEqual(self.search(sort_by='destination'), [self.early, self.late])

    def test_an_unknown_sort_falls_back_to_the_default(self):
        self.assertEqual(self.search(sort_by='loQueSea'), [self.early, self.late])
