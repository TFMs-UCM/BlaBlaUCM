"""
Pruebas de REGRESION DE SEGURIDAD sobre la superficie de ESCRITURA.
"""
from rest_framework import status
from rest_framework.test import APITestCase

from travels.tests.factories import create_travel, create_user
from users.models import Criteria, DriverRatings, Notifications, PrefTypes, Preferences, Users, Vehicles


class CanNotChangeEmailByPatchTest(APITestCase):
    """
    El correo se lee por `/users/{id}/` pero no se escribe.
    """

    def setUp(self):
        self.user = create_user("dueno")
        self.original_email = self.user.email
        self.client.force_authenticate(user=self.user)
        self.url = f"/api/v1/users/{self.user.id}/"

    def test_patching_the_email_does_not_change_it(self):
        response = self.client.patch(
            self.url, {'email': "secuestrada@atacante.com"}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertEqual(self.user.email, self.original_email)

    def test_the_response_keeps_showing_the_real_email(self):
        # De solo lectura, no oculto: la pantalla de perfil lo sigue necesitando
        response = self.client.patch(
            self.url, {'email': "secuestrada@atacante.com"}, format='json'
        )

        self.assertEqual(response.data['email'], self.original_email)

    def test_putting_the_email_is_not_possible_either(self):
        # PUT ya no se publica en este ViewSet
        response = self.client.put(
            self.url, {'email': "secuestrada@atacante.com"}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_405_METHOD_NOT_ALLOWED)
        self.user.refresh_from_db()
        self.assertEqual(self.user.email, self.original_email)

    def test_the_rest_of_the_profile_is_still_editable(self):
        """
        Contrapartida: cerrar el correo no puede haberse llevado por delante lo
        que la aplicacion si edita por aqui.
        """
        response = self.client.patch(
            self.url,
            {'name': "Angel", 'surname1': "Garcia", 'username': "otro-nombre"},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertEqual(self.user.name, "Angel")
        self.assertEqual(self.user.username, "otro-nombre")


class CreateForcesTheOwnerTest(APITestCase):
    """
    `create` no consulta el queryset: el dueño se fuerza, no se valida.
    """

    def setUp(self):
        self.attacker = create_user("atacante")
        self.victim = create_user("victima")
        self.client.force_authenticate(user=self.attacker)

    def test_a_notification_lands_on_the_caller_not_on_the_victim(self):
        response = self.client.post(
            "/api/v1/notifications/",
            {'id_user': str(self.victim.id), 'content': "Tu viaje se ha cancelado"},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertFalse(Notifications.objects.filter(id_user=self.victim).exists())
        self.assertTrue(Notifications.objects.filter(id_user=self.attacker).exists())

    def test_a_rating_cannot_be_attributed_to_someone_else(self):
        driver = create_user("conductor")

        response = self.client.post(
            "/api/v1/driverratings/",
            {
                'id_user': str(self.victim.id),
                'id_driver': str(driver.id),
                'score': 1,
                'criteria': Criteria.objects.first().code,
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        rating = DriverRatings.objects.get()
        self.assertEqual(rating.id_user_id, self.attacker.id)

    def test_a_vehicle_cannot_be_parked_in_someone_elses_garage(self):
        response = self.client.post(
            "/api/v1/vehicles/",
            {
                'id_user': str(self.victim.id),
                'brand': "Seat",
                'model': "Ibiza",
                'license_plate': "9999ZZZ",
                'color': "Rojo",
                'seats': 4,
                'env_sticker': "eco",
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(Vehicles.objects.get().id_user_id, self.attacker.id)

    def test_a_preference_cannot_be_written_on_another_account(self):
        response = self.client.post(
            "/api/v1/preferences/",
            {'id_user': str(self.victim.id), 'pref_type': PrefTypes.objects.first().code},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(Preferences.objects.get().id_user_id, self.attacker.id)

    def test_creating_your_own_still_works(self):
        response = self.client.post(
            "/api/v1/notifications/",
            {'id_user': str(self.attacker.id), 'content': "Mia"},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(Notifications.objects.get().id_user_id, self.attacker.id)


class VerbsThatAreNotPublishedTest(APITestCase):
    """
    Altas y verbos que el router publicaba solo.
    """

    def setUp(self):
        self.user = create_user("alguien")
        self.client.force_authenticate(user=self.user)

    def test_creating_a_user_through_the_viewset_is_not_allowed(self):
        # El alta es /register/, con su serializer, sus reglas de contrasena y su
        # verificacion. Por aqui nacian cuentas sin contrasena y sin verificar
        before = Users.objects.count()

        response = self.client.post(
            "/api/v1/users/",
            {'username': "colado", 'email': "colado@ucm.es", 'name': "X", 'surname1': "Y"},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_405_METHOD_NOT_ALLOWED)
        self.assertEqual(Users.objects.count(), before)

    def test_the_post_actions_of_the_user_viewset_still_work(self):
        """
        La razon de cerrar el alta en `create` y no con `http_method_names`:
        ese atributo se aplica a TODAS las rutas del ViewSet, tambien a las
        `@action`. Si se hubiera quitado `post`, esto daria 405.
        """
        response = self.client.post(
            "/api/v1/users/verify_code/", {'username': "alguien"}, format='json'
        )

        # Falta el token, asi que 400. Lo que importa es que NO es 405
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_creating_a_request_through_the_viewset_is_not_allowed(self):
        # El alta es POST /travel/request-travel/, que ademas comprueba plazas,
        # viaje propio y solicitudes repetidas. Por aqui solo se llegaba a un 500
        travel = create_travel(create_user("conductor"))

        response = self.client.post(
            "/api/v1/requesttravel/", {'id_travel': str(travel.id_travel)}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_405_METHOD_NOT_ALLOWED)

    def test_put_on_user_data_is_not_allowed(self):
        response = self.client.put("/api/v1/notifications/", {}, format='json')

        self.assertEqual(response.status_code, status.HTTP_405_METHOD_NOT_ALLOWED)
