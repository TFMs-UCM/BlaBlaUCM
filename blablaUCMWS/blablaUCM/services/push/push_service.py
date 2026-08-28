import logging
from typing import Optional

import firebase_admin
from decouple import config
from django.utils import timezone
from firebase_admin import credentials, messaging

logger = logging.getLogger(__name__)


# Inicializa la app de Firebase la primera vez que se necesita
def _ensure_initialized():
    if not firebase_admin._apps: # Solo se inicializa si no hay apps ya inicializadas
        cred = credentials.Certificate(config('FIREBASE_CREDENTIALS_PATH'))
        firebase_admin.initialize_app(cred)

# Clase para enviar notificaciones push a los usuarios
class PushNotification:
    
    #Funcion para enviar una notificacion push a todos los dispositivos de un usuario
    @staticmethod
    def send_to_user(user, title: str, body: str, notification_type: str = "notification", data: Optional[dict] = None):
        
        devices = user.devices.filter(is_deleted=False)
        if not devices.exists():# Si no hay dispositivos, no se hace nada
            return
        try:
            _ensure_initialized() # Inicializa Firebase Admin si no estaba inicializado
        except Exception as e:
            logger.error(f"Could not initialize Firebase Admin: {str(e)}")
            return

        for device in devices: # Por cada uno de los dispositivos, se envia la notificacion push
            message = messaging.Message(
                notification=messaging.Notification(title=title, body=body),
                data={"type": notification_type, **{k: str(v) for k, v in (data or {}).items()}},
                token=device.fcm_token,
            )

            try:
                messaging.send(message)
            except firebase_admin.exceptions.NotFoundError:
                # Si el token de FCM ya no es valido, se marca el dispositivo como borrado
                logger.info(f"FCM token invalid, marking device as deleted {device.id}")
                device.is_deleted = True
                device.deleted_at = timezone.now()
                device.save()
            except Exception as e:
                logger.error(f"Error sending push notification to device {device.id}: {str(e)}")
