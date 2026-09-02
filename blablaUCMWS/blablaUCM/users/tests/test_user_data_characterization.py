"""
Pruebas de CARACTERIZACION de los datos asociados al usuario
    GET    /api/v1/users/{id}/vehicles/
    GET    /api/v1/users/{id}/notifications/
    GET    /api/v1/users/{id}/notifications/unread-count/
    GET    /api/v1/users/{id}/driverratings/
    GET    /api/v1/users/{id}/preferences/
    PATCH  /api/v1/users/{id}/update-preferences/
    DELETE /api/v1/users/{id}/clear-preferences/
"""
from rest_framework import status
from rest_framework.test import APITestCase

from travels.tests.factories import create_user, create_vehicle
from users.models import Criteria, DriverRatings, Notifications, Preferences, PrefTypes


class BaseUserDataTest(APITestCase):

    def setUp(self):
        self.user = create_user("owner")
        self.client.force_authenticate(user=self.user)

    def get(self, path, user_id=None):
        return self.client.get(f"/api/v1/users/{user_id or self.user.id}/{path}")


class UserVehiclesTest(BaseUserDataTest):

    def test_returns_the_user_vehicles_paginated(self):
        create_vehicle(self.user)
        create_vehicle(self.user)

        response = self.get("vehicles/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['count'], 2)

    def test_excludes_deleted_vehicles(self):
        vehicle = create_vehicle(self.user)
        vehicle.is_deleted = True
        vehicle.save()

        response = self.get("vehicles/")

        self.assertEqual(response.data['count'], 0)

    def test_does_not_mix_vehicles_from_other_users(self):
        other = create_user("other")
        create_vehicle(other)
        create_vehicle(self.user)

        response = self.get("vehicles/")

        self.assertEqual(response.data['count'], 1)

class UserNotificationsTest(BaseUserDataTest):

    def add_notification(self, content, read=False, user=None):
        return Notifications.objects.create(
            id_user=user or self.user, content=content, read=read
        )

    def test_returns_notifications_newest_first_by_default(self):
        self.add_notification("primera")
        self.add_notification("segunda")

        response = self.get("notifications/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        contents = [n['content'] for n in response.data['results']]
        self.assertEqual(contents, ["segunda", "primera"])

    def test_ordering_asc_reverses_the_order(self):
        self.add_notification("primera")
        self.add_notification("segunda")

        response = self.get("notifications/?ordering=asc")

        contents = [n['content'] for n in response.data['results']]
        self.assertEqual(contents, ["primera", "segunda"])

    def test_excludes_deleted_notifications(self):
        notification = self.add_notification("borrada")
        notification.is_deleted = True
        notification.save()

        response = self.get("notifications/")

        self.assertEqual(response.data['count'], 0)

    def test_unread_count_only_counts_unread_and_not_deleted(self):
        self.add_notification("sin leer")
        self.add_notification("leida", read=True)
        deleted = self.add_notification("borrada")
        deleted.is_deleted = True
        deleted.save()

        response = self.get("notifications/unread-count/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['count'], 1)

    def test_unread_count_is_zero_without_notifications(self):
        response = self.get("notifications/unread-count/")

        self.assertEqual(response.data['count'], 0)


class UserDriverRatingsTest(BaseUserDataTest):
    """
    Estas valoraciones se calculan con el procedimiento almacenado
    `getdriverratings` (migracion users.0002), no con el ORM. Por eso estas
    pruebas comprueban tambien que el procedimiento existe en la BBDD de test.
    """

    def add_rating(self, criteria_code, score, rater=None):
        return DriverRatings.objects.create(
            id_user=rater or create_user(),
            id_driver=self.user,
            criteria=Criteria.objects.get(code=criteria_code),
            score=score,
        )

    def test_without_ratings_returns_the_empty_shape(self):
        response = self.get("driverratings/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['results'], {"none": 0})
        self.assertEqual(response.data['count'], 0)

    def test_averages_the_scores_per_criteria(self):
        self.add_rating('punctuality', 8)
        self.add_rating('punctuality', 6)

        response = self.get("driverratings/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['results']['punctuality'], 7.0)
        self.assertEqual(response.data['count'], 2.0)

    def test_reports_each_criteria_separately(self):
        self.add_rating('punctuality', 10)
        self.add_rating('kindness', 4)

        response = self.get("driverratings/")

        self.assertEqual(response.data['results']['punctuality'], 10.0)
        self.assertEqual(response.data['results']['kindness'], 4.0)


class UserPreferencesTest(BaseUserDataTest):

    def preference_codes(self):
        """
        Solo las activas: las que se quitan se marcan como 
        borradas en vez de desaparecer de la tabla.
        """
        return set(
            Preferences.objects.filter(id_user=self.user, is_deleted=False)
            .values_list('pref_type', flat=True)
        )

    def available_codes(self, how_many=2):
        return list(
            PrefTypes.objects.filter(is_deleted=False).values_list('code', flat=True)[:how_many]
        )

    def test_returns_the_user_preferences(self):
        codes = self.available_codes()
        for code in codes:
            Preferences.objects.create(id_user=self.user, pref_type=PrefTypes.objects.get(code=code))

        response = self.get("preferences/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['count'], len(codes))

    def test_update_replaces_the_previous_preferences(self):
        codes = self.available_codes(2)
        Preferences.objects.create(id_user=self.user, pref_type=PrefTypes.objects.get(code=codes[0]))

        response = self.client.patch(
            f"/api/v1/users/{self.user.id}/update-preferences/",
            {'preferences': [codes[1]]},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.preference_codes(), {codes[1]})

    def test_update_ignores_unknown_codes(self):
        codes = self.available_codes(1)

        response = self.client.patch(
            f"/api/v1/users/{self.user.id}/update-preferences/",
            {'preferences': [codes[0], 'NO_EXISTE']},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.preference_codes(), {codes[0]})

    def test_update_with_an_empty_list_clears_them(self):
        codes = self.available_codes(1)
        Preferences.objects.create(id_user=self.user, pref_type=PrefTypes.objects.get(code=codes[0]))

        self.client.patch(
            f"/api/v1/users/{self.user.id}/update-preferences/",
            {'preferences': []},
            format='json',
        )

        self.assertEqual(self.preference_codes(), set())

    def test_update_soft_deletes_the_old_rows(self):
        """
        Antes se hacia un borrado DURO (`Preferences.objects.filter(...).delete()`),
        mientras que el resto del proyecto usa borrado logico. Ahora la fila que
        se quita se marca como borrada y sigue en la tabla.
        """
        codes = self.available_codes(2)
        Preferences.objects.create(id_user=self.user, pref_type=PrefTypes.objects.get(code=codes[0]))

        self.client.patch(
            f"/api/v1/users/{self.user.id}/update-preferences/",
            {'preferences': [codes[1]]},
            format='json',
        )

        # La fila antigua sigue existiendo, marcada como borrada
        self.assertEqual(Preferences.objects.filter(id_user=self.user).count(), 2)
        self.assertTrue(
            Preferences.objects.get(id_user=self.user, pref_type=codes[0]).is_deleted
        )
        self.assertEqual(self.preference_codes(), {codes[1]})

    def test_update_revives_a_preference_instead_of_duplicating_it(self):
        """
        El borrado logico en una tabla de union acumula filas muertas si no se
        reutilizan: al volver a marcar una preferencia que ya se habia quitado,
        se revive la fila existente en lugar de crear otra.
        """
        codes = self.available_codes(1)
        url = f"/api/v1/users/{self.user.id}/update-preferences/"

        self.client.patch(url, {'preferences': [codes[0]]}, format='json')
        self.client.patch(url, {'preferences': []}, format='json')
        self.client.patch(url, {'preferences': [codes[0]]}, format='json')

        # Tres cambios, una sola fila
        self.assertEqual(Preferences.objects.filter(id_user=self.user).count(), 1)
        self.assertEqual(self.preference_codes(), {codes[0]})

    def test_clear_preferences_removes_them(self):
        """
        Llamaba a `user.preferences.clear()`, pero `preferences` es el manager
        inverso de una ForeignKey NO nulable: Django solo expone `clear()` si el
        campo admite null. Lanzaba AttributeError, y el endpoint no tenia ningun
        try/except que lo recogiera, asi que nunca llego a funcionar.
        """
        codes = self.available_codes(1)
        Preferences.objects.create(id_user=self.user, pref_type=PrefTypes.objects.get(code=codes[0]))

        response = self.client.delete(f"/api/v1/users/{self.user.id}/clear-preferences/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.preference_codes(), set())

        # Borrado logico: la fila sigue ahi, marcada
        self.assertEqual(Preferences.objects.filter(id_user=self.user).count(), 1)

    def test_clear_preferences_on_a_user_without_any_works(self):
        response = self.client.delete(f"/api/v1/users/{self.user.id}/clear-preferences/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
