from rest_framework.pagination import PageNumberPagination

# Clases para la paginacion de los resultados

class TravelPagination(PageNumberPagination):
    page_size = 10  # cantidad de items por página
    page_size_query_param = 'page_size'
    max_page_size = 50

class CustomPagination(PageNumberPagination):
    page_size = 10 
