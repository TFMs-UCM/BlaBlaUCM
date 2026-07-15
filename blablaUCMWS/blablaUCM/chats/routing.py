from django.urls import re_path

from chats.consumers import ChatConsumer

# Rutas WebSocket del subsistema de mensajeria
websocket_urlpatterns = [
    re_path(r'^ws/chat/(?P<travel_id>[0-9a-fA-F-]+)/$', ChatConsumer.as_asgi()),
]
