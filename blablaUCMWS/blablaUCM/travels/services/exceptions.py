"""
Excepciones de dominio de Travel y RequestTravel
El servicio las lanza y es el view el que las traduce a su ErrorCode y a su Response
"""


# Error de negocio de los viajes, del que heredan todos los demas
class TravelDomainError(Exception):
    pass

# No quedan asientos libres en el viaje
class SeatsFullError(TravelDomainError):
    def __init__(self, travel_id=None):
        self.travel_id = travel_id
        super().__init__(f"Travel {travel_id} has no remaining seats.")

# El usuario intenta solicitar plaza en un viaje suyo
class RequestOwnTravelError(TravelDomainError):
    pass

# El usuario ya tiene una solicitud viva en alguno de los viajes indicados
class AlreadyRequestedError(TravelDomainError):
    pass

# El codigo de estado de solicitud recibido no existe
class InvalidRequestStatusError(TravelDomainError):
    def __init__(self, status_code=None):
        self.status_code = status_code
        super().__init__(f"Request status {status_code} is not valid.")

# El estado destino existe, pero el salto desde el actual no esta permitido
class InvalidStatusTransitionError(TravelDomainError):
    def __init__(self, current_status, new_status):
        self.current_status = current_status
        self.new_status = new_status
        super().__init__(
            f"Transition {current_status} -> {new_status} is not allowed."
        )


# El estado existe y la transicion puede ser legitima, pero debe hacerse desde su endpoint correspondiente
class StatusNotRequestableError(TravelDomainError):

    GATEWAY = {
        'validated': "validando al pasajero con su código de validación",
        'unvalidated': "finalizando el viaje",
    }

    def __init__(self, status_code):
        self.status_code = status_code
        self.gateway = self.GATEWAY.get(status_code)
        super().__init__(f"Status {status_code} can not be requested through the API.")

# No existe ningun usuario con ese nombre de usuario
class PassengerNotFoundError(TravelDomainError):
    def __init__(self, username=None):
        self.username = username
        super().__init__(f"Passenger {username} not found.")


# El usuario existe pero no tiene una solicitud aceptada en el viaje
class PassengerNotInTravelError(TravelDomainError):
    def __init__(self, username=None):
        self.username = username
        super().__init__(f"Passenger {username} has no accepted request in this travel.")


# El codigo de validacion no corresponde a ninguna solicitud del viaje
class InvalidValidationCodeError(TravelDomainError):
    def __init__(self, code=None):
        self.code = code
        super().__init__(f"Validation code {code} is not valid.")


# El pasajero ya habia sido validado
class PassengerAlreadyValidatedError(TravelDomainError):
    def __init__(self, username=None):
        self.username = username
        super().__init__(f"Passenger {username} is already validated.")


# El pasajero no esta en estado aceptado, asi que no se puede validar
class PassengerNotAcceptedError(TravelDomainError):
    def __init__(self, username=None):
        self.username = username
        super().__init__(f"Passenger {username} is not in accepted state.")

class TravelIsNotPunctualError(TravelDomainError):
    pass

# No se puede reducir el numero de asientos de un viaje periodico
class PeriodicSeatsReductionError(TravelIsNotPunctualError):
    pass

# No se pueden cambiar los usuarios denegados de un viaje periodico
class PeriodicDeniedUsersError(TravelIsNotPunctualError):
    pass

# No existe el punto de recogida indicado dentro del viaje
class PickUpPointNotFoundError(TravelDomainError):
    def __init__(self, point_id=None):
        self.point_id = point_id
        super().__init__(f"Pickup point {point_id} not found.")


# Se intenta tocar algo que depende de un viaje que no es del usuario
class NotTravelOwnerError(TravelDomainError):
    def __init__(self, travel_id=None):
        self.travel_id = travel_id
        super().__init__(f"Travel {travel_id} does not belong to the caller.")

# Se intenta dejar menos asientos de los que ya estan ocupados
class SeatsBelowOccupiedError(TravelDomainError):
    def __init__(self, seats=None, occupied_seats=None):
        self.seats = seats
        self.occupied_seats = occupied_seats
        super().__init__(f"Cannot set {seats} seats, {occupied_seats} are already occupied.")

# No se puede mover la fecha de un viaje que ya tiene plazas ocupadas
class DateChangeWithOccupiedSeatsError(SeatsBelowOccupiedError):
    pass

# El vehiculo indicado no existe
class VehicleNotFoundError(TravelDomainError):
    pass

# El vehiculo elegido tiene menos plazas de las que necesita el viaje
class VehicleSeatsInsufficientError(TravelDomainError):
    pass

# Igual que el anterior, pero mirando toda la serie periodica
class SeriesVehicleSeatsInsufficientError(VehicleSeatsInsufficientError):
    pass

# Falta la fecha de fin para convertir un viaje en periodico
class EndDateRequiredError(TravelDomainError):
    pass

# El intervalo de periodicidad debe estar entre 1 y 31 dias
class InvalidPeriodicIntervalError(TravelDomainError):
    pass
