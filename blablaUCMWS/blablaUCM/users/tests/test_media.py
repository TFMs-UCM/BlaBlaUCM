"""
Pruebas del endpoint que sirve las FOTOS DE PERFIL.
    GET /api/v1/media/profile_pics/{filename}
"""
import os
import tempfile

from django.test import override_settings
from rest_framework import status
from rest_framework.test import APITestCase

from travels.tests.factories import create_user

TEMP_MEDIA_ROOT = tempfile.mkdtemp()
TEMP_MEDIA = override_settings(MEDIA_ROOT=TEMP_MEDIA_ROOT)

@TEMP_MEDIA
class ProfilePictureServingTest(APITestCase):

    def setUp(self):
        self.user = create_user("dueño")
        self.client.force_authenticate(user=self.user)

        # Se deja un fichero real en el sitio donde el endpoint lo busca
        self.directory = os.path.join(TEMP_MEDIA_ROOT, 'profile_pics')
        os.makedirs(self.directory, exist_ok=True)
        self.path = os.path.join(self.directory, 'foto.png')
        with open(self.path, 'wb') as f:
            f.write(b'\x89PNG\r\n\x1a\n' + b'contenido de prueba')

    def get(self, filename):
        return self.client.get(f"/api/v1/media/profile_pics/{filename}")

    def test_an_existing_picture_is_served(self):
        response = self.get('foto.png')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response['Content-Type'], 'image/png')
        self.assertIn(b'contenido de prueba', response.content)

    def test_the_cache_header_is_set(self):
        response = self.get('foto.png')

        self.assertEqual(response['Cache-Control'], 'max-age=3600')

    def test_a_missing_file_returns_404(self):
        response = self.get('no_existe.png')

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_an_unknown_extension_falls_back_to_octet_stream(self):
        with open(os.path.join(self.directory, 'raro.xyzzy'), 'wb') as f:
            f.write(b'datos')

        response = self.get('raro.xyzzy')

        self.assertEqual(response['Content-Type'], 'application/octet-stream')

    def test_it_requires_authentication(self):
        """
        Es el motivo de que exista este endpoint en vez de servir `/media/` con el
        servidor web: las fotos de perfil no son publicas.
        """
        self.client.force_authenticate(user=None)

        response = self.get('foto.png')

        self.assertIn(
            response.status_code,
            (status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN),
        )

    def test_any_authenticated_user_can_fetch_any_picture(self):
        self.client.force_authenticate(user=create_user("cualquiera"))

        response = self.get('foto.png')

        self.assertEqual(response.status_code, status.HTTP_200_OK)


@TEMP_MEDIA
class PathTraversalTest(APITestCase):

    def setUp(self):
        self.client.force_authenticate(user=create_user("curioso"))
        # Un fichero fuera de profile_pics, que no deberia poder alcanzarse
        with open(os.path.join(TEMP_MEDIA_ROOT, 'secreto.txt'), 'wb') as f:
            f.write(b'contenido secreto')

    def test_a_path_with_slashes_does_not_match_the_route(self):
        response = self.client.get("/api/v1/media/profile_pics/../secreto.txt")

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertNotIn(b'contenido secreto', response.content)

    def test_an_encoded_slash_does_not_match_either(self):
        response = self.client.get("/api/v1/media/profile_pics/..%2Fsecreto.txt")

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertNotIn(b'contenido secreto', response.content)

    def test_dots_without_separators_are_harmless(self):
        response = self.client.get("/api/v1/media/profile_pics/....secreto.txt")

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)


@TEMP_MEDIA
class ProfilePictureValidatorsTest(APITestCase):

    def setUp(self):
        self.user = create_user("dueño")
        self.client.force_authenticate(user=self.user)

    def upload(self, file_handle):
        return self.client.patch(
            f"/api/v1/users/{self.user.id}/upload-profile_picture/",
            {'profile_picture': file_handle},
            format='multipart',
        )

    @staticmethod
    def _png(size_bytes=None):
        """
        Un PNG de 1x1 valido, opcionalmente inflado hasta el tamaño que se pida.

        Se rellena con un bloque al final: Pillow lee la imagen de la cabecera y
        no le molesta la cola, asi que sirve para superar el limite de tamaño sin
        dejar de ser una imagen de verdad. Si se mandara basura, la rechazaria
        `validate_image` y la prueba pasaria por el motivo equivocado.
        """
        from io import BytesIO

        from django.core.files.uploadedfile import SimpleUploadedFile
        from PIL import Image

        buffer = BytesIO()
        Image.new('RGB', (1, 1), color='red').save(buffer, format='PNG')
        content = buffer.getvalue()

        if size_bytes and len(content) < size_bytes:
            content += b'\x00' * (size_bytes - len(content))

        return SimpleUploadedFile('foto.png', content, content_type='image/png')

    def test_a_picture_over_two_megabytes_is_rejected(self):
        response = self.upload(self._png(size_bytes=3 * 1024 * 1024))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_a_picture_under_two_megabytes_is_accepted(self):
        """
        Contrapartida obligatoria: sin ella, el limite se "aprobaria" rechazando
        cualquier subida.
        """
        response = self.upload(self._png())

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_a_text_file_renamed_to_png_is_rejected(self):
        """
        Lo que de verdad valida el contenido es Pillow, no la extension ni el
        `content_type`, que lo escribe el cliente y no prueba nada.
        """
        from django.core.files.uploadedfile import SimpleUploadedFile

        fake = SimpleUploadedFile('foto.png', b'esto es texto plano', content_type='image/png')

        response = self.upload(fake)

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_the_rejection_is_a_field_error_and_not_a_500(self):
        response = self.upload(self._png(size_bytes=3 * 1024 * 1024))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertNotEqual(response.status_code, status.HTTP_500_INTERNAL_SERVER_ERROR)