from django.db import migrations

# Datos de catalogo de la app

TRAVEL_STATES = [
    # (id_state, code, description)
    (1, 'active',  'Estado creado pero no iniciado'),
    (2, 'started', 'Estado iniciado pero no finalizado'),
    (3, 'fnd',     'Estado finalizado'),
]

REQUEST_STATES = [
    # (code, description)  -> id autogenerado
    ('pending',     'Solicitud pendiente de respuesta'),
    ('accepted',    'Solicitud aceptada'),
    ('rejected',    'Solicitud rechazada'),
    ('validated',   'Solicitud validada'),
    ('unvalidated', 'Solicitud no validada'),
]


def _resync_sequence(schema_editor, table, pk_col):
    """Realinea la secuencia del pk tras insertar ids explicitos"""
    if schema_editor.connection.vendor != 'postgresql':
        return
    with schema_editor.connection.cursor() as cur:
        cur.execute(
            "SELECT setval(pg_get_serial_sequence(%s, %s), "
            "COALESCE((SELECT MAX(" + pk_col + ") FROM " + table + "), 1))",
            [table, pk_col],
        )


def seed(apps, schema_editor):
    TravelStates = apps.get_model('travels', 'TravelStates')
    RequestStates = apps.get_model('travels', 'RequestStates')

    for id_state, code, description in TRAVEL_STATES:
        TravelStates.objects.get_or_create(
            code=code, defaults={'id_state': id_state, 'description': description, 'is_deleted': False})

    for code, description in REQUEST_STATES:
        RequestStates.objects.get_or_create(
            code=code, defaults={'description': description, 'is_deleted': False})

    _resync_sequence(schema_editor, 'travel_states', 'id_state')


class Migration(migrations.Migration):

    dependencies = [
        ('travels', '0011_alter_requesttravels_validation_code_and_more'),
    ]

    operations = [
        migrations.RunPython(seed, migrations.RunPython.noop),
    ]
