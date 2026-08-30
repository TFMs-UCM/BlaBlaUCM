"""
Pruebas de las SEÑALES de Django
    users/signals.py   -> borrado del fichero de la foto anterior
                       -> envio del push al crear una Notifications
"""
import os
import tempfile
import weakref
from unittest.mock import patch

from django.test import TestCase, override_settings

from travels.tests.factories import create_user
from users.models import Notifications
from users.tests.test_user_profile_characterization import build_image

TEMP_MEDIA = override_settings(MEDIA_ROOT=tempfile.mkdtemp())


def connected_modules(signal):
    """
    Modulos de los receptores vivos de una señal.

    Se indexa por posicion en vez de desempaquetar: Django guarda cada entrada
    como `(clave, receptor)` en unas versiones y `(clave, receptor, es_async)` en
    otras, y desempaquetar a dos nombres revienta con las segundas.
    """
    modules = set()
    for receiver_entry in signal.receivers:
        reference = receiver_entry[1]
        # Los receptores debiles se guardan como weakref y hay que resolverlos
        function = reference() if isinstance(reference, weakref.ReferenceType) else reference
        if function is not None:
            modules.add(getattr(function, '__module__', None))
    return modules


# Se captura AL CARGAR ESTE FICHERO, antes de que ninguna prueba pueda importar
# nada: el decorador `@receiver` registra al importar el modulo, asi que
# cualquier prueba que importase un modulo de señales conectaria sus receptores y
# falsearia el resultado de las demas. Es justo lo que paso al escribirlas, con
# el `travels/signals.py` que despues se borro.
_PRE_SAVE_RECEIVERS = connected_modules(__import__(
    'django.db.models.signals', fromlist=['pre_save']).pre_save)
_POST_DELETE_RECEIVERS = connected_modules(__import__(
    'django.db.models.signals', fromlist=['post_delete']).post_delete)


class PushOnNotificationTest(TestCase):
    """
    `post_save` sobre `Notifications`. Explica por que las pruebas que crean
    notificaciones no fallan sin Firebase: `PushNotification.send_to_user` sale
    antes de inicializar nada si el usuario no tiene dispositivos.
    """

    def setUp(self):
        self.user = create_user("avisado")

    @patch('users.signals.PushNotification.send_to_user')
    def test_creating_a_notification_sends_a_push(self, send_push):
        Notifications.objects.create(id_user=self.user, content="Tienes una solicitud")

        send_push.assert_called_once()
        self.assertEqual(send_push.call_args.kwargs['user'], self.user)
        self.assertEqual(send_push.call_args.kwargs['body'], "Tienes una solicitud")

    @patch('users.signals.PushNotification.send_to_user')
    def test_updating_a_notification_does_not_send_a_push(self, send_push):
        """
        `created` es lo que distingue el alta de la actualizacion. Sin esa
        comprobacion, marcar una notificacion como leida volveria a avisar.
        """
        notification = Notifications.objects.create(id_user=self.user, content="Hola")
        send_push.reset_mock()

        notification.read = True
        notification.save()

        send_push.assert_not_called()

    @patch('users.signals.PushNotification.send_to_user')
    def test_bulk_create_does_not_send_pushes(self, send_push):
        """
        `bulk_create` **no dispara `post_save`**. Importa porque el comando
        `finish_travels` crea sus avisos asi: se guardan en la base pero no llega
        ninguna notificacion push al movil.
        """
        Notifications.objects.bulk_create([
            Notifications(id_user=self.user, content="Uno"),
            Notifications(id_user=self.user, content="Dos"),
        ])

        self.assertEqual(Notifications.objects.count(), 2)
        send_push.assert_not_called()


@TEMP_MEDIA
class ProfilePictureFilesTest(TestCase):
    """
    `pre_save` y `post_delete` sobre `Users`: borran del disco el fichero de la
    foto anterior para que no se acumulen imagenes huerfanas.
    """

    def setUp(self):
        self.user = create_user("con_foto")
        self.user.profile_picture = build_image("primera.png")
        self.user.save()
        self.old_path = self.user.profile_picture.path

    def test_the_old_file_is_removed_when_the_picture_changes(self):
        self.assertTrue(os.path.isfile(self.old_path))

        self.user.profile_picture = build_image("segunda.png")
        self.user.save()

        self.assertFalse(os.path.isfile(self.old_path))
        self.assertTrue(os.path.isfile(self.user.profile_picture.path))

    def test_saving_without_touching_the_picture_keeps_the_file(self):
        self.user.name = "Otro nombre"
        self.user.save()

        self.assertTrue(os.path.isfile(self.old_path))

    def test_a_hard_delete_removes_the_file(self):
        """
        `post_delete` solo salta con un borrado **duro**. Como el proyecto usa
        borrado logico casi en todas partes, en la practica esta señal apenas se
        dispara y los ficheros de las cuentas "borradas" se quedan en el disco.
        """
        path = self.user.profile_picture.path

        self.user.delete()

        self.assertFalse(os.path.isfile(path))

    def test_a_soft_delete_keeps_the_file_on_disk(self):
        """Contraste del caso anterior: es lo que pasa de verdad al borrar cuentas."""
        self.user.is_deleted = True
        self.user.save()

        self.assertTrue(os.path.isfile(self.old_path))


class TravelsSignalsRemovedTest(TestCase):
    def test_the_travels_signals_module_no_longer_exists(self):
        import importlib.util

        self.assertIsNone(importlib.util.find_spec('travels.signals'))

    def test_no_module_of_travels_connects_signals(self):
        """
        Mas amplio que mirar solo `travels.signals`: ningun modulo de la app
        `travels` debe estar conectado a estas dos señales.
        """
        for modules in (_PRE_SAVE_RECEIVERS, _POST_DELETE_RECEIVERS):
            for module in modules:
                with self.subTest(module=module):
                    self.assertFalse((module or "").startswith('travels.'))

    def test_the_users_signals_are_the_ones_connected(self):
        """Contraparte: borrar la copia no ha tocado las señales que si funcionan."""
        self.assertIn('users.signals', _PRE_SAVE_RECEIVERS)
        self.assertIn('users.signals', _POST_DELETE_RECEIVERS)

    def test_the_travels_app_still_does_not_override_ready(self):
        """
        El mecanismo que mantenia el modulo desconectado. Se conserva porque es
        lo que evita que una copia futura se active sin querer.
        """
        from django.apps import apps

        config = apps.get_app_config('travels')

        # `ready` existe siempre, viene de AppConfig; lo que no hay es sobrescritura
        self.assertNotIn('ready', vars(type(config)))
        self.assertIn('ready', vars(type(apps.get_app_config('users'))))
