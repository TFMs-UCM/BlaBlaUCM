"""
Excepciones de dominio del subsistema de usuarios.
El servicio las lanza y es el view el que las traduce a su ErrorCode y a su Response
"""

# Error de negocio de los usuarios, del que heredan todos los demas
class UserDomainError(Exception):
    pass

# No existe un usuario activo con ese nombre de usuario o correo
class UserNotFoundError(UserDomainError):
    pass

# La contraseña actual aportada no coincide con la que tiene el usuario
class IncorrectPasswordError(UserDomainError):
    pass

# El usuario no tiene ningun viaje proximo que devolver
class NoUpcomingTravelsError(UserDomainError):
    pass

# La solicitud que se quiere valorar no existe o no esta en estado 'validated'
class RequestTravelNotValidatedError(UserDomainError):
    pass


# Falta el estado 'unvalidated' en el catalogo, no se puede cerrar la valoracion
class RequestStatusMissingError(UserDomainError):
    pass

# El vehiculo no tiene asientos suficientes para los viajes activos que ya tiene
class VehicleSeatsInsufficientError(UserDomainError):
    pass

# El vehiculo no se puede borrar porque tiene viajes activos asociados
class VehicleHasActiveTravelsError(UserDomainError):
    pass

# Error de negocio de la autenticacion, del que heredan todos los demas
class AuthDomainError(Exception):
    pass

# El codigo no coincide, o la cuenta no tenia ninguno pendiente
class InvalidTokenError(AuthDomainError):
    pass

# El codigo existia pero ya ha caducado
class TokenExpiredError(AuthDomainError):
    pass

# No se ha podido enviar el correo de verificacion
class EmailDeliveryError(AuthDomainError):
    pass

# Google no ha dado por bueno el id_token
class InvalidGoogleTokenError(AuthDomainError):
    pass

# El payload de Google no trae correo, que es el dato con el que se identifica
class GoogleEmailMissingError(AuthDomainError):
    pass

# El proveedor externo trae correo, pero no lo da por verificado
class UnverifiedEmailError(AuthDomainError):
    pass

# Ya hay una cuenta activa con ese correo
class EmailAlreadyRegisteredError(AuthDomainError):
    pass

# El correo no pertenece a ninguno de los dominios admitidos (ALLOWED_DOMAINS)
class EmailDomainNotAllowedError(AuthDomainError):
    pass

# Ya hay una cuenta activa con ese nombre de usuario
class UsernameAlreadyTakenError(AuthDomainError):
    pass

# El nombre de usuario no cumple el formato admitido
class InvalidUsernameError(AuthDomainError):
    pass

# El codigo de tipo de usuario no existe en el catalogo
class InvalidUserTypeError(AuthDomainError):
    pass