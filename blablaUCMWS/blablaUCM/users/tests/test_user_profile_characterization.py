"""
Pruebas de CARACTERIZACION del perfil de usuario.
    GET    /api/v1/users/  y  /api/v1/users/{id}/
    PATCH  /api/v1/users/{id}/upload-profile_picture/
    DELETE /api/v1/users/{id}/delete-profile_picture/
    POST   /api/v1/users/{id}/change_password/
    GET    /api/v1/users/exist_email/
"""
import io
import tempfile

from PIL import Image
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from rest_framework import status
from rest_framework.test import APITestCase

from api.errors import ErrorCodes
from travels.tests.factories import create_user
from users.models import Users

# Las subidas de imagen escriben a disco: se aisla en un directorio temporal
TEMP_MEDIA = override_settings(MEDIA_ROOT=tempfile.mkdtemp())

def build_image(name="foto.png"):
    """Genera un PNG valido en memoria (ImageField lo valida con Pillow)."""
    buffer = io.BytesIO()
    Image.new("RGB", (10, 10), color="red").save(buffer, format="PNG")
    buffer.seek(0)
    return SimpleUploadedFile(name, buffer.read(), content_type="image/png")


class UserListAndRetrieveTest(APITestCase):

    def setUp(self):
        self.user = create_user("user_one")
        self.other = create_user("user_two")
        self.client.force_authenticate(user=self.user)

    def test_the_list_only_returns_the_caller(self):

        response = self.client.get("/api/v1/users/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['count'], 1)
        self.assertEqual(response.data['results'][0]['username'], self.user.username)

    def test_the_list_does_not_expose_other_users_emails(self):
        """
        El correo de los demas era lo mas sensible que se filtraba por aqui.
        """
        response = self.client.get("/api/v1/users/")

        emails = {row['email'] for row in response.data['results']}
        self.assertNotIn(self.other.email, emails)
        self.assertEqual(emails, {self.user.email})

    def test_retrieve_returns_the_caller_own_profile(self):
        response = self.client.get(f"/api/v1/users/{self.user.id}/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['username'], self.user.username)

    def test_another_users_profile_is_not_reachable(self):
        """
        Se devuelve 404 y no 403 a proposito: asi no se confirma si el id
        existe. El filtrado esta en `get_queryset`, de modo que `get_object`
        simplemente no lo encuentra.
        """
        response = self.client.get(f"/api/v1/users/{self.other.id}/")

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_saving_the_profile_without_changing_the_username_works(self):
        """
        `UserSerializer.validate` comprobaba la unicidad sin excluirse a si mismo,
        asi que mandar el propio nombre de usuario sin cambiarlo daba 409. La app
        manda `{"username": ...}` al guardar ese campo del perfil.
        """
        response = self.client.patch(
            f"/api/v1/users/{self.user.id}/",
            {'username': self.user.username},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_changing_the_username_to_a_free_one_works(self):
        response = self.client.patch(
            f"/api/v1/users/{self.user.id}/", {'username': "nombre_libre"}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertEqual(self.user.username, "nombre_libre")

    def test_changing_the_username_to_a_taken_one_is_rejected(self):
        """Contraparte: el arreglo no puede haberse llevado por delante la regla."""
        response = self.client.patch(
            f"/api/v1/users/{self.user.id}/", {'username': self.other.username}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)

    def test_the_username_of_a_deleted_account_can_be_reused(self):
        """
        La comprobacion no descartaba las cuentas borradas, asi
        que una cuenta eliminada bloqueaba su nombre para siempre — al contrario
        que en el registro y en `verify_user`, que si las descartaban.
        """
        self.other.is_deleted = True
        self.other.save()

        response = self.client.patch(
            f"/api/v1/users/{self.user.id}/",
            {'username': self.other.username},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_a_deleted_user_loses_access(self):
        """
        `Users.is_authenticated` es una propiedad sobrescrita que devuelve
        `is_verify and not is_deleted`: al marcar la cuenta como borrada deja de
        estar autenticada, asi que no llega ni al queryset.
        """
        self.user.is_deleted = True
        self.user.save()

        response = self.client.get("/api/v1/users/")

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)


@TEMP_MEDIA
class ProfilePictureTest(APITestCase):

    def setUp(self):
        self.user = create_user("owner")
        self.intruder = create_user("intruder")
        self.client.force_authenticate(user=self.user)

    def upload(self, user_id, image=None):
        payload = {} if image is None else {'profile_picture': image}
        return self.client.patch(
            f"/api/v1/users/{user_id}/upload-profile_picture/", payload, format='multipart'
        )

    def test_upload_stores_the_picture_and_returns_its_name(self):
        response = self.upload(self.user.id, build_image())

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('name', response.data)

        self.user.refresh_from_db()
        self.assertTrue(self.user.profile_picture)

    def test_upload_without_the_field_returns_400(self):
        response = self.upload(self.user.id)

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.MISSING_REQUIRED_FIELD)

    def test_upload_of_a_non_image_returns_400(self):

        fake = SimpleUploadedFile("virus.txt", b"no soy una imagen", content_type="text/plain")

        response = self.upload(self.user.id, fake)

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.VALIDATION_ERROR)
        self.assertIn('profile_picture', response.data['fields'])

    def test_replacing_someone_elses_picture_is_blocked(self):
        self.client.force_authenticate(user=self.intruder)

        response = self.upload(self.user.id, build_image())

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.user.refresh_from_db()
        self.assertFalse(self.user.profile_picture)

    def test_deleting_someone_elses_picture_is_blocked(self):
        """REGRESION DE SEGURIDAD (ver IMPORTANTE.md §1.6)."""
        self.upload(self.user.id, build_image())
        self.client.force_authenticate(user=self.intruder)

        response = self.client.delete(f"/api/v1/users/{self.user.id}/delete-profile_picture/")

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.user.refresh_from_db()
        self.assertTrue(self.user.profile_picture)

    def test_delete_without_picture_returns_ok(self):
        response = self.client.delete(f"/api/v1/users/{self.user.id}/delete-profile_picture/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn("No profile picture", response.data['message'])

    def test_delete_removes_the_picture(self):
        self.upload(self.user.id, build_image())

        response = self.client.delete(f"/api/v1/users/{self.user.id}/delete-profile_picture/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertFalse(self.user.profile_picture)


class ChangePasswordTest(APITestCase):

    def setUp(self):
        self.user = create_user("owner")
        self.user.set_password("actual")
        self.user.save()
        self.client.force_authenticate(user=self.user)

    def change(self, user_id=None, **payload):
        return self.client.post(
            f"/api/v1/users/{user_id or self.user.id}/change_password/", payload, format='json'
        )

    def test_change_password_with_the_right_current_one(self):
        response = self.change(current_password="actual", new_password="nueva-clave")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("nueva-clave"))

    def test_wrong_current_password_returns_400(self):
        response = self.change(current_password="equivocada", new_password="nueva")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.INVALID_CREDENTIALS)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("actual"))

    def test_missing_fields_return_400(self):
        response = self.change(current_password="actual")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.MISSING_REQUIRED_FIELD)

    def test_changing_someone_elses_password_is_blocked(self):
        """
        Este endpoint nunca fue explotable, pero solo porque exigia la
        contraseña actual: la proteccion era un efecto secundario, no una
        comprobacion de autorizacion. Ahora la cuenta ajena ni se alcanza, asi
        que responde 404 antes de mirar la contraseña.
        """
        victim = create_user("victim")
        victim.set_password("secreta")
        victim.save()

        response = self.change(user_id=victim.id, current_password="adivinada", new_password="nueva")

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        victim.refresh_from_db()
        self.assertTrue(victim.check_password("secreta"))


class ExistEmailTest(APITestCase):

    def setUp(self):
        self.user = create_user("owner")
        self.client.force_authenticate(user=self.user)

    def test_free_email_returns_ok(self):
        response = self.client.get("/api/v1/users/exist_email/?email=libre@ucm.es")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['status'], "OK")

    def test_taken_email_returns_ko(self):
        response = self.client.get(f"/api/v1/users/exist_email/?email={self.user.email}")

        self.assertEqual(response.data['status'], "KO")

    def test_missing_param_returns_400(self):
        response = self.client.get("/api/v1/users/exist_email/")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.MISSING_REQUIRED_FIELD)

    def test_deleted_users_do_not_hold_their_email(self):
        # El usuario borrado no puede ser el autenticado: `is_authenticated`
        # devuelve False en cuanto is_deleted es True, y saldria un 403
        deleted = create_user("borrado")
        deleted.is_deleted = True
        deleted.save()

        response = self.client.get(f"/api/v1/users/exist_email/?email={deleted.email}")

        self.assertEqual(response.data['status'], "OK")
        # La fila sigue existiendo, solo marcada como borrada
        self.assertEqual(Users.objects.filter(email=deleted.email).count(), 1)
