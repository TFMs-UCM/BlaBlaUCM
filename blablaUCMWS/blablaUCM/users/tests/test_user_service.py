"""
Pruebas UNITARIAS de `UserService`
"""
from datetime import timedelta

from django.test import TestCase
from django.utils import timezone

from travels.models import Travel, TravelStates
from travels.tests.factories import (
    create_request,
    create_travel,
    create_user,
    create_vehicle,
)
from users.models import Device, Notifications, Preferences, PrefTypes
from users.services.exceptions import (
    IncorrectPasswordError,
    NoUpcomingTravelsError,
    RequestTravelNotValidatedError,
    UserNotFoundError,
    VehicleHasActiveTravelsError,
    VehicleSeatsInsufficientError,
)
from users.services.user_service import UserService


class FindUserTest(TestCase):

    def setUp(self):
        self.user = create_user("buscado")

    def test_finds_by_username(self):
        self.assertEqual(UserService.find_by_username_or_email("buscado"), self.user)

    def test_finds_by_email_when_the_identifier_has_an_at_sign(self):
        self.assertEqual(UserService.find_by_username_or_email(self.user.email), self.user)

    def test_an_unknown_identifier_raises(self):
        with self.assertRaises(UserNotFoundError):
            UserService.find_by_username_or_email("no_existe")

    def test_a_deleted_user_is_not_found(self):
        self.user.is_deleted = True
        self.user.save()

        with self.assertRaises(UserNotFoundError):
            UserService.find_by_username_or_email("buscado")


class ChangePasswordTest(TestCase):

    def setUp(self):
        self.user = create_user("dueño")
        self.user.set_password("actual")
        self.user.save()

    def test_the_password_changes_when_the_current_one_is_right(self):
        UserService.change_password(self.user, "actual", "nueva-clave")

        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("nueva-clave"))

    def test_a_wrong_current_password_raises_and_changes_nothing(self):
        with self.assertRaises(IncorrectPasswordError):
            UserService.change_password(self.user, "equivocada", "nueva")

        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("actual"))


class PreferencesTest(TestCase):
    def setUp(self):
        self.user = create_user("con_preferencias")
        self.codes = list(
            PrefTypes.objects.filter(is_deleted=False).values_list('code', flat=True)[:3]
        )

    def active_codes(self):
        return set(UserService.list_preferences(self.user).values_list('pref_type', flat=True))

    def test_update_sets_exactly_the_requested_preferences(self):
        UserService.update_preferences(self.user, self.codes[:2])

        self.assertEqual(self.active_codes(), set(self.codes[:2]))

    def test_update_ignores_codes_that_are_not_in_the_catalog(self):
        UserService.update_preferences(self.user, [self.codes[0], 'NO_EXISTE'])

        self.assertEqual(self.active_codes(), {self.codes[0]})

    def test_update_returns_how_many_are_active(self):
        self.assertEqual(UserService.update_preferences(self.user, self.codes[:2]), 2)

    def test_what_is_removed_is_soft_deleted_not_erased(self):
        UserService.update_preferences(self.user, [self.codes[0]])
        UserService.update_preferences(self.user, [self.codes[1]])

        self.assertEqual(self.active_codes(), {self.codes[1]})
        # La fila antigua sigue en la tabla, marcada
        self.assertTrue(
            Preferences.objects.get(id_user=self.user, pref_type=self.codes[0]).is_deleted
        )

    def test_a_preference_that_comes_back_reuses_its_row(self):
        """
        Sin esto, el borrado logico en una tabla de union acumularia una fila
        muerta por cada cambio del usuario.
        """
        for _ in range(5):
            UserService.update_preferences(self.user, [self.codes[0]])
            UserService.update_preferences(self.user, [])

        UserService.update_preferences(self.user, [self.codes[0]])

        self.assertEqual(Preferences.objects.filter(id_user=self.user).count(), 1)
        self.assertEqual(self.active_codes(), {self.codes[0]})

    def test_clear_marks_every_active_preference_as_deleted(self):
        UserService.update_preferences(self.user, self.codes[:2])

        self.assertEqual(UserService.clear_preferences(self.user), 2)
        self.assertEqual(self.active_codes(), set())

    def test_clear_on_a_user_without_preferences_returns_zero(self):
        self.assertEqual(UserService.clear_preferences(self.user), 0)

    def test_list_only_returns_the_active_ones(self):
        UserService.update_preferences(self.user, self.codes[:2])
        UserService.update_preferences(self.user, [self.codes[0]])

        self.assertEqual(UserService.list_preferences(self.user).count(), 1)


class NotificationsTest(TestCase):

    def setUp(self):
        self.user = create_user("avisado")

    def test_counts_only_the_unread_ones(self):
        Notifications.objects.create(id_user=self.user, content="sin leer")
        Notifications.objects.create(id_user=self.user, content="leida", read=True)

        self.assertEqual(UserService.count_unread_notifications(self.user), 1)

    def test_deleted_notifications_do_not_count(self):
        Notifications.objects.create(id_user=self.user, content="borrada", is_deleted=True)

        self.assertEqual(UserService.count_unread_notifications(self.user), 0)

    def test_the_default_order_is_newest_first(self):
        old_notification = Notifications.objects.create(id_user=self.user, content="vieja")
        Notifications.objects.filter(pk=old_notification.pk).update(
            date=timezone.now() - timedelta(days=1)
        )
        Notifications.objects.create(id_user=self.user, content="nueva")

        contents = list(
            UserService.list_notifications(self.user).values_list('content', flat=True)
        )
        self.assertEqual(contents, ["nueva", "vieja"])

    def test_ascending_order_can_be_requested(self):
        old_notification = Notifications.objects.create(id_user=self.user, content="vieja")
        Notifications.objects.filter(pk=old_notification.pk).update(
            date=timezone.now() - timedelta(days=1)
        )
        Notifications.objects.create(id_user=self.user, content="nueva")

        contents = list(
            UserService.list_notifications(self.user, ordering='asc')
            .values_list('content', flat=True)
        )
        self.assertEqual(contents, ["vieja", "nueva"])


class CreatedTravelsTest(TestCase):

    def setUp(self):
        self.driver = create_user("conductor")

    def test_pending_returns_the_upcoming_and_the_started_ones(self):
        future = create_travel(self.driver)
        started = create_travel(self.driver, state='started')

        ids = set(UserService.list_created_travels(self.driver, 'pending').values_list('pk', flat=True))
        self.assertEqual(ids, {future.pk, started.pk})

    def test_past_returns_the_finished_ones(self):
        finished = create_travel(self.driver, state='fnd')
        create_travel(self.driver)

        ids = set(UserService.list_created_travels(self.driver, 'past').values_list('pk', flat=True))
        self.assertEqual(ids, {finished.pk})

    def test_without_a_type_it_returns_them_all(self):
        create_travel(self.driver)
        create_travel(self.driver, state='fnd')

        self.assertEqual(UserService.list_created_travels(self.driver).count(), 2)

    def test_deleted_travels_never_show_up(self):
        travel = create_travel(self.driver)
        Travel.objects.filter(pk=travel.pk).update(is_deleted=True)

        self.assertEqual(UserService.list_created_travels(self.driver).count(), 0)


class OwnRequestsTest(TestCase):

    def setUp(self):
        self.driver = create_user("conductor")
        self.passenger = create_user("pasajero")

    def test_pending_also_includes_the_rejected_ones(self):
        """
        Es intencionado: el usuario tiene que ver en la misma pantalla que le han
        dicho que no
        """
        pending = create_request(create_travel(self.driver), self.passenger, 'pending')
        rejected = create_request(create_travel(self.driver), self.passenger, 'rejected')

        ids = set(
            UserService.list_own_requests(self.passenger, 'pending').values_list('pk', flat=True)
        )
        self.assertEqual(ids, {pending.pk, rejected.pk})

    def test_active_returns_only_the_accepted_ones(self):
        accepted = create_request(create_travel(self.driver), self.passenger, 'accepted')
        create_request(create_travel(self.driver), self.passenger, 'pending')

        ids = set(
            UserService.list_own_requests(self.passenger, 'active').values_list('pk', flat=True)
        )
        self.assertEqual(ids, {accepted.pk})

    def test_past_returns_the_validated_and_the_unvalidated(self):
        validated = create_request(create_travel(self.driver), self.passenger, 'validated')
        unvalidated = create_request(create_travel(self.driver), self.passenger, 'unvalidated')
        create_request(create_travel(self.driver), self.passenger, 'accepted')

        ids = set(
            UserService.list_own_requests(self.passenger, 'past').values_list('pk', flat=True)
        )
        self.assertEqual(ids, {validated.pk, unvalidated.pk})


class ReceivedRequestsTest(TestCase):

    def test_returns_the_pending_requests_of_the_travels_created_by_the_user(self):
        driver = create_user("conductor")
        travel = create_travel(driver)
        pending = create_request(travel, create_user("p1"), 'pending')
        create_request(travel, create_user("p2"), 'accepted')

        ids = set(UserService.list_received_requests(driver).values_list('pk', flat=True))
        self.assertEqual(ids, {pending.pk})

    def test_a_user_without_travels_receives_nothing(self):
        self.assertEqual(UserService.list_received_requests(create_user("nadie")).count(), 0)


class NextTravelsTest(TestCase):

    def setUp(self):
        self.driver = create_user("conductor")

    def test_a_user_without_travels_raises(self):
        with self.assertRaises(NoUpcomingTravelsError):
            UserService.get_next_travels(self.driver)

    def test_a_started_travel_always_comes_first(self):
        create_travel(self.driver)
        started = create_travel(self.driver, state='started')

        result = UserService.get_next_travels(self.driver)

        self.assertEqual(result[0]['id'], started.pk)
        self.assertEqual(result[0]['status'], 'started')

    def test_it_returns_at_most_three(self):
        for _ in range(5):
            create_travel(self.driver)

        self.assertEqual(len(UserService.get_next_travels(self.driver)), 3)

    def test_a_started_travel_takes_up_one_of_the_three_slots(self):
        create_travel(self.driver, state='started')
        for _ in range(5):
            create_travel(self.driver)

        self.assertEqual(len(UserService.get_next_travels(self.driver)), 3)

    def test_requested_travels_come_with_their_validation_code(self):
        passenger = create_user("pasajero")
        travel = create_travel(self.driver)
        request_travel = create_request(travel, passenger, 'accepted')
        request_travel.validation_code = "ABCD1234"
        request_travel.save()

        result = UserService.get_next_travels(passenger)

        self.assertTrue(result[0]['is_request'])
        self.assertEqual(result[0]['code'], "ABCD1234")
        self.assertEqual(result[0]['id'], request_travel.id)


class RateDriverTest(TestCase):

    def setUp(self):
        self.driver = create_user("conductor")
        self.passenger = create_user("pasajero")
        self.travel = create_travel(self.driver)

    def test_a_request_that_is_not_validated_raises(self):
        pending = create_request(self.travel, self.passenger, 'accepted')

        with self.assertRaises(RequestTravelNotValidatedError):
            UserService.rate_driver(self.passenger, pending.pk, {'punctuality': 9})

    def test_a_request_of_another_user_raises(self):
        someone_elses = create_request(self.travel, create_user("otro"), 'validated')

        with self.assertRaises(RequestTravelNotValidatedError):
            UserService.rate_driver(self.passenger, someone_elses.pk, {'punctuality': 9})

    def test_rating_closes_the_request_so_it_cannot_be_rated_twice(self):
        validated = create_request(self.travel, self.passenger, 'validated')

        UserService.rate_driver(self.passenger, validated.pk, {'punctuality': 9})

        validated.refresh_from_db()
        self.assertEqual(validated.status_id, 'unvalidated')

        with self.assertRaises(RequestTravelNotValidatedError):
            UserService.rate_driver(self.passenger, validated.pk, {'punctuality': 1})


class DriverRatingsTest(TestCase):

    def test_a_driver_without_ratings_gets_the_empty_shape(self):
        """La app espera esta forma concreta, no una lista vacia."""
        data = UserService.get_driver_ratings(create_user("sin_notas"))

        self.assertEqual(data, {"results": {"none": 0}, "count": 0})


class VehicleChecksTest(TestCase):

    def setUp(self):
        self.driver = create_user("conductor")
        self.vehicle = create_vehicle(self.driver, seats=5)

    def test_fewer_than_two_seats_is_rejected(self):
        with self.assertRaises(VehicleSeatsInsufficientError):
            UserService.check_new_seats(self.driver, self.vehicle, 1)

    def test_a_free_vehicle_accepts_the_new_seats(self):
        UserService.check_new_seats(self.driver, self.vehicle, 4)

    def test_it_cannot_drop_below_the_seats_already_published(self):
        Travel.objects.create(
            origin="Moncloa",
            destination="Facultad",
            duration_minutes=25,
            num_seats=4,
            remaining_seats=4,
            travel_date=timezone.now() + timedelta(days=3),
            creation_user=self.driver,
            vehicle=self.vehicle,
            state=TravelStates.objects.get(code='active'),
            is_periodic=False,
        )

        with self.assertRaises(VehicleHasActiveTravelsError):
            UserService.check_new_seats(self.driver, self.vehicle, 4)

    def test_a_vehicle_with_active_travels_cannot_be_deleted(self):
        Travel.objects.create(
            origin="Moncloa",
            destination="Facultad",
            duration_minutes=25,
            num_seats=2,
            remaining_seats=2,
            travel_date=timezone.now() + timedelta(days=3),
            creation_user=self.driver,
            vehicle=self.vehicle,
            state=TravelStates.objects.get(code='active'),
            is_periodic=False,
        )

        with self.assertRaises(VehicleHasActiveTravelsError):
            UserService.check_vehicle_is_free(self.driver, self.vehicle)

    def test_a_free_vehicle_can_be_deleted(self):
        UserService.check_vehicle_is_free(self.driver, self.vehicle)


class RegisterDeviceTest(TestCase):

    def setUp(self):
        self.user = create_user("con_movil")

    def test_registering_creates_the_device(self):
        device = UserService.register_device(self.user, "token-1", "android")

        self.assertEqual(device.id_user, self.user)
        self.assertEqual(Device.objects.filter(fcm_token="token-1").count(), 1)

    def test_the_same_token_changes_hands_instead_of_duplicating(self):
        """
        El token identifica al movil, no a la cuenta: si alguien inicia sesion
        en un telefono donde ya habia otro usuario, el token pasa a ser suyo.
        """
        other_user = create_user("anterior")
        UserService.register_device(other_user, "token-compartido", "android")

        UserService.register_device(self.user, "token-compartido", "android")

        self.assertEqual(Device.objects.filter(fcm_token="token-compartido").count(), 1)
        self.assertEqual(Device.objects.get(fcm_token="token-compartido").id_user, self.user)

    def test_registering_again_revives_a_deleted_device(self):
        UserService.register_device(self.user, "token-2", "ios")
        Device.objects.filter(fcm_token="token-2").update(is_deleted=True)

        UserService.register_device(self.user, "token-2", "ios")

        self.assertFalse(Device.objects.get(fcm_token="token-2").is_deleted)
