from django.core.exceptions import ImproperlyConfigured
from django.db.models import Q


class OwnedQuerysetMixin:
    """
    Limita el queryset a los objetos del usuario que hace la peticion
    """
    owner_field = 'id_user'

    def get_queryset(self):
        qs = super().get_queryset()
        # Sin usuario autenticado no hay nada que sea suyo
        if not self.request.user.is_authenticated:
            return qs.none()

        fields = self.owner_field
        if isinstance(fields, str):
            fields = (fields,)

        condition = Q()
        for field in fields:
            condition |= Q(**{field: self.request.user.pk})

        return qs.filter(condition)


class OwnedCreateMixin:
    """
    Obliga a que el objeto creado tenga como dueño al usuario que hace la peticion
    """
    def perform_create(self, serializer):
        field = self.owner_field

        if not isinstance(field, str) or '__' in field:
            raise ImproperlyConfigured(
                f"{type(self).__name__}: OwnedCreateMixin necesita un `owner_field` "
                f"que sea un campo directo del modelo, y no {field!r}."
            )

        serializer.save(**{field: self.request.user})