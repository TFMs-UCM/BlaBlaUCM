"""
Catalogos de travels en el panel de administracion, solo se añaden los de TravelStates y RequestStates
"""
from django.contrib import admin

from api.catalog_admin import CatalogAdmin
from travels.models import RequestStates, TravelStates


# Estados por los que pasa un viaje
@admin.register(TravelStates)
class TravelStatesAdmin(CatalogAdmin):
    list_display = ('code', 'description', 'is_deleted')
    search_fields = ('code', 'description')


# Estados por los que pasa una solicitud de viaje
@admin.register(RequestStates)
class RequestStatesAdmin(CatalogAdmin):
    list_display = ('code', 'description', 'is_deleted')
    search_fields = ('code', 'description')
