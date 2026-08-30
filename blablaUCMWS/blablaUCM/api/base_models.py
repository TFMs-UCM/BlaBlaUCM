"""
Modelo base para declarar los campos de auditoria y borrado logico del dominio.
"""
from django.db import models


class BaseModel(models.Model):
    """Campos de auditoria y borrado logico compartidos por todo el dominio."""

    is_deleted = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
      abstract = True
