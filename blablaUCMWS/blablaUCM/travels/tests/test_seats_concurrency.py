"""
Pruebas de CONCURRENCIA del invariante `remaining_seats`.
"""
import threading
import time

from django.db import connection, transaction
from django.test import TransactionTestCase

from travels.models import Travel
from travels.services.exceptions import SeatsFullError
from travels.services.travel_service import TravelService
from travels.tests.factories import create_travel, create_user

class ConcurrentReservationTest(TransactionTestCase):

    serialized_rollback = True

    def setUp(self):
        self.driver = create_user("driver")
        # Un solo asiento libre: es el escenario donde se juega el overbooking
        self.travel = create_travel(self.driver, num_seats=3, remaining_seats=1)

    def remaining_seats(self):
        return Travel.objects.get(pk=self.travel.pk).remaining_seats

    def test_reserve_seat_waits_for_the_transaction_holding_the_lock(self):
        """
        Escenario determinista:

          1. El hilo A abre una transaccion y bloquea la fila del viaje.
          2. El hilo B llama a reserve_seat mientras A sigue dentro.
          3. B se queda esperando en el select_for_update hasta que A confirma.
          4. Cuando B despierta ya lee remaining_seats = 0, asi que falla.

        Sin el bloqueo, B habria leido el 1 anterior y habria aceptado un
        segundo pasajero para el mismo asiento.
        """
        lock_acquired = threading.Event()
        results = []

        def thread_a():
            try:
                with transaction.atomic():
                    travel = Travel.objects.select_for_update().get(pk=self.travel.pk)
                    lock_acquired.set()
                    # Se mantiene el bloqueo mientras B intenta reservar
                    time.sleep(0.5)
                    travel.remaining_seats -= 1
                    travel.save()
            finally:
                connection.close()

        def thread_b():
            lock_acquired.wait(timeout=5)
            try:
                TravelService.reserve_seat(self.travel.pk)
                results.append('ok')
            except SeatsFullError:
                results.append('full')
            finally:
                connection.close()

        a = threading.Thread(target=thread_a)
        b = threading.Thread(target=thread_b)
        a.start()
        b.start()
        a.join(timeout=15)
        b.join(timeout=15)

        # B no consigue el asiento y el viaje se queda en 0, no en -1
        self.assertEqual(results, ['full'])
        self.assertEqual(self.remaining_seats(), 0)

    def test_two_simultaneous_reservations_only_take_one_seat(self):
        """
        Los dos hilos llaman a reserve_seat a la vez sobre el ultimo asiento.
        Exactamente uno debe conseguirlo.
        """
        start_barrier = threading.Barrier(2, timeout=10)
        results = []
        results_lock = threading.Lock()

        def try_reserve():
            try:
                start_barrier.wait()
                try:
                    TravelService.reserve_seat(self.travel.pk)
                    outcome = 'ok'
                except SeatsFullError:
                    outcome = 'full'
                with results_lock:
                    results.append(outcome)
            finally:
                connection.close()

        threads = [threading.Thread(target=try_reserve) for _ in range(2)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=15)

        self.assertEqual(sorted(results), ['full', 'ok'])
        self.assertEqual(self.remaining_seats(), 0)

    def test_two_simultaneous_releases_do_not_exceed_the_maximum(self):
        """
        Escenario: quedan 2 de 3 plazas y dos hilos liberan a la vez. El viaje
        tiene que acabar en 3, nunca en 4, porque `release_seat` bloquea la fila
        y aplica el guard `remaining_seats >= num_seats` **despues** de leerla
        bloqueada. Sin el bloqueo los dos leerian 2, los dos pasarian el guard y
        el viaje ofreceria un asiento que el coche no tiene.
        """
        Travel.objects.filter(pk=self.travel.pk).update(remaining_seats=2)

        start_barrier = threading.Barrier(2, timeout=10)
        results = []
        results_lock = threading.Lock()

        def try_release():
            try:
                start_barrier.wait()
                _travel, released = TravelService.release_seat(self.travel.pk)
                with results_lock:
                    results.append('released' if released else 'at-max')
            finally:
                connection.close()

        threads = [threading.Thread(target=try_release) for _ in range(2)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=15)

        # Uno libera y el otro se encuentra el viaje ya al maximo
        self.assertEqual(sorted(results), ['at-max', 'released'])
        self.assertEqual(self.remaining_seats(), 3)

    def test_a_release_and_a_reservation_at_the_same_time_leave_the_count_intact(self):
        """
        Los dos sentidos compitiendo por la misma fila. Da igual quien gane la
        carrera: el neto es cero y las plazas no se descuadran.
        """
        Travel.objects.filter(pk=self.travel.pk).update(remaining_seats=2)

        start_barrier = threading.Barrier(2, timeout=10)

        def reserve():
            try:
                start_barrier.wait()
                TravelService.reserve_seat(self.travel.pk)
            except SeatsFullError:
                pass
            finally:
                connection.close()

        def release():
            try:
                start_barrier.wait()
                TravelService.release_seat(self.travel.pk)
            finally:
                connection.close()

        threads = [threading.Thread(target=reserve), threading.Thread(target=release)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=15)

        self.assertEqual(self.remaining_seats(), 2)

    def test_without_lock_overbooking_happens(self):
        """
        Contraprueba: reproduce la logica ANTERIOR al refactor (leer, comprobar
        y escribir sin select_for_update) y demuestra que sobrevende.

        La barrera fuerza el entrelazado que en produccion ocurriria por azar:
        los dos hilos leen remaining_seats = 1 antes de que ninguno escriba.

        Este test NO prueba el codigo actual: existe para justificar por que
        reserve_seat necesita el bloqueo. Si algun dia falla, significa que el
        motor esta serializando por su cuenta, no que el codigo sea correcto.
        """
        both_have_read = threading.Barrier(2, timeout=10)
        results = []
        results_lock = threading.Lock()

        def reserve_without_lock():
            try:
                with transaction.atomic():
                    travel = Travel.objects.get(pk=self.travel.pk)  # sin select_for_update
                    both_have_read.wait()
                    if travel.remaining_seats > 0:
                        travel.remaining_seats -= 1
                        travel.save()
                        outcome = 'ok'
                    else:
                        outcome = 'full'
                with results_lock:
                    results.append(outcome)
            finally:
                connection.close()

        threads = [threading.Thread(target=reserve_without_lock) for _ in range(2)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=15)

        # Los dos creen haber conseguido plaza: un asiento, dos pasajeros
        self.assertEqual(results, ['ok', 'ok'])
        self.assertEqual(self.remaining_seats(), 0)
