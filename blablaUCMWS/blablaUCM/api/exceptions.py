from rest_framework.exceptions import APIException

class CustomAPIException(APIException):
    status_code = 400

    def __init__(self, code, message, status_code=None):
        if status_code:
            self.status_code = status_code

        detail = {
            "error": {
                "code": code,
                "message": message
            }
        }

        super().__init__(detail)

