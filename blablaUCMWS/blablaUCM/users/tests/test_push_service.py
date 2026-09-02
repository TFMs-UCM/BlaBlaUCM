"""
Pruebas del ENVIO DE NOTIFICACIONES PUSH (`services/push/push_service.py`).
"""
from unittest.mock import patch

import firebase_admin
from django.test import TestCase

from travels.tests.factories import create_user
from users.models import Device
from users.services.user_service import UserService
from services.push.push_service import PushNotification


class BasePushTest(TestCase):

    def setUp(self):
        self.user = create_user("piloto")
        self.device = Device.objects.create(
            id_user=self.user, fcm_token="token-del-movil", platform="android"
        )

    def send(self, side_effect=None):
        """Manda una notificacion con Firebase sustituido por completo."""
        with patch('services.push.push_service._ensure_initialized'), \
             patch('services.push.push_service.messaging.send', side_effect=side_effect) as send_mock:
            PushNotification.send_to_user(self.user, "titulo", "cuerpo")
        return send_mock


class DevicePruningTest(BasePushTest):

    def test_an_invalid_token_soft_deletes_the_device(self):
        """
        Antes se hacia `device.delete()`, un borrado duro en un proyecto que en
        todo lo demas marca `is_deleted`.
        """
        self.send(side_effect=firebase_admin.exceptions.NotFoundError("token no registrado"))

        self.device.refresh_from_db()
        self.assertTrue(self.device.is_deleted)
        self.assertIsNotNone(self.device.deleted_at)

    def test_the_pruned_device_stops_receiving_pushes(self):
        """
        La contrapartida de marcar en vez de borrar: si `send_to_user` no
        filtrara por `is_deleted`, la fila retirada seguiria recibiendo intentos.
        """
        self.send(side_effect=firebase_admin.exceptions.NotFoundError("token no registrado"))

        send_mock = self.send()

        send_mock.assert_not_called()

    def test_the_same_device_can_register_again(self):
        """
        El detalle que hace seguro el borrado logico aqui, y que en otra tabla lo
        haria imposible: `fcm_token` es unico **sin condicion**, asi que si la
        fila se conservara marcada y `register_device` creara una nueva, chocaria
        con la restriccion. Funciona porque `register_device` hace
        `update_or_create` y revive la fila existente.
        """
        self.send(side_effect=firebase_admin.exceptions.NotFoundError("token no registrado"))

        UserService.register_device(self.user, "token-del-movil", "android")

        self.assertEqual(Device.objects.filter(fcm_token="token-del-movil").count(), 1)
        self.device.refresh_from_db()
        self.assertFalse(self.device.is_deleted)

    def test_any_other_error_leaves_the_device_alone(self):
        """
        Un fallo de red o una caida de Firebase no significan que el token sea
        invalido: retirar el dispositivo ahi dejaria al usuario sin avisos hasta
        que reinstalara la app.
        """
        self.send(side_effect=RuntimeError("Firebase no responde"))

        self.device.refresh_from_db()
        self.assertFalse(self.device.is_deleted)


class SendToUserTest(BasePushTest):

    def test_a_user_without_devices_does_not_touch_firebase(self):
        """
        Sale antes incluso de inicializar Firebase. Es lo que permite que las
        pruebas del resto del proyecto creen notificaciones sin credenciales.
        """
        Device.objects.all().delete()

        with patch('services.push.push_service._ensure_initialized') as init:
            PushNotification.send_to_user(self.user, "titulo", "cuerpo")

        init.assert_not_called()

    def test_one_message_per_device(self):
        Device.objects.create(
            id_user=self.user, fcm_token="token-de-la-tablet", platform="ios"
        )

        send_mock = self.send()

        self.assertEqual(send_mock.call_count, 2)

    def test_a_failure_on_one_device_does_not_stop_the_rest(self):
        """
        Los dispositivos se recorren en bucle: sin el try dentro del bucle, el
        primer token caducado dejaria sin aviso a todos los demas.
        """
        Device.objects.create(
            id_user=self.user, fcm_token="token-de-la-tablet", platform="ios"
        )

        send_mock = self.send(
            side_effect=[firebase_admin.exceptions.NotFoundError("caducado"), None]
        )

        self.assertEqual(send_mock.call_count, 2)
