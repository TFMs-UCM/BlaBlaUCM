"""
Catalogos de users en el panel de administracion.
"""
from django.contrib import admin

from api.catalog_admin import CatalogAdmin
from users.models import Criteria, EnvTypes, PrefTypes, UserType


# Tipos de usuario (estudiante, profesor, personal...)
@admin.register(UserType)
class UserTypeAdmin(CatalogAdmin):
    list_display = ('code', 'name', 'is_deleted')
    search_fields = ('code', 'name')


# Tipos de preferencia que puede declarar un usuario
@admin.register(PrefTypes)
class PrefTypesAdmin(CatalogAdmin):
    list_display = ('code', 'description', 'is_deleted')
    search_fields = ('code', 'description')


# Criterios con los que se valora a un conductor
@admin.register(Criteria)
class CriteriaAdmin(CatalogAdmin):
    list_display = ('code', 'description', 'is_deleted')
    search_fields = ('code', 'description')


# Distintivos ambientales de los vehiculos
@admin.register(EnvTypes)
class EnvTypesAdmin(CatalogAdmin):
    list_display = ('code', 'label', 'is_deleted')
    search_fields = ('code', 'label')
