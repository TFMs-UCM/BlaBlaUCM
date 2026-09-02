"""
Pruebas de REGRESION DE SEGURIDAD sobre la separacion de datos entre usuarios.
"""
from rest_framework import status
from rest_framework.test import APITestCase

from travels.tests.factories import create_travel, create_user, create_vehicle
from users.models import Device, DriverRatings, Criteria, Notifications, Preferences, PrefTypes


class BaseOwnershipTest(APITestCase):

    def setUp(self):
        self.victim = create_user("victim")
        self.attacker = create_user("attacker")
        self.client.force_authenticate(user=self.attacker)


class NotificationsExposureTest(BaseOwnershipTest):

    def setUp(self):
        super().setUp()
        self.notification = Notifications.objects.create(
            id_user=self.victim, content="Contenido privado de la victima"
        )

    def test_the_list_only_returns_the_callers_notifications(self):
        Notifications.objects.create(id_user=self.attacker, content="La mia")

        response = self.client.get("/api/v1/notifications/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        contents = [n['content'] for n in response.data['results']]
        self.assertEqual(contents, ["La mia"])

    def test_another_users_notification_cannot_be_read(self):
        response = self.client.get(f"/api/v1/notifications/{self.notification.pk}/")

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_another_users_notification_cannot_be_modified(self):
        response = self.client.patch(
            f"/api/v1/notifications/{self.notification.pk}/", {'read': True}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.notification.refresh_from_db()
        self.assertFalse(self.notification.read)

    def test_another_users_notification_cannot_be_deleted(self):
        response = self.client.delete(f"/api/v1/notifications/{self.notification.pk}/")

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.notification.refresh_from_db()
        self.assertFalse(self.notification.is_deleted)

    def test_the_caller_can_still_mark_their_own_as_read(self):
        """
        Contraparte imprescindible: el filtro no puede haber roto el uso normal.
        La app marca las notificaciones como leidas por este endpoint.
        """
        own = Notifications.objects.create(id_user=self.attacker, content="La mia")

        response = self.client.patch(
            f"/api/v1/notifications/{own.pk}/", {'read': True}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        own.refresh_from_db()
        self.assertTrue(own.read)


class VehiclesExposureTest(BaseOwnershipTest):

    def test_the_list_only_returns_the_callers_vehicles(self):
        create_vehicle(self.victim)
        own = create_vehicle(self.attacker)

        response = self.client.get("/api/v1/vehicles/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        plates = [v['license_plate'] for v in response.data['results']]
        self.assertEqual(plates, [own.license_plate])

    def test_deleting_another_users_vehicle_is_blocked(self):
        """
        `destroy` ya comprobaba el dueño a mano y devolvia 403. Ahora no llega
        ni a esa comprobacion: el vehiculo ajeno no esta en el queryset, asi que
        responde 404. Se prefiere el 404 porque no confirma que el id exista.
        """
        vehicle = create_vehicle(self.victim)

        response = self.client.delete(f"/api/v1/vehicles/{vehicle.pk}/")

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        vehicle.refresh_from_db()
        self.assertFalse(vehicle.is_deleted)

    def test_the_caller_can_still_delete_their_own_vehicle(self):
        own = create_vehicle(self.attacker)

        response = self.client.delete(f"/api/v1/vehicles/{own.pk}/")

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        own.refresh_from_db()
        self.assertTrue(own.is_deleted)

class PreferencesExposureTest(BaseOwnershipTest):

    def test_the_list_only_returns_the_callers_preferences(self):
        pref_type = PrefTypes.objects.filter(is_deleted=False).first()
        Preferences.objects.create(id_user=self.victim, pref_type=pref_type)

        response = self.client.get("/api/v1/preferences/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['count'], 0)


class DriverRatingsExposureTest(BaseOwnershipTest):

    def test_individual_ratings_of_other_users_are_not_visible(self):
        """
        Las valoraciones se consultan agregadas en /users/{id}/driverratings/,
        que es justo lo que evita saber quien puntuo a quien y con que nota.
        Este endpoint las exponia una a una.
        """
        driver = create_user("driver")
        DriverRatings.objects.create(
            id_user=self.victim,
            id_driver=driver,
            criteria=Criteria.objects.get(code='punctuality'),
            score=3,
        )

        response = self.client.get("/api/v1/driverratings/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['count'], 0)

    def test_the_caller_sees_the_ratings_they_wrote(self):
        driver = create_user("driver")
        DriverRatings.objects.create(
            id_user=self.attacker,
            id_driver=driver,
            criteria=Criteria.objects.get(code='punctuality'),
            score=9,
        )

        response = self.client.get("/api/v1/driverratings/")

        self.assertEqual(response.data['count'], 1)


class DevicesExposureTest(BaseOwnershipTest):

    def test_fcm_tokens_of_other_users_are_not_visible(self):
        """
        Los tokens de FCM permiten enviar notificaciones push al dispositivo.
        Exponerlos es especialmente sensible.
        """
        Device.objects.create(
            id_user=self.victim, fcm_token="token-privado-de-la-victima", platform="android"
        )

        response = self.client.get("/api/v1/devices/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        tokens = [d['fcm_token'] for d in response.data['results']]
        self.assertNotIn("token-privado-de-la-victima", tokens)
        self.assertEqual(tokens, [])

    def test_registering_a_device_still_works(self):
        """El alta de dispositivo la hace la app en cada arranque."""
        response = self.client.post(
            "/api/v1/devices/",
            {'fcm_token': "token-del-atacante", 'platform': "android"},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(
            Device.objects.filter(id_user=self.attacker, fcm_token="token-del-atacante").exists()
        )


class CatalogWriteTest(BaseOwnershipTest):
    """
    Los catalogos eran ModelViewSet abiertos y cualquiera podia modificarlos.
    Ahora son `ReadOnlyModelViewSet`
    """

    def test_a_travel_state_cannot_be_deleted(self):
        response = self.client.delete("/api/v1/travelstates/1/")

        self.assertEqual(response.status_code, status.HTTP_405_METHOD_NOT_ALLOWED)

        from travels.models import TravelStates
        self.assertFalse(TravelStates.objects.get(pk=1).is_deleted)

    def test_a_user_type_cannot_be_created(self):
        response = self.client.post(
            "/api/v1/usertypes/", {'code': 'hack', 'name': 'Inventado'}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_405_METHOD_NOT_ALLOWED)

    def test_the_catalogs_can_still_be_read(self):
        """
        La app necesita leerlos para pintar los desplegables: el cierre no puede
        haberse llevado por delante la consulta.
        """
        for catalog_name in ("usertypes", "preftypes", "criteria", "envtypes",
                     "travelstates", "requeststates"):
            with self.subTest(catalog_name=catalog_name):
                response = self.client.get(f"/api/v1/{catalog_name}/")
                self.assertEqual(response.status_code, status.HTTP_200_OK)
                self.assertGreater(response.data['count'], 0)


class TravelOwnershipContrastTest(BaseOwnershipTest):
    """
    Los viajes SI son visibles para todos a proposito (hay que poder buscarlos),
    pero solo su creador puede modificarlos. Aqui la comprobacion explicita en
    la vista es la correcta: no se puede filtrar el queryset.
    """

    def test_editing_another_users_travel_is_blocked(self):
        travel = create_travel(self.victim)

        response = self.client.patch(
            f"/api/v1/travel/{travel.pk}/", {'origin': 'Secuestrado'}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_deleting_another_users_travel_is_blocked(self):
        travel = create_travel(self.victim)

        response = self.client.delete(f"/api/v1/travel/{travel.pk}/")

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
