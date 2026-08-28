"""
Exige el formato de USERNAME_REGEX en el nombre de usuario y comprueba que no
queden cuentas anteriores a la regla con una arroba en el nombre
"""
import logging
import re

import django.core.validators
from django.db import migrations, models

logger = logging.getLogger(__name__)

# Copia literal de lo que tenia el modelo al escribir esta migracion. No se
# importa de `users.models` a proposito: una migracion describe un estado pasado
# y no puede cambiar sola cuando cambie el modelo
USERNAME_REGEX = r'^[\w.-]{3,20}$'
USERNAME_ERROR_MESSAGE = (
    "El nombre de usuario debe tener entre 3 y 20 caracteres y solo puede "
    "contener letras, numeros, puntos, guiones y guiones bajos"
)


def check_existing_usernames(apps, schema_editor):
    Users = apps.get_model('users', 'Users')

    # Las cuentas con arroba en el nombre no pueden iniciar sesion ni recuperar la
    # contraseña, asi que hay que decidir a mano que se hace con cada una. Se para
    # la migracion en vez de arreglarlas solas porque renombrar a alguien sin
    # avisarle no es cosa de un despliegue
    with_at = list(
        Users.objects.filter(is_deleted=False, username__contains='@')
        .values_list('username', flat=True)
    )
    if with_at:
        raise RuntimeError(
            "Hay cuentas activas con una arroba en el nombre de usuario, que a "
            "partir de ahora no se admite.\n"
            "Nombres afectados: " + ", ".join(with_at) + "\n"
            "Esas cuentas ya estaban rotas (el login y la recuperacion de "
            "contraseña buscan por correo en cuanto ven una arroba), hay que "
            "renombrarlas o borrarlas a mano y volver a lanzar la migracion. "
            "Para verlas:\n"
            "  SELECT id_user, username, email FROM users "
            "WHERE is_deleted = false AND username LIKE '%@%';"
        )

    # El resto de incumplimientos (espacios, nombres de menos de 3 caracteres) no
    # rompen nada, la cuenta sigue funcionando. Solo se avisa, y el nombre se
    # corregira la proxima vez que su dueño edite el perfil
    offenders = [
        username
        for username in Users.objects.filter(is_deleted=False).values_list('username', flat=True)
        if not re.match(USERNAME_REGEX, username or '')
    ]
    if offenders:
        logger.warning(
            "Hay %s cuenta(s) activa(s) cuyo nombre de usuario no cumple el "
            "formato nuevo: %s", len(offenders), ", ".join(offenders),
        )


class Migration(migrations.Migration):

    dependencies = [
        ('users', '0014_normalize_emails'),
    ]

    operations = [
        migrations.RunPython(check_existing_usernames, migrations.RunPython.noop),
        migrations.AlterField(
            model_name='users',
            name='username',
            field=models.CharField(
                max_length=20,
                validators=[
                    django.core.validators.RegexValidator(
                        message=USERNAME_ERROR_MESSAGE,
                        regex=USERNAME_REGEX,
                    )
                ],
            ),
        ),
    ]
