"""
Base comun de los serializers para manejar sus campos de auditoria para que solo se borren con su delete, 
no se puede dejar que alguien haga PATCH /api/v1/<lo-que-sea>/{id}/   {"is_deleted": true} y 
se modifique, por lo que todos los serializers heredan de este, y este los debe poner en 
solo lectura, de modo que solo se pueda eliminar pasando por el enpoint delete correspondiente
"""


class AuditFieldsMixin:
    """
    Deja los campos de auditoria de BaseModel en solo lectura. La forma de borrar sigue siendo DELETE, 
    que pasa por SoftDeleteQuerysetMixin.perform_destroy y escribe is_deleted y deleted_at sin pasar por el serializer.
    """

    AUDIT_FIELDS = ('is_deleted', 'deleted_at', 'created_at', 'updated_at')

    def get_fields(self):
        fields = super().get_fields()

        for name in self.AUDIT_FIELDS:
            if name in fields:
                fields[name].read_only = True

        return fields
