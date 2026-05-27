from rest_framework.exceptions import APIException

# Clase para lanzar una excepcion personalizada de la API
class CustomAPIException(APIException):
    status_code = 400 # Se lanza el error 400 por defecto

    def __init__(self, code, message, status_code=None):
        if status_code: # Si se pasa el status_code se asigna
            self.status_code = status_code
        # Se crea el detalle del error con el codigo y mensaje
        detail = {
            "error": {
                "code": code,
                "message": message
            }
        }

        super().__init__(detail)

