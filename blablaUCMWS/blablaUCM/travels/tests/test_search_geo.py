"""
Pruebas del filtrado geoespacial de la busqueda de viajes.
    TravelService.search_travels  -> las ramas de PostGIS
"""
from django.test import TestCase

from travels.models import Travel
from travels.services.travel_service import TravelService
from travels.tests.factories import (
    ALCALA,
    ATOCHA,
    GETAFE,
    INFORMATICA,
    MONCLOA,
    SOL,
    add_pickup_point,
    create_travel,
    create_user,
    set_travel_points,
)


class BaseGeoSearchTest(TestCase):

    def setUp(self):
        self.driver = create_user("driver")
        self.searcher = create_user("searcher")

    def travel_from(self, origin, destination, **kwargs):
        travel = create_travel(self.driver, **kwargs)
        return set_travel_points(travel, origin=origin, destination=destination)

    def search(self, **data):
        """Lanza la busqueda con el queryset base que usa el view."""
        queryset = Travel.objects.filter(is_deleted=False)
        return list(TravelService.search_travels(queryset, self.searcher, data))

    def coords(self, lat_lng):
        lat, lng = lat_lng
        return {'lat': lat, 'lng': lng}


class OriginOnlySearchTest(BaseGeoSearchTest):
    """Solo se rellena el origen en el buscador."""

    def test_a_travel_starting_near_the_origin_is_found(self):
        travel = self.travel_from(MONCLOA, ATOCHA)

        found_travels = self.search(origin=self.coords(SOL), radius_origin_km=5)

        self.assertEqual(found_travels, [travel])

    def test_a_travel_starting_far_away_is_not_found(self):
        self.travel_from(ALCALA, ATOCHA)

        found_travels = self.search(origin=self.coords(MONCLOA), radius_origin_km=5)

        self.assertEqual(found_travels, [])

    def test_the_radius_is_respected(self):
        """Getafe esta a unos 14 km de Moncloa: dentro de 20, fuera de 5."""
        travel = self.travel_from(GETAFE, ATOCHA)

        self.assertEqual(self.search(origin=self.coords(MONCLOA), radius_origin_km=5), [])
        self.assertEqual(self.search(origin=self.coords(MONCLOA), radius_origin_km=20), [travel])

    def test_without_a_radius_the_default_is_ten_kilometres(self):
        """
        `radius_origin_km` ausente o 0 se convierte en 10 km, no en "sin limite".
        """
        near = self.travel_from(SOL, ATOCHA)
        self.travel_from(GETAFE, ATOCHA)

        self.assertEqual(self.search(origin=self.coords(MONCLOA)), [near])
        self.assertEqual(self.search(origin=self.coords(MONCLOA), radius_origin_km=0), [near])

    def test_a_travel_is_found_by_one_of_its_pickup_points(self):
        """
        El viaje no sale de donde busca el usuario, pero pasa por ahi. Es el caso
        que da sentido a las paradas intermedias.
        """
        travel = self.travel_from(ALCALA, ATOCHA)
        add_pickup_point(travel, MONCLOA, order=1)

        found_travels = self.search(origin=self.coords(MONCLOA), radius_origin_km=3)

        self.assertEqual(found_travels, [travel])

    def test_a_deleted_pickup_point_does_not_match(self):
        travel = self.travel_from(ALCALA, ATOCHA)
        add_pickup_point(travel, MONCLOA, order=1, is_deleted=True)

        found_travels = self.search(origin=self.coords(MONCLOA), radius_origin_km=3)

        self.assertEqual(found_travels, [])

    def test_a_travel_without_geometry_is_never_matched(self):
        """
        `origin_point` admite null. Un viaje sin coordenadas no puede aparecer en
        una busqueda por cercania, aunque su texto de origen diga otra cosa.
        """
        create_travel(self.driver)   # sin puntos

        found_travels = self.search(origin=self.coords(MONCLOA), radius_origin_km=50)

        self.assertEqual(found_travels, [])

    def test_the_same_travel_is_not_repeated_by_several_matching_stops(self):
        """
        Tres paradas dentro del radio no pueden devolver el viaje tres veces: de
        ahi el `.distinct()` de la consulta.
        """
        travel = self.travel_from(ALCALA, ATOCHA)
        add_pickup_point(travel, MONCLOA, order=1)
        add_pickup_point(travel, SOL, order=2)
        add_pickup_point(travel, INFORMATICA, order=3)

        found_travels = self.search(origin=self.coords(MONCLOA), radius_origin_km=10)

        self.assertEqual(found_travels, [travel])


class DestinationOnlySearchTest(BaseGeoSearchTest):
    """Solo se rellena el destino en el buscador."""

    def test_a_travel_ending_near_the_destination_is_found(self):
        travel = self.travel_from(ALCALA, MONCLOA)

        found_travels = self.search(destination=self.coords(SOL), radius_dest_km=5)

        self.assertEqual(found_travels, [travel])

    def test_a_travel_ending_far_away_is_not_found(self):
        self.travel_from(MONCLOA, ALCALA)

        found_travels = self.search(destination=self.coords(ATOCHA), radius_dest_km=5)

        self.assertEqual(found_travels, [])

    def test_a_travel_is_found_by_a_pickup_point_near_the_destination(self):
        travel = self.travel_from(ALCALA, GETAFE)
        add_pickup_point(travel, ATOCHA, order=1)

        found_travels = self.search(destination=self.coords(ATOCHA), radius_dest_km=3)

        self.assertEqual(found_travels, [travel])


class OriginAndDestinationSearchTest(BaseGeoSearchTest):
    """
    Las dos coordenadas a la vez. Es la rama mas complicada: tres condiciones
    alternativas y dos anotaciones (`Min`/`Max`) sobre el orden de las paradas.
    Se busca de Moncloa a Getafe, que estan a unos 14 km, con radios de 5 km.
    La eleccion no es casual: los dos radios tienen que quedar disjuntos.
    """

    def search_both_ends(self, origin_radius=5, destination_radius=5):
        return self.search(
            origin=self.coords(MONCLOA),
            destination=self.coords(GETAFE),
            radius_origin_km=origin_radius,
            radius_dest_km=destination_radius,
        )

    def test_both_main_points_match(self):
        travel = self.travel_from(MONCLOA, GETAFE)

        self.assertEqual(self.search_both_ends(), [travel])

    def test_the_origin_matches_and_the_destination_is_a_stop(self):
        """Rama `cond_main_origin`: sale de donde quiero y pasa por mi destino."""
        travel = self.travel_from(MONCLOA, ALCALA)
        add_pickup_point(travel, GETAFE, order=1)

        self.assertEqual(self.search_both_ends(), [travel])

    def test_the_destination_matches_and_the_origin_is_a_stop(self):
        """Rama `cond_main_dest`: pasa por donde estoy y acaba donde quiero."""
        travel = self.travel_from(ALCALA, GETAFE)
        add_pickup_point(travel, MONCLOA, order=1)

        self.assertEqual(self.search_both_ends(), [travel])

    def test_both_are_intermediate_stops_in_the_right_order(self):
        """
        Rama `cond_stops`: ni el origen ni el destino del viaje me sirven, pero el
        viaje pasa primero por donde estoy y despues por donde voy.
        """
        travel = self.travel_from(ALCALA, ATOCHA)
        add_pickup_point(travel, MONCLOA, order=1)
        add_pickup_point(travel, GETAFE, order=2)

        self.assertEqual(self.search_both_ends(), [travel])

    def test_the_order_of_the_stops_matters(self):
        """
        El mismo viaje, con las mismas dos paradas, pero al reves: pasa por mi
        destino ANTES que por mi origen. No me sirve, porque no puedo subirme en
        Moncloa y bajarme en Getafe si el coche ya paso por Getafe.

        Es lo que fija `min_orig_stop_order < max_dest_stop_order`. Sin esa
        comparacion el viaje apareceria como valido.
        """
        travel = self.travel_from(ALCALA, ATOCHA)
        add_pickup_point(travel, GETAFE, order=1)    # mi destino, primero
        add_pickup_point(travel, MONCLOA, order=2)   # mi origen, despues

        self.assertEqual(self.search_both_ends(), [])

    def test_a_travel_that_only_matches_the_origin_is_not_returned(self):
        """Con las dos coordenadas rellenas, cuadrar solo una no basta."""
        self.travel_from(MONCLOA, ALCALA)

        self.assertEqual(self.search_both_ends(), [])

    def test_a_travel_that_only_matches_the_destination_is_not_returned(self):
        self.travel_from(ALCALA, GETAFE)

        self.assertEqual(self.search_both_ends(), [])

    def test_each_radius_applies_to_its_own_end(self):
        """
        Un viaje de Moncloa a Atocha: el origen cuadra siempre, y el destino solo
        entra si el radio de destino es lo bastante amplio para llegar a Getafe
        (unos 11 km). El radio de origen no influye.
        """
        travel = self.travel_from(MONCLOA, ATOCHA)

        self.assertEqual(self.search_both_ends(destination_radius=5), [])
        self.assertEqual(self.search_both_ends(destination_radius=20), [travel])


class GeoSortingTest(BaseGeoSearchTest):
    """Ordenacion por distancia, que depende de las anotaciones `Distance`."""

    def test_sorting_by_origin_puts_the_closest_first(self):
        far = self.travel_from(GETAFE, ATOCHA)
        near = self.travel_from(SOL, ATOCHA)

        found_travels = self.search(
            origin=self.coords(MONCLOA), radius_origin_km=30, sort_by='origin'
        )

        self.assertEqual(found_travels, [near, far])

    def test_sorting_by_destination_puts_the_closest_first(self):
        far = self.travel_from(ALCALA, GETAFE)
        near = self.travel_from(ALCALA, SOL)

        found_travels = self.search(
            destination=self.coords(MONCLOA), radius_dest_km=30, sort_by='destination'
        )

        self.assertEqual(found_travels, [near, far])

    def test_sorting_by_origin_is_ignored_without_an_origin(self):
        """
        `sort_by='origin'` sin coordenada de origen no puede ordenar por
        distancia: cae al orden por fecha. Sin ese `and has_origin` la consulta
        reventaria al ordenar por una anotacion que no existe.
        """
        first_travel = self.travel_from(MONCLOA, ATOCHA)
        second_travel = self.travel_from(SOL, ATOCHA)
        Travel.objects.filter(pk=second_travel.pk).update(
            travel_date=first_travel.travel_date + __import__('datetime').timedelta(days=1)
        )

        found_travels = self.search(sort_by='origin')

        self.assertEqual(found_travels, [first_travel, second_travel])


class GeoSearchRespectsTheOtherFiltersTest(BaseGeoSearchTest):
    """
    Las condiciones geograficas se combinan con el resto de filtros. Se comprueba
    que no se saltan la exclusion del propio usuario ni los asientos.
    """

    def test_my_own_travel_is_excluded_even_if_it_matches_geographically(self):
        own = create_travel(self.searcher)
        set_travel_points(own, origin=MONCLOA, destination=ATOCHA)

        found_travels = self.search(origin=self.coords(MONCLOA), radius_origin_km=5)

        self.assertEqual(found_travels, [])

    def test_a_full_travel_is_excluded_even_if_it_matches_geographically(self):
        full = create_travel(self.driver, num_seats=3, remaining_seats=0)
        set_travel_points(full, origin=MONCLOA, destination=ATOCHA)

        found_travels = self.search(origin=self.coords(MONCLOA), radius_origin_km=5)

        self.assertEqual(found_travels, [])
