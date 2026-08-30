"""
Pruebas de REGRESION DE SEGURIDAD sobre las fotos de perfil
"""
import io
import os
import tempfile

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from rest_framework import status
from rest_framework.test import APITestCase

from travels.tests.factories import create_user
from users.models import Users

TEMP_MEDIA_ROOT = tempfile.mkdtemp()
TEMP_MEDIA = override_settings(MEDIA_ROOT=TEMP_MEDIA_ROOT)


def real_png(name):
    """
    Un PNG **valido**, para que Pillow lo acepte. Es lo que hace interesante la
    prueba: el contenido esta bien y lo unico sospechoso es el nombre.
    """
    from PIL import Image

    buffer = io.BytesIO()
    Image.new('RGB', (1, 1), color='red').save(buffer, format='PNG')
    return SimpleUploadedFile(name, buffer.getvalue(), content_type='image/png')


@TEMP_MEDIA
class PathTraversalTest(APITestCase):
    """
    El nombre no puede sacarte del directorio de las fotos.
    """

    def setUp(self):
        self.user = create_user("dueño")
        self.client.force_authenticate(user=self.user)

        self.directory = os.path.join(TEMP_MEDIA_ROOT, 'profile_pics')
        os.makedirs(self.directory, exist_ok=True)
        with open(os.path.join(self.directory, 'foto.png'), 'wb') as f:
            f.write(b'\x89PNG\r\n\x1a\n' + b'contenido de prueba')

        # Un fichero FUERA del directorio, que es lo que se intenta alcanzar
        self.secret = os.path.join(TEMP_MEDIA_ROOT, 'secreto.txt')
        with open(self.secret, 'w') as f:
            f.write("esto no se puede servir")

    def get(self, filename):
        return self.client.get(f"/api/v1/media/profile_pics/{filename}")

    def test_a_backslash_does_not_escape_the_directory(self):
        """
        El caso que si funcionaba en Windows: `os.path.join` trata `\\` como
        separador alli, y el convertidor `<str:>` de la URL solo bloquea `/`.
        """
        response = self.get('..\\secreto.txt')

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertNotIn(b'esto no se puede servir', response.content)

    def test_a_dotdot_name_is_rejected(self):
        response = self.get('..')

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_an_absolute_windows_path_is_rejected(self):
        response = self.get('C:\\Windows\\win.ini')

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_a_missing_file_looks_exactly_like_a_rejected_one(self):
        """
        Las dos respuestas tienen que ser indistinguibles: si el intento de
        salirse diera algo distinto de "aqui no hay nada", eso ya seria una pista.
        """
        rejected = self.get('..\\secreto.txt')
        missing = self.get('no-existe.png')

        self.assertEqual(rejected.status_code, missing.status_code)

    def test_a_normal_picture_is_still_served(self):
        # Contrapartida obligada: el endurecimiento no puede romper el uso normal
        response = self.get('foto.png')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn(b'contenido de prueba', response.content)

    def test_the_response_says_not_to_sniff_the_type(self):
        response = self.get('foto.png')

        self.assertEqual(response['X-Content-Type-Options'], 'nosniff')


@TEMP_MEDIA
class ExtensionAllowlistTest(APITestCase):
    """
    La extension decide el `Content-Type` con el que se sirve la foto, asi que no
    puede elegirla quien la sube.
    """

    def setUp(self):
        self.user = create_user("dueño")
        self.client.force_authenticate(user=self.user)
        self.url = f"/api/v1/users/{self.user.id}/upload-profile_picture/"

    def upload(self, name):
        return self.client.patch(
            self.url, {'profile_picture': real_png(name)}, format='multipart'
        )

    def test_an_html_name_is_rejected_even_with_a_valid_image_inside(self):
        """
        El caso que importa: la imagen es un PNG de verdad y pasa la verificacion
        de Pillow. Lo unico peligroso es el nombre, que decidiria que el fichero
        se sirve como `text/html`.
        """
        response = self.upload('poliglota.html')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.user.refresh_from_db()
        self.assertFalse(self.user.profile_picture)

    def test_an_svg_name_is_rejected(self):
        response = self.upload('vector.svg')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_a_name_without_extension_is_rejected(self):
        response = self.upload('sinextension')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_the_allowed_formats_still_work(self):
        for name in ('foto.png', 'foto.jpg', 'foto.jpeg', 'foto.gif', 'foto.webp'):
            with self.subTest(name=name):
                response = self.upload(name)
                self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_the_extension_is_case_insensitive(self):
        response = self.upload('FOTO.PNG')

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_the_stored_name_keeps_a_safe_extension(self):
        self.upload('foto.png')

        self.user.refresh_from_db()
        self.assertTrue(self.user.profile_picture.name.endswith('.png'))
        # El nombre guardado es un UUID, no el que mando el cliente
        self.assertNotIn('foto', os.path.basename(self.user.profile_picture.name))


class ProfilePathHelperTest(APITestCase):
    """
    La ultima linea de defensa: `user_profile_path` es quien decide el nombre con
    el que queda el fichero en disco, y no puede escribir una extension peligrosa
    aunque el validador desaparezca.
    """

    def test_a_dangerous_extension_falls_back_to_a_safe_one(self):
        from users.models import user_profile_path

        path = user_profile_path(Users(), 'poliglota.html')

        self.assertTrue(path.endswith('.jpg'))
        self.assertNotIn('.html', path)

    def test_an_allowed_extension_is_kept(self):
        from users.models import user_profile_path

        self.assertTrue(user_profile_path(Users(), 'x.webp').endswith('.webp'))
