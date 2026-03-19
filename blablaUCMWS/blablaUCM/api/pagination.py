from rest_framework.pagination import PageNumberPagination

class TravelPagination(PageNumberPagination):
    page_size = 10  # cantidad de items por página
    page_size_query_param = 'page_size'
    max_page_size = 50
