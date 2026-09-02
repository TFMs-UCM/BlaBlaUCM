"""
Manejador de excepciones unico de la API

Antes de esto la API devolvia los errores en tres formatos distintos y el
cliente tenia que saber cual le tocaba segun el endpoint y el tipo de fallo:

    1. La mayoria de endpoints     {"status": "error", "message": ..., "error_code": 6}
    2. CustomAPIException          {"error": {"code": "6", "message": ...}}
    3. Validacion de campo de DRF  {"password": [mensaje]}

El formato 1 es el que construyen a mano las vistas, asi que es el que se va a tomar como ejemplo,
se mantiene la compatibilidad con los otros dos
El nuevo formato es:
    {
        "status": "error",
        "message": "<texto para el usuario>",
        "error_code": <entero>,
        "error": {"code": "<entero>", "message": "<texto>"},   Se mantiene por compatibilidad
        "fields": {"password": ["..."]},                        
        "password": ["..."]                                    Se mantiene por compatibilidad
    }
"""
from django.core.exceptions import ValidationError as DjangoValidationError
from rest_framework import status as http_status
from rest_framework.exceptions import ErrorDetail
from rest_framework.exceptions import ValidationError as DRFValidationError
from rest_framework.views import exception_handler as drf_exception_handler

from api.errors import ErrorCodes

# Codigo de error por defecto segun el codigo HTTP, para lo que no trae uno propio
STATUS_TO_ERROR_CODE = {
    http_status.HTTP_400_BAD_REQUEST: ErrorCodes.VALIDATION_ERROR,
    http_status.HTTP_401_UNAUTHORIZED: ErrorCodes.INVALID_CREDENTIALS,
    http_status.HTTP_403_FORBIDDEN: ErrorCodes.INSUFICIENT_CREDENTIALS,
    http_status.HTTP_404_NOT_FOUND: ErrorCodes.NOT_FOUND,
    http_status.HTTP_405_METHOD_NOT_ALLOWED: ErrorCodes.METHOD_NOT_ALLOWED,
    http_status.HTTP_429_TOO_MANY_REQUESTS: ErrorCodes.TOO_MANY_REQUESTS,
}


# Extrae un texto legible de cualquier forma que tenga el detalle de DRF
def _first_message(detail):
    """
    El detalle puede ser una cadena, una lista de cadenas o un diccionario de
    campo -> lista de cadenas
    """
    if isinstance(detail, dict):
        # Si el diccionario trae un mensaje, es ese
        if 'message' in detail:
            message = _first_message(detail['message'])
            if message:
                return message

        for value in detail.values():
            message = _first_message(value)
            if message:
                return message
        return None
    if isinstance(detail, (list, tuple)):
        for value in detail:
            message = _first_message(value)
            if message:
                return message
        return None
    return str(detail) if detail is not None else None


# Un error de campo con codigo required es un campo que falta, no un formato malo
def _code_from_field_errors(detail):
    for value in detail.values():
        candidates = value if isinstance(value, (list, tuple)) else [value]
        for item in candidates:
            if isinstance(item, ErrorDetail) and item.code == 'required':
                return ErrorCodes.MISSING_REQUIRED_FIELD
    return ErrorCodes.VALIDATION_ERROR


# Saca el codigo de error propio si la excepcion trae uno (CustomAPIException)
def _explicit_error_code(detail):
    if not isinstance(detail, dict):
        return None
    error = detail.get('error')
    if not isinstance(error, dict) or 'code' not in error:
        return None
    try:
        return int(error['code'])
    except (TypeError, ValueError):
        return None


def unified_exception_handler(exc, context):
    """
    Se configura en REST_FRAMEWORK[EXCEPTION_HANDLER].

    Devolver None significa "no lo se manejar", DRF deja entonces que la
    excepcion suba y Django responda un 500. Se mantiene ese comportamiento
    para todo lo que no sea una excepcion de DRF, para no enmascarar fallos de
    programacion como si fueran errores de negocio
    """
    if isinstance(exc, DjangoValidationError):
        detail = exc.message_dict if hasattr(exc, 'message_dict') else exc.messages
        exc = DRFValidationError(detail)

    response = drf_exception_handler(exc, context)
    if response is None:
        return None

    detail = response.data

    # Si ya viene en el formato bueno, no se toca
    if isinstance(detail, dict) and 'error_code' in detail and 'status' in detail:
        return response

    error_code = _explicit_error_code(detail)
    message = _first_message(detail)

    # Errores de validacion de campo: {"password": ["..."], "email": ["..."]}
    field_errors = None
    if error_code is None and isinstance(detail, dict) and 'detail' not in detail:
        field_errors = {key: value for key, value in detail.items() if key != 'error'}
        if field_errors:
            error_code = _code_from_field_errors(field_errors)

    if error_code is None:
        error_code = STATUS_TO_ERROR_CODE.get(
            response.status_code, ErrorCodes.INTERNAL_SERVER_ERROR
        )

    body = {
        "status": "error",
        "message": message,
        "error_code": error_code,
        # Compatibilidad la anterior version que lanzaba el CustomAPIException
        "error": {"code": str(error_code), "message": message},
    }

    if field_errors:
        body["fields"] = field_errors
        # Compatibilidad con la anterior version que leia la clave del campo directamente
        for field, errors in field_errors.items():
            body.setdefault(field, errors)

    response.data = body
    return response
