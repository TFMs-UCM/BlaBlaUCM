"""
Pruebas del bloque de vehiculo de `_edit_periodic_travel`
    PATCH /api/v1/travel/{id}/edit/   sobre un viaje de una serie periodica
"""
from django.db.models import Q
from rest_framework import status
from rest_framework.test import APITestCase

from api.errors import ErrorCodes
from travels.models import Travel
from travels.tests.factories import (
    create_periodic_travel,
    create_request,
    create_user,
    create_vehicle,
)


class BasePeriodicVehicleTest(APITestCase):

    def setUp(self):
        self.driver = create_user("driver")
        self.passenger = create_user("passenger")
        # La serie: padre a 3 dias vista + 3 hijos, uno cada 7 dias.
        # num_seats=3 y el vehiculo original tiene 4 plazas (3 utiles).
        self.parent = create_periodic_travel(self.driver, num_seats=3, interval=7, weeks=3)
        self.old_vehicle = self.parent.vehicle
        self.client.force_authenticate(user=self.driver)

    def series(self):
        """Los viajes de la serie ordenados por fecha: [padre, hijo1, hijo2, hijo3]."""
        return list(
            Travel.objects
            .filter(Q(pk=self.parent.pk) | Q(id_origin_travel=self.parent))
            .order_by('travel_date')
        )

    def reload(self, travel):
        return Travel.objects.get(pk=travel.pk)

    def send_edit(self, travel, **extra):
        """
        Mismo cuerpo minimo que manda la app (ver test_edit_characterization):
        origen, destino, fecha y tipo de viaje viajan siempre aunque no cambien.
        """
        data = {
            'origin': travel.origin,
            'destination': travel.destination,
            'travel_date': travel.travel_date.isoformat(),
            'is_periodic': travel.is_periodic,
        }
        data.update(extra)
        return self.client.patch(f"/api/v1/travel/{travel.pk}/edit/", data, format='json')


class PeriodicVehicleErrorsTest(BasePeriodicVehicleTest):
    """Las tres excepciones del bloque, cada una con su codigo de error."""

    def test_unknown_vehicle_returns_404(self):
        response = self.send_edit(
            self.parent, vehicle_id="00000000-0000-0000-0000-000000000000"
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(response.data['error_code'], ErrorCodes.VEHICLE_DONT_EXIST)
        self.assertEqual(self.reload(self.parent).vehicle_id, self.old_vehicle.id_vehicle)

    def test_a_deleted_vehicle_counts_as_not_found(self):
        """El filtro del servicio lleva `is_deleted=False`: un coche borrado no existe."""
        removed = create_vehicle(self.driver, seats=5)
        removed.is_deleted = True
        removed.save()

        response = self.send_edit(self.parent, vehicle_id=str(removed.id_vehicle))

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(response.data['error_code'], ErrorCodes.VEHICLE_DONT_EXIST)

    def test_a_vehicle_too_small_for_this_travel_returns_400(self):
        # 3 plazas -> 2 utiles, y el viaje necesita 3
        small = create_vehicle(self.driver, seats=3)

        response = self.send_edit(self.parent, vehicle_id=str(small.id_vehicle))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.VEHICLE_SEATS_INSUFFICIENT)
        self.assertEqual(self.reload(self.parent).vehicle_id, self.old_vehicle.id_vehicle)

    def test_a_vehicle_that_fits_this_travel_but_not_a_future_one_returns_400(self):
        """
        `SeriesVehicleSeatsInsufficientError`: el coche vale para el viaje que se
        esta editando, pero un hijo futuro pide mas plazas. Se comprueba ademas
        que el mensaje es el de la serie y no el del viaje suelto, porque la
        excepcion hereda de `VehicleSeatsInsufficientError` y el orden de los
        `except` en la vista es lo unico que los distingue.
        """
        child = self.series()[2]
        Travel.objects.filter(pk=child.pk).update(num_seats=4)
        # 4 plazas -> 3 utiles: le vale al padre (3) pero no al hijo (4)
        new_vehicle = create_vehicle(self.driver, seats=4)

        response = self.send_edit(self.parent, vehicle_id=str(new_vehicle.id_vehicle))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.VEHICLE_SEATS_INSUFFICIENT)
        self.assertIn("serie", response.data['message'])

    def test_the_failed_series_change_leaves_no_partial_write(self):
        child = self.series()[2]
        Travel.objects.filter(pk=child.pk).update(num_seats=4)
        new_vehicle = create_vehicle(self.driver, seats=4)

        response = self.send_edit(self.parent, vehicle_id=str(new_vehicle.id_vehicle))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        # Ni el viaje editado ni ninguno de la serie se ha quedado con el coche nuevo
        for travel in self.series():
            self.assertEqual(travel.vehicle_id, self.old_vehicle.id_vehicle)

    def test_changing_the_denied_user_types_returns_400(self):
        """
        `PeriodicDeniedUsersError`: en una serie periodica no se pueden tocar los
        usuarios denegados. La serie no tiene ninguno, asi que mandar uno ya es
        un cambio.
        """
        response = self.send_edit(self.parent, users_deny=['prof'])

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.TRAVEL_IS_NOT_PUNCTUAL)


class PeriodicVehiclePropagationTest(BasePeriodicVehicleTest):
    """A que viajes alcanza el cambio de vehiculo."""

    def test_changing_the_vehicle_updates_the_whole_series(self):
        new_vehicle = create_vehicle(self.driver, seats=5)

        response = self.send_edit(self.parent, vehicle_id=str(new_vehicle.id_vehicle))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        for travel in self.series():
            self.assertEqual(travel.vehicle_id, new_vehicle.id_vehicle)

    def test_editing_a_child_does_not_touch_the_earlier_travels(self):
        """
        El filtro es `travel_date__gte`: editar desde el segundo viaje de la
        serie cambia ese y los posteriores, y deja intactos los anteriores.
        """
        series_travels = self.series()
        second = series_travels[1]
        new_vehicle = create_vehicle(self.driver, seats=5)

        response = self.send_edit(second, vehicle_id=str(new_vehicle.id_vehicle))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        updated_series = self.series()
        self.assertEqual(updated_series[0].vehicle_id, self.old_vehicle.id_vehicle)
        for travel in updated_series[1:]:
            self.assertEqual(travel.vehicle_id, new_vehicle.id_vehicle)

    def test_only_this_travel_leaves_the_rest_of_the_series_alone(self):
        new_vehicle = create_vehicle(self.driver, seats=5)

        response = self.send_edit(
            self.parent, vehicle_id=str(new_vehicle.id_vehicle), only_this_travel=True
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        series_travels = self.series()
        self.assertEqual(series_travels[0].vehicle_id, new_vehicle.id_vehicle)
        for travel in series_travels[1:]:
            self.assertEqual(travel.vehicle_id, self.old_vehicle.id_vehicle)

    def test_only_this_travel_skips_the_series_seat_check(self):
        """
        La comprobacion de la serie va dentro de `if not only_this_travel`. Con
        un hijo que no cabria en el coche nuevo, cambiar solo este viaje debe
        funcionar igualmente.
        """
        child = self.series()[2]
        Travel.objects.filter(pk=child.pk).update(num_seats=4)
        new_vehicle = create_vehicle(self.driver, seats=4)

        response = self.send_edit(
            self.parent, vehicle_id=str(new_vehicle.id_vehicle), only_this_travel=True
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.reload(self.parent).vehicle_id, new_vehicle.id_vehicle)
        self.assertEqual(self.reload(child).vehicle_id, self.old_vehicle.id_vehicle)

    def test_sending_the_same_vehicle_changes_nothing(self):
        """La guarda de entrada compara con el vehiculo actual: no debe entrar."""
        response = self.send_edit(self.parent, vehicle_id=str(self.old_vehicle.id_vehicle))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.reload(self.parent).vehicle_id, self.old_vehicle.id_vehicle)
        self.assertEqual(self.passenger.notifications.count(), 0)


class PeriodicVehicleNotificationsTest(BasePeriodicVehicleTest):
    """El aviso a los pasajeros aceptados de todos los viajes afectados."""

    def test_every_accepted_passenger_of_the_series_is_notified(self):
        other_user = create_user("passenger2")
        series_travels = self.series()
        create_request(series_travels[0], self.passenger, 'accepted')
        create_request(series_travels[2], other_user, 'accepted')
        new_vehicle = create_vehicle(self.driver, seats=5)

        response = self.send_edit(self.parent, vehicle_id=str(new_vehicle.id_vehicle))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.passenger.notifications.count(), 1)
        self.assertEqual(other_user.notifications.count(), 1)

    def test_pending_requests_are_not_notified(self):
        create_request(self.series()[0], self.passenger, 'pending')
        new_vehicle = create_vehicle(self.driver, seats=5)

        response = self.send_edit(self.parent, vehicle_id=str(new_vehicle.id_vehicle))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.passenger.notifications.count(), 0)

    def test_only_this_travel_notifies_just_its_own_passengers(self):
        other_user = create_user("passenger2")
        series_travels = self.series()
        create_request(series_travels[0], self.passenger, 'accepted')
        create_request(series_travels[2], other_user, 'accepted')
        new_vehicle = create_vehicle(self.driver, seats=5)

        response = self.send_edit(
            self.parent, vehicle_id=str(new_vehicle.id_vehicle), only_this_travel=True
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.passenger.notifications.count(), 1)
        self.assertEqual(other_user.notifications.count(), 0)


class PeriodicIsPeriodicFlagTest(BasePeriodicVehicleTest):
    """
    El final de `_edit_periodic_travel` convierte la serie entera en puntual.

    REGRESION: la condicion era `if not is_periodic:`, y cuando la peticion no
    traia el campo el valor era None, asi que se cumplia siempre. Un PATCH que
    solo cambiaba el vehiculo respondia 200 y deshacia la serie, borrando de
    paso `id_origin_travel` y dejando huerfanos a los hijos
    """

    def test_asking_for_punctual_converts_the_series(self):
        response = self.send_edit(self.parent, is_periodic=False)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(self.reload(self.parent).is_periodic)

    def test_omitting_is_periodic_leaves_the_series_periodic(self):
        """Un PATCH que solo cambia el vehiculo no deberia deshacer la serie."""
        new_vehicle = create_vehicle(self.driver, seats=5)

        response = self.client.patch(
            f"/api/v1/travel/{self.parent.pk}/edit/",
            {
                'origin': self.parent.origin,
                'destination': self.parent.destination,
                'vehicle_id': str(new_vehicle.id_vehicle),
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        updated = self.reload(self.parent)
        self.assertEqual(updated.vehicle_id, new_vehicle.id_vehicle)
        self.assertTrue(updated.is_periodic)
        self.assertIsNotNone(updated.periodic_interval)
