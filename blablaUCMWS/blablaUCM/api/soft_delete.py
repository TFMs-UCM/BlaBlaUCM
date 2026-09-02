from django.utils import timezone

class SoftDeleteQuerysetMixin:
    """
    Clase para aplicar un soft delete, es decir que no se elimine de bbdd el elemento, si no que se marque como borrado,
    ademas, se sobreescribe el queryset para que por defecto no saque los elementos marcados como borrados
    """
    # Se sobreescribe para que el queryset no saque los borrados, todas las tablas tienen el campo is_deleted
    def get_queryset(self):
        qs = super().get_queryset()
        return qs.filter(is_deleted=False)
    
    # Se sobreescribe el destroy para que en vez de eliminar, marque como borrado
    def perform_destroy(self, instance):
        instance.is_deleted = True
        instance.deleted_at = timezone.now()
        instance.save()