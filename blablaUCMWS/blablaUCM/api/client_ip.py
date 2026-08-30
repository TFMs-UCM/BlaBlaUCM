"""
IP real del cliente, con la misma regla que ya usa DRF para el limite de peticiones.

Existe porque REMOTE_ADDR no es de fiar ya que daphne arranca con --proxy-headers para que la IP no sea siempre 
la de Caddy, y al hacerlo sustituye REMOTE_ADDR por la primera entrada de X-Forwarded-For, que es justo la que 
pone el cliente, el proxy añde la suya al final de la cabecera en lugar de sustituirla
"""
from django.conf import settings


def get_client_ip(request):
    """
    Devuelve la IP del cliente segun REST_FRAMEWORK[NUM_PROXIES]:

    Con NUM_PROXIES = n (n > 0) se coge la entrada n-esima (por la derecha)
      de X-Forwarded-For, que es la que ha escrito el ultimo proxy de confianza
    Con NUM_PROXIES = 0, o sin cabecera, se usa REMOTE_ADDR (se debe usar si no hay
      proxy delante donde ese valor si es el del socket y no se puede falsear)
    Sin NUM_PROXIES definido va al comportamiento por defecto de DRF, que usa la cadena entera
    """
    xff = request.META.get('HTTP_X_FORWARDED_FOR')
    remote_addr = request.META.get('REMOTE_ADDR')

    num_proxies = getattr(settings, 'REST_FRAMEWORK', {}).get('NUM_PROXIES')

    if num_proxies is not None:
        if num_proxies == 0 or xff is None:
            return remote_addr
        addrs = xff.split(',')
        client_addr = addrs[-min(num_proxies, len(addrs))]
        return client_addr.strip()

    return ''.join(xff.split()) if xff else remote_addr
