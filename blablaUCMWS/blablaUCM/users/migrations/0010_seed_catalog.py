from django.db import migrations


# Datos de catalogo de la app users, sin ellos la app no funciona, por eso se cargan como migracion de datos
USER_TYPES = [
    # (id_type, code, name)
    (1, 'std',   'student'),
    (2, 'prof',  'professor'),
    (3, 'unStf', 'University Stuff'),
]

ENV_TYPES = [
    # (id_type, code, label)
    (0, 'c',    'C'),
    (1, 'b',    'B'),
    (2, 'eco',  'ECO'),
    (3, 'cero', 'CERO'),
    (4, 'hist', 'Historico'),
    (5, 'all',  ' - '),
]

PREF_TYPES = [
    # (code, description)  -> id autogenerado
    ('smokingAllowed',     'Fumadores permitidos'),
    ('smokeFreeSpace',     'Espacio sin humo'),
    ('alwaysWithMusic',    'Siempre con música'),
    ('loveSilence',        'Adoro el silencio'),
    ('loveToChat',         'Me encanta charlar'),
    ('veryShy',            'Soy muy tímido'),
    ('noAnimals',          'Sin animales, por favor'),
    ('punctualityFirst',   'Puntualidad ante todo'),
    ('flexibleSchedule',   'Flexible con el horario'),
    ('loudMusic',          'Música alta, sin problema'),
    ('softMusic',          'Música suave, por favor'),
    ('likeToSing',         'Me gusta cantar en el coche'),
    ('meetingNewPeople',   'Me encanta conocer gente nueva'),
    ('dontLikeToTalkMuch', 'No me gusta hablar mucho'),
    ('loveToTalk',         'Me encanta hablar'),
]

CRITERIA = [
    # (id, code, description)
    (0, 'driverSkills', 'Driver skills rating'),
    (1, 'punctuality',  'Punctuality rating'),
    (2, 'kindness',     'Kindness rating'),
    (3, 'cleanliness',  'Cleanliness rating'),
    (4, 'flexibility',  'Flexibility rating'),
    (5, 'reliability',  'Reliability rating'),
]


def _resync_sequence(schema_editor, table, pk_col):
    """Realinea la secuencia del pk tras insertar ids explicitos (Postgres)."""
    if schema_editor.connection.vendor != 'postgresql':
        return
    with schema_editor.connection.cursor() as cur:
        cur.execute(
            "SELECT setval(pg_get_serial_sequence(%s, %s), "
            "COALESCE((SELECT MAX(" + pk_col + ") FROM " + table + "), 1))",
            [table, pk_col],
        )


def seed(apps, schema_editor):
    UserType = apps.get_model('users', 'UserType')
    EnvTypes = apps.get_model('users', 'EnvTypes')
    PrefTypes = apps.get_model('users', 'PrefTypes')
    Criteria = apps.get_model('users', 'Criteria')

    for id_type, code, name in USER_TYPES:
        UserType.objects.get_or_create(
            code=code, defaults={'id_type': id_type, 'name': name, 'is_deleted': False})

    for id_type, code, label in ENV_TYPES:
        EnvTypes.objects.get_or_create(
            code=code, defaults={'id_type': id_type, 'label': label, 'is_deleted': False})

    for code, description in PREF_TYPES:
        PrefTypes.objects.get_or_create(
            code=code, defaults={'description': description, 'is_deleted': False})

    for id_, code, description in CRITERIA:
        Criteria.objects.get_or_create(
            code=code, defaults={'id': id_, 'description': description, 'is_deleted': False})

    _resync_sequence(schema_editor, 'user_type', 'id_type')
    _resync_sequence(schema_editor, 'env_types', 'id_type')
    _resync_sequence(schema_editor, 'criteria', 'id')


class Migration(migrations.Migration):

    dependencies = [
        ('users', '0009_device'),
    ]

    operations = [
        migrations.RunPython(seed, migrations.RunPython.noop),
    ]
