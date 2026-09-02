"""
Pruebas de CARACTERIZACION de la creacion de viajes.
    POST /api/v1/travel/
"""
from datetime import timedelta

from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from chats.models import Chat
from travels.models import PickUpPoints, Travel, UsersDenied
from travels.tests.factories import create_user, create_vehicle


class BaseTravelCreationTest(APITestCase):

    def setUp(self):
        self.driver = create_user("driver")
        self.vehicle = create_vehicle(self.driver, seats=5)
        self.client.force_authenticate(user=self.driver)
        self.start_date = timezone.now() + timedelta(days=3)

    def payload(self, **overrides):
        data = {
            'origin': "Moncloa",
            'destination': "Facultad de Informatica",
            'origin_lat': 40.4350,
            'origin_lng': -3.7190,
            'destination_lat': 40.4530,
            'destination_lng': -3.7280,
            'duration_minutes': 25,
            'num_seats': 4,
            'remaining_seats': 4,
            'travel_date': self.start_date.isoformat(),
            'state': 'active',
            'vehicle_id': str(self.vehicle.id_vehicle),
            'is_periodic': False,
        }
        data.update(overrides)
        return data

    def create_travel(self, **overrides):
        return self.client.post("/api/v1/travel/", self.payload(**overrides), format='json')

    def pickup_point(self, direction, order, date=None):
        return {
            'direction': direction,
            'order_in_travel': order,
            'lat': 40.44,
            'lng': -3.72,
            'date': date.isoformat() if date else None,
        }


class PunctualTravelCreationTest(BaseTravelCreationTest):

    def test_creating_a_travel_returns_201_and_stores_it(self):
        response = self.create_travel()

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

        travel = Travel.objects.get()
        self.assertEqual(travel.origin, "Moncloa")
        self.assertEqual(travel.num_seats, 4)

    def test_the_creator_is_taken_from_the_session_not_the_payload(self):
        other = create_user("otro")

        self.create_travel(creation_user=str(other.id))

        self.assertEqual(Travel.objects.get().creation_user_id, self.driver.id)

    def test_remaining_seats_is_forced_to_the_total(self):
        """
        `remaining_seats` es obligatorio en la peticion (el modelo no admite
        null), pero `create()` lo sobrescribe con `num_seats`. Es decir: el
        cliente esta obligado a mandar un valor que se ignora.
        """
        self.create_travel(num_seats=4, remaining_seats=1)

        self.assertEqual(Travel.objects.get().remaining_seats, 4)

    def test_the_coordinates_become_geographic_points(self):
        self.create_travel()

        travel = Travel.objects.get()
        self.assertIsNotNone(travel.origin_point)
        self.assertIsNotNone(travel.destination_point)
        self.assertAlmostEqual(travel.origin_point.y, 40.4350, places=3)
        self.assertAlmostEqual(travel.origin_point.x, -3.7190, places=3)

    def test_the_chat_of_the_travel_is_created(self):
        self.create_travel()

        travel = Travel.objects.get()
        self.assertTrue(Chat.objects.filter(id_travel=travel).exists())

    def test_pickup_points_are_created_in_order(self):
        response = self.create_travel(
            pick_up_points=[
                self.pickup_point("Argüelles", 1),
                self.pickup_point("Islas Filipinas", 2),
            ]
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

        travel = Travel.objects.get()
        points = PickUpPoints.objects.filter(id_travel=travel).order_by('order_in_travel')
        self.assertEqual([p.direction for p in points], ["Argüelles", "Islas Filipinas"])
        self.assertIsNotNone(points.first().point)

    def test_denied_roles_are_created(self):
        response = self.create_travel(deny_roles=['prof'])

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

        travel = Travel.objects.get()
        denied = UsersDenied.objects.filter(id_travel=travel)
        self.assertEqual([d.user_type_id for d in denied], ['prof'])

    def test_unknown_denied_roles_are_ignored(self):
        response = self.create_travel(deny_roles=['prof', 'NO_EXISTE'])

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(UsersDenied.objects.count(), 1)

    def test_a_travel_without_mandatory_fields_is_rejected(self):
        payload = self.payload()
        del payload['origin']

        response = self.client.post("/api/v1/travel/", payload, format='json')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(Travel.objects.count(), 0)

    def test_a_travel_without_coordinates_is_rejected(self):
        payload = self.payload()
        del payload['origin_lat']

        response = self.client.post("/api/v1/travel/", payload, format='json')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_more_seats_than_allowed_is_rejected(self):
        response = self.create_travel(num_seats=50, remaining_seats=50)

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(Travel.objects.count(), 0)


class PeriodicTravelCreationTest(BaseTravelCreationTest):
    """
    Al crear un viaje periodico, los hijos NO los crea Django: los inserta el
    trigger `create_periodic_travels` (migracion travels.0004) en el mismo
    INSERT. El serializer los busca despues para copiarles paradas y roles.
    """

    def create_periodic(self, interval=7, weeks=3, **overrides):
        end_date = (self.start_date + timedelta(days=interval * weeks)).date()
        return self.create_travel(
            is_periodic=True,
            periodic_interval=interval,
            end_periodic_date=end_date.isoformat(),
            **overrides,
        )

    def test_the_trigger_creates_the_child_travels(self):
        response = self.create_periodic(interval=7, weeks=3)

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

        parent = Travel.objects.get(id_origin_travel__isnull=True)
        children = Travel.objects.filter(id_origin_travel=parent)
        self.assertEqual(children.count(), 3)

    def test_the_children_copy_the_seats_of_the_parent(self):
        self.create_periodic()

        parent = Travel.objects.get(id_origin_travel__isnull=True)
        for child in Travel.objects.filter(id_origin_travel=parent):
            self.assertEqual(child.num_seats, parent.num_seats)
            self.assertEqual(child.remaining_seats, parent.num_seats)
            self.assertTrue(child.is_periodic)

    def test_the_pickup_points_are_copied_to_every_child(self):
        self.create_periodic(
            pick_up_points=[self.pickup_point("Argüelles", 1, date=self.start_date)]
        )

        parent = Travel.objects.get(id_origin_travel__isnull=True)
        children = Travel.objects.filter(id_origin_travel=parent)

        for child in children:
            self.assertEqual(PickUpPoints.objects.filter(id_travel=child).count(), 1)

    def test_the_copied_pickup_points_shift_their_date_with_the_travel(self):
        """
        La parada del hijo no hereda la fecha del padre tal cual: se le suma la
        diferencia entre las fechas de los dos viajes.
        """
        self.create_periodic(
            interval=7, weeks=1,
            pick_up_points=[self.pickup_point("Argüelles", 1, date=self.start_date)],
        )

        parent = Travel.objects.get(id_origin_travel__isnull=True)
        child = Travel.objects.get(id_origin_travel=parent)

        parent_point = PickUpPoints.objects.get(id_travel=parent)
        child_point = PickUpPoints.objects.get(id_travel=child)

        difference = child_point.date - parent_point.date
        self.assertEqual(difference.days, 7)

    def test_the_denied_roles_are_copied_to_every_child(self):
        self.create_periodic(deny_roles=['prof'])

        parent = Travel.objects.get(id_origin_travel__isnull=True)
        for child in Travel.objects.filter(id_origin_travel=parent):
            self.assertEqual(
                list(UsersDenied.objects.filter(id_travel=child).values_list('user_type', flat=True)),
                ['prof'],
            )

    def test_every_child_gets_its_own_chat(self):
        self.create_periodic()

        for travel in Travel.objects.all():
            self.assertTrue(
                Chat.objects.filter(id_travel=travel).exists(),
                f"El viaje {travel.pk} se ha quedado sin chat",
            )

    def test_without_pickup_points_or_denied_roles_nothing_is_copied(self):
        self.create_periodic()

        self.assertEqual(PickUpPoints.objects.count(), 0)
        self.assertEqual(UsersDenied.objects.count(), 0)


class ModelValidationReachesTheClientTest(BaseTravelCreationTest):

    def test_a_rule_of_the_model_comes_back_as_400_and_not_500(self):
        """
        `clean()` exige intervalo si el viaje es periodico. El serializer no lo
        comprueba, asi que este camino solo lo corta el modelo.
        """
        response = self.create_travel(is_periodic=True)

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertNotEqual(response.status_code, status.HTTP_500_INTERNAL_SERVER_ERROR)

    def test_the_response_says_which_field_is_wrong(self):
        """
        Lo que se gana ademas del codigo correcto: el mensaje del modelo llega al
        cliente en vez de quedarse solo en el log.
        """
        response = self.create_travel(is_periodic=True)

        self.assertIn('periodic_interval', response.data['fields'])

    def test_nothing_is_stored_when_the_model_rejects_it(self):
        """Contrapartida: que responda 400 no vale de nada si ha guardado igual."""
        self.create_travel(is_periodic=True)

        self.assertEqual(Travel.objects.count(), 0)

    def test_a_valid_travel_is_still_created(self):
        """
        Contrapartida obligatoria: traducir la excepcion no puede convertir en
        error lo que antes funcionaba.
        """
        response = self.create_travel()

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
