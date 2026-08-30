"""
Normaliza los correos ya guardados y pasa la unicidad a comparar en minusculas
"""
from django.db import migrations, models
from django.db.models import Count, Q
from django.db.models.functions import Lower


def normalize_emails(apps, schema_editor):
    Users = apps.get_model('users', 'Users')

    collisions = (
        Users.objects.filter(is_deleted=False)
        .annotate(normalized=Lower('email'))
        .values('normalized')
        .annotate(total=Count('id'))
        .filter(total__gt=1)
        .order_by('normalized')
    )

    colliding = [row['normalized'] for row in collisions]
    if colliding:
        raise RuntimeError(
            "No se puede normalizar el correo: hay cuentas activas que solo se "
            "diferencian en las mayusculas y quedarian duplicadas.\n"
            "Direcciones afectadas: " + ", ".join(colliding) + "\n"
            "Hay que decidir a mano que cuenta se queda con cada una (borrandola "
            "logicamente o cambiandole el correo) y volver a lanzar la migracion. "
            "Para verlas:\n"
            "  SELECT lower(email), count(*), array_agg(id_user) FROM users "
            "WHERE is_deleted = false GROUP BY lower(email) HAVING count(*) > 1;"
        )

    for pk, email in Users.objects.values_list('pk', 'email').iterator():
        normalized = (email or '').strip().lower()
        if normalized != email:
            Users.objects.filter(pk=pk).update(email=normalized)


class Migration(migrations.Migration):

    dependencies = [
        ('users', '0013_users_sessions_epoch'),
    ]

    operations = [
        migrations.RunPython(normalize_emails, migrations.RunPython.noop),
        migrations.RemoveConstraint(
            model_name='users',
            name='unique_active_email',
        ),
        migrations.AddConstraint(
            model_name='users',
            constraint=models.UniqueConstraint(
                Lower('email'),
                condition=Q(is_deleted=False),
                name='unique_active_email',
            ),
        ),
    ]
