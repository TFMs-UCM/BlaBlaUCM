"""
Pruebas de REGRESION DE SEGURIDAD sobre lo que cuelga de un viaje.
    /api/v1/pickuppoints/
    /api/v1/usersdenied/
"""
from rest_framework import status
from rest_framework.test import APITestCase

from api.errors import ErrorCodes
from travels.models import PickUpPoints, UsersDenied
from travels.tests.factories import create_travel, create_user


class BaseTravelChildTest(APITestCase):

    def setUp(self):
        self.victim = create_user("victim")
        self.attacker = create_user("attacker")
        self.victim_travel = create_travel(self.victim)
        self.own_travel = create_travel(self.attacker)
        self.client.force_authenticate(user=self.attacker)


class PickUpPointsOwnershipTest(BaseTravelChildTest):

    def setUp(self):
        super().setUp()
        self.victim_point = PickUpPoints.objects.create(
            id_travel=self.victim_travel, direction="Moncloa", order_in_travel=1
        )

    def post(self, payload):
        return self.client.post("/api/v1/pickuppoints/", payload, format='json')

    def test_the_list_only_returns_points_of_the_callers_travels(self):
        PickUpPoints.objects.create(
            id_travel=self.own_travel, direction="Atocha", order_in_travel=1
        )

        response = self.client.get("/api/v1/pickuppoints/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        addresses = [p['direction'] for p in response.data['results']]
        self.assertEqual(addresses, ["Atocha"])

    def test_a_point_of_another_travel_cannot_be_read(self):
        response = self.client.get(f"/api/v1/pickuppoints/{self.victim_point.pk}/")

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_a_point_cannot_be_added_to_another_travel(self):
        """
        La via que el filtrado del queryset NO cubre: `create` no consulta el
        queryset, guarda el `id_travel` que venga en el cuerpo.
        """
        response = self.post({
            'id_travel': str(self.victim_travel.pk),
            'direction': "Secuestrado",
            'order_in_travel': 2,
        })

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data['error_code'], ErrorCodes.INSUFICIENT_CREDENTIALS)
        self.assertEqual(PickUpPoints.objects.filter(id_travel=self.victim_travel).count(), 1)

    def test_a_bulk_post_with_one_foreign_travel_creates_nothing(self):
        """
        El endpoint acepta listas. Basta un elemento ajeno para rechazar la
        peticion entera: si se validara solo el primero, colar el segundo seria trivial.
        """
        response = self.post([
            {'id_travel': str(self.own_travel.pk), 'direction': "Propia", 'order_in_travel': 1},
            {'id_travel': str(self.victim_travel.pk), 'direction': "Ajena", 'order_in_travel': 2},
        ])

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        # Ni la propia se ha creado
        self.assertEqual(PickUpPoints.objects.filter(id_travel=self.own_travel).count(), 0)
        self.assertEqual(PickUpPoints.objects.filter(id_travel=self.victim_travel).count(), 1)

    def test_a_point_of_another_travel_cannot_be_modified(self):
        response = self.client.patch(
            f"/api/v1/pickuppoints/{self.victim_point.pk}/",
            {'direction': "Desviado"},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.victim_point.refresh_from_db()
        self.assertEqual(self.victim_point.direction, "Moncloa")

    def test_a_point_of_another_travel_cannot_be_deleted(self):
        response = self.client.delete(f"/api/v1/pickuppoints/{self.victim_point.pk}/")

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.victim_point.refresh_from_db()
        self.assertFalse(self.victim_point.is_deleted)

    def test_an_own_point_cannot_be_moved_to_another_travel(self):
        """
        Tercera via, la mas sutil: la fila es propia, asi que el queryset la deja
        pasar, pero el cuerpo reasigna `id_travel` a un viaje ajeno.

        `order_in_travel` distinto del que ya tiene el viaje de la victima a
        proposito: con el mismo, salta el `UniqueConstraint` de
        (id_travel, order_in_travel) y la peticion se rechazaria con un 400 sin
        llegar a la comprobacion de propiedad, que es lo que se quiere probar.
        """
        own_point = PickUpPoints.objects.create(
            id_travel=self.own_travel, direction="Mia", order_in_travel=5
        )

        response = self.client.patch(
            f"/api/v1/pickuppoints/{own_point.pk}/",
            {'id_travel': str(self.victim_travel.pk)},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        own_point.refresh_from_db()
        self.assertEqual(own_point.id_travel, self.own_travel)

    # --- Contrapartes: el conductor sigue pudiendo -----------------------

    def test_the_driver_can_add_a_point_to_their_own_travel(self):
        response = self.post({
            'id_travel': str(self.own_travel.pk),
            'direction': "Atocha",
            'order_in_travel': 1,
        })

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(PickUpPoints.objects.filter(id_travel=self.own_travel).count(), 1)

    def test_the_driver_can_add_several_points_at_once(self):
        response = self.post([
            {'id_travel': str(self.own_travel.pk), 'direction': "Primera", 'order_in_travel': 1},
            {'id_travel': str(self.own_travel.pk), 'direction': "Segunda", 'order_in_travel': 2},
        ])

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(PickUpPoints.objects.filter(id_travel=self.own_travel).count(), 2)

    def test_the_driver_can_modify_and_delete_their_own_points(self):
        own_point = PickUpPoints.objects.create(
            id_travel=self.own_travel, direction="Mia", order_in_travel=1
        )

        patch = self.client.patch(
            f"/api/v1/pickuppoints/{own_point.pk}/", {'direction': "Corregida"}, format='json'
        )
        self.assertEqual(patch.status_code, status.HTTP_200_OK)
        own_point.refresh_from_db()
        self.assertEqual(own_point.direction, "Corregida")

        delete = self.client.delete(f"/api/v1/pickuppoints/{own_point.pk}/")
        self.assertEqual(delete.status_code, status.HTTP_204_NO_CONTENT)
        own_point.refresh_from_db()
        self.assertTrue(own_point.is_deleted)


class UsersDeniedOwnershipTest(BaseTravelChildTest):

    def setUp(self):
        super().setUp()
        self.victim_denied = UsersDenied.objects.create(
            id_travel=self.victim_travel, user_type_id='prof'
        )

    def post(self, payload):
        return self.client.post("/api/v1/usersdenied/", payload, format='json')

    def test_the_list_only_returns_rows_of_the_callers_travels(self):
        response = self.client.get("/api/v1/usersdenied/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['count'], 0)

    def test_a_role_cannot_be_denied_on_another_travel(self):
        """
        Impacto concreto: prohibir un tipo de usuario en un viaje ajeno deja
        fuera a los pasajeros que encajaban en él.
        """
        response = self.post({
            'id_travel': str(self.victim_travel.pk),
            'user_type': 'std',
        })

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(UsersDenied.objects.filter(id_travel=self.victim_travel).count(), 1)

    def test_a_row_of_another_travel_cannot_be_deleted(self):
        response = self.client.delete(f"/api/v1/usersdenied/{self.victim_denied.pk}/")

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.victim_denied.refresh_from_db()
        self.assertFalse(self.victim_denied.is_deleted)

    def test_the_driver_can_deny_a_role_on_their_own_travel(self):
        response = self.post({
            'id_travel': str(self.own_travel.pk),
            'user_type': 'prof',
        })

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(UsersDenied.objects.filter(id_travel=self.own_travel).count(), 1)


class TravelDetailsStillWorksTest(APITestCase):
    """
    Contraparte de integracion, la que de verdad importa: filtrar estos dos
    endpoints NO puede haber roto la pantalla de detalle de un viaje ajeno, que
    es donde la app enseña las paradas y los roles denegados.

    Ese camino no pasa por los ViewSets filtrados, sino por `get_travel_details`.
    """

    def setUp(self):
        self.driver = create_user("driver")
        self.passenger = create_user("passenger")
        self.travel = create_travel(self.driver)
        PickUpPoints.objects.create(
            id_travel=self.travel, direction="Moncloa", order_in_travel=1
        )
        UsersDenied.objects.create(id_travel=self.travel, user_type_id='prof')
        self.client.force_authenticate(user=self.passenger)

    def test_a_passenger_still_sees_the_pickup_points_of_a_travel_they_do_not_own(self):
        response = self.client.get(f"/api/v1/travel/{self.travel.pk}/get_travel_details/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        addresses = [p['direction'] for p in response.data['pickup_points']]
        self.assertEqual(addresses, ["Moncloa"])

    def test_a_passenger_still_sees_the_denied_roles(self):
        response = self.client.get(f"/api/v1/travel/{self.travel.pk}/get_travel_details/")

        self.assertEqual(response.data['denied_roles'], ['prof'])
