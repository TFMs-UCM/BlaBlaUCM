import logging

from django.core.management.base import BaseCommand
from django.utils import timezone

from travels.services.travel_service import TravelService

logger = logging.getLogger(__name__)


# Comando para finalizar los viajes tras 2 horas despues de su fecha de finalizacion
class Command(BaseCommand):
    help = 'Pasa a estado finalizado los viajes activos cuya fecha supero las 2 horas tras la fecha de finalizacion.'

    def handle(self, *args, **kwargs):
        now = timezone.now()

        try:
            # La regla vive en el servicio, este comando solo la dispara
            finished_count, unvalidated_count = TravelService.finish_expired_travels(now)

            if not finished_count:
                logger.info(f'[{now}] No expired travels found.')
                return

            logger.info(
                f'Success: {finished_count} travels finished, '
                f'{unvalidated_count} passengers marked as unvalidated.'
            )
        except Exception as e:
            logger.error(f'Error finishing travels, command finish_travels: {str(e)}')