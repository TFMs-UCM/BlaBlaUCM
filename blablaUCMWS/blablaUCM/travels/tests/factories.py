"""
Utilidades para construir los datos de las pruebas.

No se usa ninguna libreria externa, son funciones
planas sobre el ORM para no añadir dependencias nuevas al proyecto.
"""
import itertools
from datetime import timedelta

from django.utils import timezone

from travels.models import Travel, TravelStates, RequestStates, RequestTravels
from users.models import Users, UserType, EnvTypes, Vehicles

# Contador para generar valores unicos (username, matricula...) dentro de un mismo test
_counter = itertools.count(1)

def create_user(username=None, user_type='std'):
    """
    Crea un usuario verificado (is_verify=True es necesario para que
    IsAuthenticated lo acepte)
    """
    n = next(_counter)
    username = username or f"user{n}"
    return Users.objects.create(
        username=username,
        email=f"{username}@ucm.es",
        name="Nombre",
        surname1="Apellido",
        user_type=UserType.objects.get(code=user_type),
        is_verify=True,
    )


def create_vehicle(user, seats=4, env_sticker='eco'):
    """`env_sticker` es un codigo de EnvTypes: 'c', 'b', 'eco', 'cero', 'hist'."""
    n = next(_counter)
    return Vehicles.objects.create(
        brand="Seat",
        model="Ibiza",
        license_plate=f"{n:04d}ABC",
        color="Rojo",
        seats=seats,
        id_user=user,
        env_sticker=EnvTypes.objects.get(code=env_sticker),
    )


def create_travel(driver, num_seats=3, remaining_seats=None, state='active',
                  travel_date=None, env_sticker='eco'):
    """
    Crea un viaje puntual del conductor indicado
    """
    if remaining_seats is None:
        remaining_seats = num_seats

    if travel_date is None:
        travel_date = timezone.now() + timedelta(days=3)

    return Travel.objects.create(
        origin="Moncloa",
        destination="Facultad de Informatica",
        duration_minutes=25,
        num_seats=num_seats,
        remaining_seats=remaining_seats,
        travel_date=travel_date,
        creation_user=driver,
        vehicle=create_vehicle(driver, seats=num_seats + 1, env_sticker=env_sticker),
        state=TravelStates.objects.get(code=state),
        is_periodic=False,
    )


def create_periodic_travel(driver, num_seats=3, interval=7, weeks=3):
    """
    Crea el viaje padre de una serie periodica
    """
    start_date = timezone.now() + timedelta(days=3)
    end_date = (start_date + timedelta(days=interval * weeks)).date()

    return Travel.objects.create(
        origin="Moncloa",
        destination="Facultad de Informatica",
        duration_minutes=25,
        num_seats=num_seats,
        remaining_seats=num_seats,
        travel_date=start_date,
        creation_user=driver,
        vehicle=create_vehicle(driver, seats=num_seats + 1),
        state=TravelStates.objects.get(code='active'),
        is_periodic=True,
        periodic_interval=interval,
        end_periodic_date=end_date,
    )


def create_request(travel, passenger, state='pending'):
    return RequestTravels.objects.create(
        id_travel=travel,
        user=passenger,
        status=RequestStates.objects.get(code=state),
    )


# Coordenadas reales de Madrid, en (lat, lng). Las distancias aproximadas entre
# ellas son las que hacen legibles las pruebas del radio de busqueda:
#
#   MONCLOA -> INFORMATICA   ~2 km
#   MONCLOA -> SOL           ~2 km
#   MONCLOA -> ATOCHA        ~4 km
#   MONCLOA -> GETAFE       ~14 km
#   MONCLOA -> ALCALA       ~30 km
MONCLOA = (40.4353, -3.7186)
INFORMATICA = (40.4530, -3.7266)
SOL = (40.4169, -3.7038)
ATOCHA = (40.4065, -3.6892)
GETAFE = (40.3082, -3.7325)
ALCALA = (40.4820, -3.3635)


def as_point(coords):
    """
    Convierte una tupla (lat, lng) en un Point.
    """
    from django.contrib.gis.geos import Point

    lat, lng = coords
    return Point(lng, lat, srid=4326)


def set_travel_points(travel, origin=None, destination=None):
    """Coloca el viaje en el mapa. Las factorias no lo hacen por defecto."""
    if origin is not None:
        travel.origin_point = as_point(origin)
    if destination is not None:
        travel.destination_point = as_point(destination)
    travel.save()
    return travel


def add_pickup_point(travel, coords, order, direction=None, is_deleted=False):
    """Añade una parada intermedia georreferenciada al viaje."""
    from travels.models import PickUpPoints

    return PickUpPoints.objects.create(
        id_travel=travel,
        direction=direction or f"Parada {order}",
        order_in_travel=order,
        point=as_point(coords),
        is_deleted=is_deleted,
    )
