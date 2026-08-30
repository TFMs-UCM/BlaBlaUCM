"""
Pruebas del comando programado que finaliza los viajes caducados
    manage.py finish_travels
"""
from datetime import timedelta
from io import StringIO

from django.core.management import call_command
from django.test import TestCase
from django.utils import timezone

from travels.models import RequestTravels, Travel
from travels.tests.factories import create_request, create_travel, create_user
from users.models import Notifications


class BaseFinishTravelsTest(TestCase):

    def setUp(self):
        self.driver = create_user("driver")
        self.passenger = create_user("passenger")

    def run_command(self):
        call_command('finish_travels', stdout=StringIO())

    def travel_ended_hours_ago(self, hours, duration_minutes=25):
        """
        Coloca el viaje de forma que su hora de llegada fue hace `hours` horas.
        El comando calcula la caducidad como travel_date + duracion + 2 horas.
        """
        travel = create_travel(self.driver)
        Travel.objects.filter(pk=travel.pk).update(
            travel_date=timezone.now() - timedelta(hours=hours, minutes=duration_minutes),
            duration_minutes=duration_minutes,
        )
        travel.refresh_from_db()
        return travel


class ExpirationWindowTest(BaseFinishTravelsTest):

    def test_a_travel_finished_more_than_two_hours_ago_is_closed(self):
        travel = self.travel_ended_hours_ago(3)

        self.run_command()

        travel.refresh_from_db()
        self.assertEqual(travel.state_id, 'fnd')

    def test_a_travel_finished_less_than_two_hours_ago_is_left_alone(self):
        """El margen de dos horas es para que dé tiempo a validar pasajeros."""
        travel = self.travel_ended_hours_ago(1)

        self.run_command()

        travel.refresh_from_db()
        self.assertEqual(travel.state_id, 'active')

    def test_a_future_travel_is_left_alone(self):
        travel = create_travel(self.driver)

        self.run_command()

        travel.refresh_from_db()
        self.assertEqual(travel.state_id, 'active')

    def test_the_duration_counts_towards_the_expiration(self):
        """
        Un viaje largo caduca mas tarde: la cuenta parte de la hora de llegada
        prevista, no de la de salida.
        """
        travel = create_travel(self.driver)
        Travel.objects.filter(pk=travel.pk).update(
            travel_date=timezone.now() - timedelta(hours=3),
            duration_minutes=120,   # llego hace 1 hora, aun no caduca
        )

        self.run_command()

        travel.refresh_from_db()
        self.assertEqual(travel.state_id, 'active')

    def test_an_already_finished_travel_is_not_touched_again(self):
        travel = self.travel_ended_hours_ago(3)
        self.run_command()

        # Segunda pasada: no debe generar notificaciones nuevas
        Notifications.objects.all().delete()
        self.run_command()

        self.assertEqual(Notifications.objects.count(), 0)

    def test_a_deleted_travel_is_ignored(self):
        travel = self.travel_ended_hours_ago(3)
        Travel.objects.filter(pk=travel.pk).update(is_deleted=True)

        self.run_command()

        travel.refresh_from_db()
        self.assertEqual(travel.state_id, 'active')

    def test_running_it_without_expired_travels_does_nothing(self):
        """El caso normal: el cron se ejecuta cada pocos minutos y casi nunca hay nada."""
        self.run_command()

        self.assertEqual(Notifications.objects.count(), 0)


class NotificationsTest(BaseFinishTravelsTest):

    def test_the_passengers_are_notified(self):
        travel = self.travel_ended_hours_ago(3)
        create_request(travel, self.passenger, 'accepted')

        self.run_command()

        notification = Notifications.objects.get(id_user=self.passenger)
        self.assertIn(travel.origin, notification.content)
        self.assertIn(travel.destination, notification.content)
        self.assertIn("NO has sido validado", notification.content)


class RequestStatusRegressionTest(BaseFinishTravelsTest):

    def test_the_command_marks_accepted_requests_as_unvalidated(self):
        """
        Antes las marcaba 'validated' mientras el aviso decia "NO has sido
        validado". Ahora el estado y el texto dicen lo mismo.
        """
        travel = self.travel_ended_hours_ago(3)
        request_row = create_request(travel, self.passenger, 'accepted')

        self.run_command()

        request_row.refresh_from_db()
        self.assertEqual(request_row.status_id, 'unvalidated')

    def test_it_does_not_touch_pending_or_rejected_requests(self):
        """
        El comando ya no arrastra a todas las solicitudes: una que el conductor
        nunca acepto, o que rechazo expresamente, se queda como estaba.
        """
        travel = self.travel_ended_hours_ago(3)
        pending = create_request(travel, self.passenger, 'pending')
        rejected = create_request(travel, create_user("otro"), 'rejected')

        self.run_command()

        pending.refresh_from_db()
        rejected.refresh_from_db()
        self.assertEqual(pending.status_id, 'pending')
        self.assertEqual(rejected.status_id, 'rejected')

    def test_a_rejected_passenger_cannot_rate_the_driver(self):
        """
        La consecuencia que hacia grave el fallo: `UserService.rate_driver` exige
        'validated', y el cron se lo regalaba a cualquiera
        """
        from users.models import DriverRatings
        from users.services.exceptions import RequestTravelNotValidatedError
        from users.services.user_service import UserService

        travel = self.travel_ended_hours_ago(3)
        rejected = create_request(travel, self.passenger, 'rejected')

        self.run_command()

        with self.assertRaises(RequestTravelNotValidatedError):
            UserService.rate_driver(self.passenger, rejected.pk, {'punctuality': 1})

        self.assertFalse(DriverRatings.objects.filter(id_driver=self.driver).exists())

    def test_a_validated_passenger_can_still_rate_the_driver(self):
        """
        Contrapartida obligatoria de la prueba anterior: sin esta, el arreglo se
        podria "aprobar" impidiendo puntuar a todo el mundo. Al pasajero que el
        conductor si valido durante el viaje el cron no le quita ese derecho.
        """
        from users.models import DriverRatings
        from users.services.user_service import UserService

        travel = self.travel_ended_hours_ago(3)
        validated = create_request(travel, self.passenger, 'validated')

        self.run_command()

        UserService.rate_driver(self.passenger, validated.pk, {'punctuality': 5})

        self.assertTrue(DriverRatings.objects.filter(id_driver=self.driver).exists())

    def test_both_ways_of_finishing_leave_the_same_state(self):
        """
        La prueba que fija el arreglo de verdad: mismo viaje, mismo pasajero, los
        dos caminos, y el estado resultante tiene que coincidir.
        """
        from travels.services.travel_service import TravelService

        by_cron = self.travel_ended_hours_ago(3)
        cron_request = create_request(by_cron, self.passenger, 'accepted')

        by_hand = create_travel(self.driver)
        manual_request = create_request(by_hand, create_user("otro_pasajero"), 'accepted')

        self.run_command()
        TravelService.finish_travel(by_hand)

        cron_request.refresh_from_db()
        manual_request.refresh_from_db()
        self.assertEqual(cron_request.status_id, manual_request.status_id)
        self.assertEqual(cron_request.status_id, 'unvalidated')


class ExpiredTravelsQueryTest(BaseFinishTravelsTest):
    """
    La consulta de caducidad se movio al servicio junto con la regla. Aqui se
    prueba directamente, sin pasar por el comando.
    """

    def test_it_finds_the_expired_ones_only(self):
        from travels.services.travel_service import TravelService

        expired = self.travel_ended_hours_ago(3)
        self.travel_ended_hours_ago(1)      # dentro del margen
        create_travel(self.driver)          # futuro

        found = list(TravelService.find_expired_travels())

        self.assertEqual([t.pk for t in found], [expired.pk])

    def test_the_margin_is_a_single_named_constant(self):
        """
        Antes las dos horas estaban escritas dentro del comando. Que sean un
        atributo con nombre es lo que permite probar el limite sin tocar relojes.
        """
        from datetime import timedelta as td

        from travels.services.travel_service import TravelService

        self.assertEqual(TravelService.EXPIRATION_MARGIN, td(hours=2))
