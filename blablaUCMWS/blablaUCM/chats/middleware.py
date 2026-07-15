from urllib.parse import parse_qs

from channels.middleware import BaseMiddleware
from channels.db import database_sync_to_async
from rest_framework_simplejwt.tokens import AccessToken
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.settings import api_settings

from users.models import Users

# Funcion asincrona para obtener el usaurio a partir de su id
@database_sync_to_async
def get_user(user_id):
    try:
        return Users.objects.get(id=user_id)
    except Users.DoesNotExist:
        return None

# Middleware de autenticacion para los WebSocket
class JWTAuthMiddleware(BaseMiddleware):

    async def __call__(self, scope, receive, send):
        query_string = scope.get('query_string', b'').decode()
        token = parse_qs(query_string).get('token', [None])[0]

        scope['user'] = None

        if token:
            try:
                access_token = AccessToken(token)
                user_id = access_token[api_settings.USER_ID_CLAIM]
                scope['user'] = await get_user(user_id)
            except (TokenError, KeyError):
                scope['user'] = None

        return await super().__call__(scope, receive, send)
