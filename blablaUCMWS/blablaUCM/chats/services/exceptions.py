"""
Excepciones de dominio del subsistema de mensajeria.

El servicio las lanza y es el view el que las traduce a su ErrorCode y a su Response
"""


# Error de negocio de los chats, del que heredan todos los demas
class ChatDomainError(Exception):
    pass


# El conductor no puede abandonar el chat de su viaje hasta que este finalice
class DriverCannotLeaveError(ChatDomainError):
    pass
