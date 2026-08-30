"""
Borrado logico: que lo borrado deje de verse, y que no se pueda entrar con ello
"""
from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import AccessToken

from travels.tests.factories import create_travel, create_user, create_vehicle
from users.models import Device, Notifications, Users


class DeletedItemsDisappearFromListingsTest(APITestCase):
    """
    `SoftDeleteQuerysetMixin` filtra `is_deleted=False` en `get_queryset`. Se
    comprueba recurso a recurso, porque el mixin hay que heredarlo y el fallo
    tipico es un ViewSet que se olvido de hacerlo.
    """

    def setUp(self):
        self.user = create_user("titular")
        self.client.force_authenticate(user=self.user)

    def test_a_deleted_vehicle_is_not_listed(self):
        alive = create_vehicle(self.user)
        deleted = create_vehicle(self.user)
        deleted.is_deleted = True
        deleted.save()

        response = self.client.get("/api/v1/vehicles/")

        plates = [row['license_plate'] for row in response.data['results']]
        self.assertIn(alive.license_plate, plates)
        self.assertNotIn(deleted.license_plate, plates)

    def test_a_deleted_notification_is_not_listed(self):
        Notifications.objects.create(id_user=self.user, content="viva", is_deleted=False)
        Notifications.objects.create(id_user=self.user, content="borrada", is_deleted=True)

        response = self.client.get("/api/v1/notifications/")

        contents = [row['content'] for row in response.data['results']]
        self.assertIn("viva", contents)
        self.assertNotIn("borrada", contents)

    def test_a_deleted_device_is_not_listed(self):
        Device.objects.create(id_user=self.user, fcm_token="vivo", platform="android")
        Device.objects.create(
            id_user=self.user, fcm_token="borrado", platform="android", is_deleted=True)

        response = self.client.get("/api/v1/devices/")

        tokens = [row['fcm_token'] for row in response.data['results']]
        self.assertIn("vivo", tokens)
        self.assertNotIn("borrado", tokens)

    def test_a_deleted_travel_is_not_listed(self):
        alive = create_travel(self.user)
        deleted = create_travel(self.user)
        deleted.is_deleted = True
        deleted.save()

        response = self.client.get("/api/v1/travel/")

        ids = [row['id_travel'] for row in response.data['results']]
        self.assertIn(str(alive.pk), ids)
        self.assertNotIn(str(deleted.pk), ids)

    def test_deleting_a_vehicle_marks_it_instead_of_removing_the_row(self):
        """`perform_destroy` marca; la fila tiene que seguir ahi con su fecha."""
        vehicle = create_vehicle(self.user)

        response = self.client.delete(f"/api/v1/vehicles/{vehicle.id_vehicle}/")

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        vehicle.refresh_from_db()
        self.assertTrue(vehicle.is_deleted)
        self.assertIsNotNone(vehicle.deleted_at)

    def test_a_deleted_vehicle_cannot_be_retrieved_by_its_id(self):
        """No basta con que no salga en la lista: por id tampoco."""
        vehicle = create_vehicle(self.user)
        vehicle.is_deleted = True
        vehicle.save()

        response = self.client.get(f"/api/v1/vehicles/{vehicle.id_vehicle}/")

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)


class DeletedAccountsTest(APITestCase):
    """
    Que una cuenta borrada no siga operando. `Users.is_active` y el
    `is_verify and not is_deleted` del modelo son lo que lo decide.
    """

    def setUp(self):
        self.user = create_user("caducada")

    def test_a_deleted_user_is_not_listed(self):
        survivor = create_user("viva")
        self.user.is_deleted = True
        self.user.save()
        self.client.force_authenticate(user=survivor)

        response = self.client.get("/api/v1/users/")

        usernames = [row['username'] for row in response.data['results']]
        self.assertIn("viva", usernames)
        self.assertNotIn("caducada", usernames)

    def test_a_token_issued_before_the_deletion_stops_working(self):
        """
        El caso con consecuencias: el token sigue siendo valido
        criptograficamente y su fecha de caducidad no ha llegado. Lo unico que
        cambia es el estado de la cuenta.

        Sale **403 y no 401** por como reparte DRF los dos codigos:
        `api/authentication.py` devuelve el usuario sin mirar `is_deleted`, asi
        que la autenticacion se considera correcta; quien corta es despues la
        propiedad `Users.is_authenticated` (`is_verify and not is_deleted`) al
        evaluar `IsAuthenticated`, y con un autenticador que si funciono DRF
        responde 403. El acceso queda cerrado igual, que es lo que importa.
        """
        token = AccessToken.for_user(self.user)
        self.user.is_deleted = True
        self.user.save()

        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")
        response = self.client.get("/api/v1/vehicles/")

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_an_unverified_account_cannot_operate_either(self):
        """Misma propiedad, otra mitad: sin verificar tampoco se opera."""
        self.user.is_verify = False
        self.user.save()
        token = AccessToken.for_user(self.user)

        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")
        response = self.client.get("/api/v1/vehicles/")

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_a_healthy_account_still_works(self):
        """Contraparte: los 401 de arriba son por el estado de la cuenta, no por otra cosa."""
        token = AccessToken.for_user(self.user)

        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")
        response = self.client.get("/api/v1/vehicles/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_the_row_of_a_deleted_user_survives(self):
        """
        El borrado es logico: la fila sigue, porque de ella cuelgan viajes y
        valoraciones que no se pueden quedar huerfanos.
        """
        self.user.is_deleted = True
        self.user.save()

        self.assertTrue(Users.objects.filter(pk=self.user.pk).exists())
