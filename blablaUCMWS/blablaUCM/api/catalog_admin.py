"""
Base comun del panel de administracion de los catalogos.

Los catalogos (tipos de usuario, de preferencia, criterios, distintivos
ambientales y estados de viaje y de solicitud) se insertan en las migraciones
"""
from django.contrib import admin
from django.utils import timezone

class CatalogAdmin(admin.ModelAdmin):
    """
    Alta y edicion de un catalogo, con el borrado real desactivado.
    """
    list_filter = ('is_deleted',)
    readonly_fields = ('created_at', 'updated_at', 'deleted_at')
    ordering = ('code',)

    def has_delete_permission(self, request, obj=None):
        """
        No se debe permitir eliminar un catalogo desde el panel
        """
        return False

    def save_model(self, request, obj, form, change):
        """
        Pone el delete_At y is_deleted, para mantener consistencia con el borrado de la aplicacion
        """
        if obj.is_deleted and obj.deleted_at is None:
            obj.deleted_at = timezone.now()
        elif not obj.is_deleted:
            obj.deleted_at = None

        super().save_model(request, obj, form, change)
