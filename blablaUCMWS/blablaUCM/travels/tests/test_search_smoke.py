"""
Pruebas de HUMO de la busqueda de viajes.
    POST /api/v1/travel/search-travels/
"""
from rest_framework import status
from rest_framework.test import APITestCase

from travels.models import UsersDenied
from travels.tests.factories import create_travel, create_user
from users.models import Preferences


class SearchSmokeTest(APITestCase):

    def setUp(self):
        self.searcher = create_user("searcher")
        self.driver = create_user("driver")
        self.client.force_authenticate(user=self.searcher)

    def search(self, **filters):
        return self.client.post("/api/v1/travel/search-travels/", filters, format='json')

    def result_ids(self, response):
        return {t['id_travel'] for t in response.data['data']}

    def test_returns_active_travels_from_other_users(self):
        travel = create_travel(self.driver, num_seats=3, remaining_seats=3)

        response = self.search()

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['status'], 'ok')
        self.assertIn(str(travel.pk), self.result_ids(response))

    def test_excludes_own_travels(self):
        own_travel = create_travel(self.searcher, num_seats=3, remaining_seats=3)
        other_travel = create_travel(self.driver, num_seats=3, remaining_seats=3)

        response = self.search()

        found = self.result_ids(response)
        self.assertNotIn(str(own_travel.pk), found)
        self.assertIn(str(other_travel.pk), found)

    def test_excludes_travels_without_seats(self):
        full_travel = create_travel(self.driver, num_seats=3, remaining_seats=0)
        travel_with_room = create_travel(self.driver, num_seats=3, remaining_seats=1)

        response = self.search()

        found = self.result_ids(response)
        self.assertNotIn(str(full_travel.pk), found)
        self.assertIn(str(travel_with_room.pk), found)

    def test_excludes_travels_that_are_not_active(self):
        finished_travel = create_travel(self.driver, num_seats=3, remaining_seats=3, state='fnd')
        active_travel = create_travel(self.driver, num_seats=3, remaining_seats=3)

        response = self.search()

        found = self.result_ids(response)
        self.assertNotIn(str(finished_travel.pk), found)
        self.assertIn(str(active_travel.pk), found)

    def test_excludes_travels_that_deny_my_user_type(self):
        blocked_travel = create_travel(self.driver, num_seats=3, remaining_seats=3)
        UsersDenied.objects.create(id_travel=blocked_travel, user_type=self.searcher.user_type)
        open_travel = create_travel(self.driver, num_seats=3, remaining_seats=3)

        response = self.search()

        found = self.result_ids(response)
        self.assertNotIn(str(blocked_travel.pk), found)
        self.assertIn(str(open_travel.pk), found)

    def test_paginates_ten_by_ten(self):
        for _ in range(12):
            create_travel(self.driver, num_seats=3, remaining_seats=3)

        first_page = self.search(page=1)
        second_page = self.search(page=2)

        self.assertEqual(len(first_page.data['data']), 10)
        self.assertTrue(first_page.data['has_next'])
        self.assertEqual(len(second_page.data['data']), 2)
        self.assertFalse(second_page.data['has_next'])

    def test_filters_by_punctual_travel_type(self):
        punctual_travel = create_travel(self.driver, num_seats=3, remaining_seats=3)

        response = self.search(travel_type='punctual')

        self.assertIn(str(punctual_travel.pk), self.result_ids(response))

    def test_filtering_by_preferences_no_longer_returns_500(self):
       
        create_travel(self.driver, num_seats=3, remaining_seats=3)

        response = self.search(preferences=['alwaysWithMusic'])

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_search_without_filters_does_not_break(self):
        # El caso degenerado: sin viajes y sin filtros debe devolver lista vacia
        response = self.search()

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['data'], [])
        self.assertFalse(response.data['has_next'])


class PreferencesFilterTest(APITestCase):

    def setUp(self):
        self.searcher = create_user("searcher")
        self.client.force_authenticate(user=self.searcher)

    def driver_with(self, username, *pref_codes):
        driver = create_user(username)
        for code in pref_codes:
            Preferences.objects.create(id_user=driver, pref_type_id=code)
        return driver

    def search(self, **filters):
        return self.client.post("/api/v1/travel/search-travels/", filters, format='json')

    def result_ids(self, response):
        return {t['id_travel'] for t in response.data['data']}

    def test_it_finds_the_driver_that_has_the_preference(self):
        with_music = create_travel(
            self.driver_with("melomano", 'alwaysWithMusic'), num_seats=3, remaining_seats=3)
        without_music = create_travel(
            self.driver_with("silencioso", 'loveSilence'), num_seats=3, remaining_seats=3)

        response = self.search(preferences=['alwaysWithMusic'])

        found = self.result_ids(response)
        self.assertIn(str(with_music.pk), found)
        self.assertNotIn(str(without_music.pk), found)

    def test_a_driver_without_any_preference_is_left_out(self):
        """
        Contrapartida: sin esta prueba, un filtro que no filtrase nada tambien
        pasaria la anterior.
        """
        create_travel(self.driver_with("indiferente"), num_seats=3, remaining_seats=3)

        response = self.search(preferences=['alwaysWithMusic'])

        self.assertEqual(self.result_ids(response), set())

    def test_marking_two_preferences_requires_both(self):
        """La decision de diseño, ejecutada."""
        both = create_travel(
            self.driver_with("completo", 'alwaysWithMusic', 'noAnimals'),
            num_seats=3, remaining_seats=3)
        only_one = create_travel(
            self.driver_with("parcial", 'alwaysWithMusic'), num_seats=3, remaining_seats=3)

        response = self.search(preferences=['alwaysWithMusic', 'noAnimals'])

        found = self.result_ids(response)
        self.assertIn(str(both.pk), found)
        self.assertNotIn(str(only_one.pk), found)

    def test_extra_preferences_of_the_driver_do_not_get_in_the_way(self):
        """
        Que las tenga TODAS no significa que tenga SOLO esas. Es el fallo tipico
        del truco del Count: contar de mas y dejar fuera al conductor completo.
        """
        travel = create_travel(
            self.driver_with("variado", 'alwaysWithMusic', 'noAnimals', 'loveToChat'),
            num_seats=3, remaining_seats=3)

        response = self.search(preferences=['alwaysWithMusic'])

        self.assertIn(str(travel.pk), self.result_ids(response))

    def test_a_removed_preference_no_longer_counts(self):
        """
        Las preferencias se quitan con borrado logico, asi que la fila
        sigue en la tabla. Si el filtro no lo tuviera en cuenta, encontraria
        conductores por preferencias que ya se habian quitado.
        """
        driver = self.driver_with("arrepentido", 'alwaysWithMusic')
        Preferences.objects.filter(id_user=driver).update(is_deleted=True)
        create_travel(driver, num_seats=3, remaining_seats=3)

        response = self.search(preferences=['alwaysWithMusic'])

        self.assertEqual(self.result_ids(response), set())

    def test_repeating_a_preference_does_not_break_the_count(self):
        """
        Si el cliente manda la misma casilla dos veces, exigir `len(preferences)`
        coincidencias dejaria fuera al conductor que si la tiene. Por eso el
        recuento va sobre el conjunto y no sobre la lista.
        """
        travel = create_travel(
            self.driver_with("melomano", 'alwaysWithMusic'), num_seats=3, remaining_seats=3)

        response = self.search(preferences=['alwaysWithMusic', 'alwaysWithMusic'])

        self.assertIn(str(travel.pk), self.result_ids(response))

    def test_an_unknown_preference_returns_nothing_instead_of_failing(self):
        create_travel(self.driver_with("cualquiera", 'alwaysWithMusic'), num_seats=3, remaining_seats=3)

        response = self.search(preferences=['noExisteEstaPreferencia'])

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.result_ids(response), set())
