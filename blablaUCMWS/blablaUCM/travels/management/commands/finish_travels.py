from django.core.management.base import BaseCommand
from django.utils import timezone
from datetime import timedelta
from travels.models import Travel, RequestTravels
from users.models import Notifications
import logging
from django.db import transaction
from django.db.models import F, ExpressionWrapper, DateTimeField
from django.template.defaultfilters import date as django_date


logger = logging.getLogger(__name__)

# Comando para eliminar los viajes tras 2 horas despues de su fecha de finalizacion
class Command(BaseCommand):
    help = 'Pasa a estado finalizado los viajes activos cuya fecha supero las 2 horas tras la fecha de finalizacion.'

    def handle(self, *args, **kwargs):
        now = timezone.now()
        period = timedelta(hours=2)

        try:
            with transaction.atomic():
                # Se calcula la fecha de expiracion de cada viaje que es 2 horas pasadas desde la fecha de finalizacion 
                travels_with_expiration = Travel.objects.annotate(
                    expiration_date=ExpressionWrapper(
                        F('travel_date') + (timedelta(minutes=1) * F('duration_minutes')) + period,
                        output_field=DateTimeField()
                    )
                )
                # Se sacan los viajes que han expirado
                expired_travels_qs = travels_with_expiration.filter(
                    state='active', 
                    expiration_date__lte=now,
                    is_deleted=False
                )
                # Se extraen los ids de los viajes expirados
                expired_travel_ids = list(expired_travels_qs.values_list('id_travel', flat=True))
                # Si no hay viajes expirados, no se hace nada
                if not expired_travel_ids:
                    logger.info(f'[{now}] No expired travels found.')
                    return

                # Se actualizan los viajes expirados a estado finalizado
                updated_travels_count = expired_travels_qs.update(state='fnd')
                
                # Se buscan las solicitudes de viaje asociadas a los viajes expirados
                requests_to_update = RequestTravels.objects.filter(
                    id_travel__in=expired_travel_ids,
                    is_deleted=False
                ).select_related('id_travel', 'user')
                
                # Por cada una de las notificaciones se envia una notificacion indicando que el viaje ha finalizado
                notifications = []
                for req in requests_to_update:
                    travel = req.id_travel    
                    parsed_date = django_date(travel.travel_date, r"j \d\e F \d\e Y")
                    msg = f"El viaje de {travel.origin} a {travel.destination} del día {parsed_date} ha finalizado, NO has sido validado en él."
                    notifications.append(
                        Notifications(
                            id_user=req.user,
                            content=msg
                        )
                    )
                # Se actualiza el estado de las solicitudes
                updated_requests_count = requests_to_update.update(status='unvalidated')
                
                # Si hay que enviar notificaciones, se crean en bloque
                if notifications:
                    Notifications.objects.bulk_create(notifications)
                    
                logger.info(
                    f'Success: {updated_travels_count} travels finished, '
                    f'{updated_requests_count} requests unvalidated, '
                    f'{len(notifications)} notifications sent.'
                )           
        except Exception as e:
            logger.error(f'Error finishing travels, command finish_travels: {str(e)}')