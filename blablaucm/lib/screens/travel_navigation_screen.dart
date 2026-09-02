import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/models/travel_model.dart';
import 'package:blablaucm/models/pick_up_points_model.dart';
import 'package:blablaucm/models/api_error.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/services/route_services/ors_routing_service.dart';
import 'package:blablaucm/screens/helper.dart';
import 'package:blablaucm/theme/app_colors.dart';

// Pantalla de navegacion que muestra la ruta del viaje con instrucciones

class TravelNavigationScreen extends StatefulWidget {
  final TravelModel travel;
  final double originLat;
  final double originLng;
  final double destLat;
  final double destLng;

  const TravelNavigationScreen({
    super.key,
    required this.travel,
    required this.originLat,
    required this.originLng,
    required this.destLat,
    required this.destLng,
  });

  @override
  State<TravelNavigationScreen> createState() => _TravelNavigationScreenState();
}

class _TravelNavigationScreenState extends State<TravelNavigationScreen> {
  final MapController _mapController = MapController();
  final ApiService _api = ApiService();
  final OrsRoutingService _routingService = OrsRoutingService();
  final Distance _distanceCalc = const Distance();
  bool _isMapReady = false;

  // Estado del GPS
  StreamSubscription<Position>? _positionStream;
  LatLng? _currentPosition;
  // Grados desde el norte para orientar la flecha del GPS
  double? _currentHeading;
  bool _isFollowingUser = true;
  // Si el GPS esta apagado o sin permisos al abrir la pantalla, la guia se queda sin arrancar
  // Se recuerda para poder reintentarlo con el boton de centrar
  bool _isGpsActive = false;
  bool _isRetryingGps = false;

  // Marca que la pantalla ya se ha cerrado para no arrancar el GPS a destiempo
  bool _disposed = false;

  // Estado de la ruta
  RouteResult? _routeResult;
  List<LatLng> _routePoints = [];
  List<RouteStep> _routeSteps = [];
  int _currentStepIndex = 0;
  RouteProgress? _progress;
  bool _isLoadingRoute = true;
  bool _isRecalculating = false;

  // Paradas ordenadas y navegacion por tramos
  final List<LatLng> _stopPoints = [];
  final List<String> _stopLabels = [];
  final List<PickUpPointModel?> _stopPickups = [];
  final List<LatLng> _pickupPoints = [];
  int _currentStopIndex = 0;
  int _lastArrivalStopIndex = -1;
  bool _hasReachedFinalDestination = false;
  bool _isAdvancingStop = false;

  // Umbral de desviacion para recalcular la ruta (en metros)
  static const double _deviationThreshold = 50.0;
  // Radio para dar por alcanzado el destino final del viaje
  static const double _arrivalThreshold = 35.0;
  // Radio dentro del cual se considera que se ha estado en una parada de recogida
  static const double _pickupArrivalThreshold = 1000.0;
  // Cuanto hay que alejarse del punto mas cercano al que se llego para dar la parada por pasada
  static const double _passedAwayMargin = 250.0;
  // Lo mas cerca que se ha llegado a estar de la parada actual
  double? _minDistanceToCurrentStop;
  // Tiempo minimo entre recalculos para no saturar la API
  DateTime? _lastRecalculationTime;
  static const Duration _minRecalculationInterval = Duration(seconds: 15);

  // Velocidad a partir de la cual el rumbo que da el GPS es fiable (m/s)
  static const double _minSpeedForHeading = 0.5;
  // Separacion minima entre dos posiciones para deducir el rumbo de ellas (m)
  static const double _minDistanceForBearing = 8.0;

  // Lista de pasajeros validados
  final Set<String> _validatedCodes = {};

  @override
  void initState() {
    super.initState();
    // Conduciendo no se toca la pantalla, y al apagarse el sistema corta las
    // actualizaciones de posicion, se mantiene encendida solo en esta pantalla.
    WakelockPlus.enable();
    _initLocationAndRoute();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPositionUpdates();
    WakelockPlus.disable();
    super.dispose();
  }

  // Corta las actualizaciones de posicion y cierra la notificacion de navegacion en curso
  void _stopPositionUpdates() {
    _positionStream?.cancel();
    _positionStream = null;
    _isGpsActive = false;
  }

  // Se inicializa el GPS y calcula la ruta inicial
  Future<void> _initLocationAndRoute() async {
    await _startGps();
    _buildStopPoints();
    await _calculateRoute();
  }

  // Construye la lista de paradas
  void _buildStopPoints() {
    _stopPoints.clear();
    _stopLabels.clear();
    _stopPickups.clear();
    _pickupPoints.clear();

    int stopCount = 0;
    if (widget.travel.pickUpPoints != null) {
      for (final pp in widget.travel.pickUpPoints!) {
        if (pp.lat != null && pp.lng != null) {
          stopCount += 1;
          final label = pp.name.trim().isNotEmpty ? pp.name.trim() : 'Parada $stopCount';
          final point = LatLng(pp.lat!, pp.lng!);
          _pickupPoints.add(point);
          _stopPoints.add(point);
          _stopLabels.add(label);
          _stopPickups.add(pp);
        }
      }
    }

    _stopPoints.add(LatLng(widget.destLat, widget.destLng));
    _stopLabels.add('Destino');
    _stopPickups.add(null);
    _currentStopIndex = _findNextStopIndex(0);
    _lastArrivalStopIndex = -1;
    _hasReachedFinalDestination = false;
    _minDistanceToCurrentStop = null;
  }

  // Saca la siguiente parada que no se ha alcanzado aun
  int _findNextStopIndex(int startIndex) {
    for (int i = startIndex; i < _stopPoints.length; i++) {
      final pickup = _stopPickups[i];
      if (pickup == null) {
        return i;
      }
      if (pickup.isReached != true) {
        return i;
      }
    }
    return _stopPoints.length - 1;
  }

  LatLng? _getCurrentTarget() {
    if (_currentStopIndex >= 0 && _currentStopIndex < _stopPoints.length) {
      return _stopPoints[_currentStopIndex];
    }
    return null;
  }

  String _getCurrentTargetLabel() {
    if (_currentStopIndex >= 0 && _currentStopIndex < _stopLabels.length) {
      return _stopLabels[_currentStopIndex];
    }
    return 'Destino';
  }

  // Ajustes del stream de posiciones para navegar.
  LocationSettings _buildLocationSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5, // Se actualiza cada 5 metros de movimiento
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Navegación en curso',
          notificationText: 'BlaBlaUCM te está guiando hasta tu destino',
          notificationChannelName: 'Navegación',
          enableWakeLock: true,
          setOngoing: true,
          color: AppColors.primary,
        ),
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    }

    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );
  }

  // Funcion para iniciar el servicio de geolocalizacion y el stream de posiciones
  Future<bool> _startGps() async {
    // Se comprueba que el servicio de localizacion este habilitado
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        showModal(context, 'Por favor, activa el GPS para usar la navegación. '
            'Cuando lo actives, pulsa el botón de centrar para reanudar la guía.');
      }
      return false;
    }

    // Se comprueba y solicita los permisos de ubicacion
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          showModal(context, 'Se necesitan permisos de ubicación para la navegación.');
        }
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        showModal(context, 'Los permisos de ubicación están permanentemente denegados. Actívalos en ajustes.');
      }
      return false;
    }

    // Se obtiene la posicion actual
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });
    } catch (e) {
      // Si no se puede obtener, se usa el origen como posicion inicial
      setState(() {
        _currentPosition = LatLng(widget.originLat, widget.originLng);
      });
    }

    if (_disposed) return false;

    // Un reintento no debe dejar dos streams vivos si el anterior seguia 
    _stopPositionUpdates();

    final subscription = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(),
    ).listen((Position position) async {
      if (!mounted) return;
      final newPosition = LatLng(position.latitude, position.longitude);
      final heading = _resolveHeading(position, newPosition);
      setState(() {
        _currentPosition = newPosition;
        if (heading != null) _currentHeading = heading;
      });

      // Se mueve el mapa para seguir al usuario si esta activado
      if (_isMapReady && _isFollowingUser && _currentPosition != null) {
        _mapController.move(_currentPosition!, _mapController.camera.zoom);
      }

      // Se actualiza el paso actual de la ruta
      _updateCurrentStep();

      // Se comprueba si se ha llegado a la parada actual
      await _checkArrivalToTarget();

      // Se comprueba si el conductor se ha desviado de la ruta
      _checkRouteDeviation();
    }, onError: (_) {
      if (!mounted) return;
      _stopPositionUpdates();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Se ha perdido la señal del GPS. Actívalo y pulsa el botón de centrar.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
    });
    
    if (_disposed) {
      subscription.cancel();
      return false;
    }

    _positionStream = subscription;
    _isGpsActive = true;
    return true;
  }

  // Funcion para intentar arrancar la el GPS desde el boton de centrar
  Future<void> _retryGps() async {
    if (_isRetryingGps) return;
    setState(() {
      _isRetryingGps = true;
    });

    final started = await _startGps();

    if (!mounted) {
      _isRetryingGps = false;
      return;
    }

    setState(() {
      _isRetryingGps = false;
      if (started) _isFollowingUser = true;
    });

    if (!started || _currentPosition == null) return;

    if (_isMapReady) {
      _mapController.move(_currentPosition!, 16);
    }
    await _calculateRoute(fromPosition: _currentPosition);
  }

  // Funcion para sacar el rumbo de la marcha para orientar la flecha del mapa
  double? _resolveHeading(Position position, LatLng newPosition) {
    if (position.speed >= _minSpeedForHeading && position.heading != 0.0) {
      return _normalizeDegrees(position.heading);
    }

    final previous = _currentPosition;
    if (previous == null) return null;
    if (_distanceCalc.as(LengthUnit.Meter, previous, newPosition) < _minDistanceForBearing) {
      return null;
    }
    return _normalizeDegrees(_distanceCalc.bearing(previous, newPosition));
  }

  // Funcion para normalizar los grados al rango [0, 360), el rumbo calculado sale de un atan2 y viene en [-180, 180]
  double _normalizeDegrees(double degrees) => (degrees % 360 + 360) % 360;

  // Calcula la ruta usando OpenRouteService
  Future<void> _calculateRoute({LatLng? fromPosition}) async {
    if (_hasReachedFinalDestination) return;
    final target = _getCurrentTarget();
    if (target == null) {
      if (mounted) {
        showModal(context, 'No hay paradas validas para calcular la ruta.');
      }
      return;
    }

    setState(() {
      _isLoadingRoute = fromPosition == null;
      _isRecalculating = fromPosition != null;
    });

    // Se construyen los waypoints del tramo actual
    final startPoint = fromPosition ?? _currentPosition ?? LatLng(widget.originLat, widget.originLng);
    final List<LatLng> waypoints = [startPoint, target];

    // Se calcula la ruta con ORS
    final result = await _routingService.getRoute(waypoints);

    if (!mounted) return;

    if (result != null) {
      setState(() {
        _routeResult = result;
        _routePoints = result.routePoints;
        _routeSteps = result.steps;
        _isLoadingRoute = false;
        _isRecalculating = false;
        _currentStepIndex = 0;
        _progress = null;
      });

      // Se recoloca el progreso con la posicion actual
      _updateCurrentStep();

      if (_routePoints.isNotEmpty && (fromPosition == null || !_isFollowingUser)) {
        _fitRouteOnMap();
      }
    } else {
      setState(() {
        _isLoadingRoute = false;
        _isRecalculating = false;
      });
      if (mounted) {
        showModal(context, 'No se pudo calcular la ruta. Comprueba tu conexión.');
      }
    }
  }

  // Ajusta el zoom del mapa para mostrar toda la ruta
  void _fitRouteOnMap() {
    if (_routePoints.isEmpty) return;
    if (!_isMapReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isMapReady) {
          _fitRouteOnMap();
        }
      });
      return;
    }
    final bounds = LatLngBounds.fromPoints(_routePoints);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _mapController.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)),
        );
      }
    });
  }

  // Funcion para actualizar el progreso sobre la ruta con la ultima posicion del GPS
  void _updateCurrentStep() {
    if (_routeResult == null || _routeSteps.isEmpty || _currentPosition == null) return;
    final progress = OrsRoutingService.computeProgress(
      _currentPosition!,
      _routeResult!,
      fromStepIndex: _currentStepIndex,
    );
    setState(() {
      _progress = progress;
      _currentStepIndex = progress.stepIndex;
    });
  }

  // Funcion para sacar el indice de la instruccion que hay que enseñar al conductor
  int get _displayStepIndex {
    if (_routeSteps.isEmpty){
      return 0;
    }
    final next = _currentStepIndex + 1;
    return next < _routeSteps.length ? next : _routeSteps.length - 1;
  }

  // Funcion para sacar la distancia que falta hasta la maniobra que se esta mostrando
  double get _distanceToNextManeuver {
    final progress = _progress;
    if (progress != null){
      return progress.distanceToManeuver;
    }
    if (_routeSteps.isEmpty){
      return 0;
    }
    return _routeSteps[_displayStepIndex].distance;
  }

  // Funcion para comprobar si el conductor ha llegado a la parada actual y si ha llegado avanza a la siguiente
  Future<void> _checkArrivalToTarget() async {
    if (_hasReachedFinalDestination || _currentPosition == null || _isAdvancingStop) return;
    final target = _getCurrentTarget();
    if (target == null) return;
    if (_currentStopIndex == _lastArrivalStopIndex) return;

    final distToTarget = _distanceCalc.as(LengthUnit.Meter, _currentPosition!, target);
    final isPickup = _currentStopIndex < _stopPickups.length && _stopPickups[_currentStopIndex] != null;

    // Se guarda lo mas cerca que se ha llegado a estar antes de comparar, para que el minimo no incluya la lectura actual
    final minSeen = _minDistanceToCurrentStop;
    if (minSeen == null || distToTarget < minSeen) {
      _minDistanceToCurrentStop = distToTarget;
    }

    bool arrived = distToTarget <= _arrivalThreshold;

    if (!arrived && isPickup && minSeen != null && minSeen <= _pickupArrivalThreshold && distToTarget > minSeen + _passedAwayMargin) {
      arrived = true;
    }

    if (!arrived) return;

    _lastArrivalStopIndex = _currentStopIndex;
    _isAdvancingStop = true;
    await _advanceToNextStop();
    _isAdvancingStop = false;
  }

  // Funcion para indicar si despues del objetivo actual queda alguna parada a la que saltar
  bool get _hasNextStop {
    if (_hasReachedFinalDestination || _isAdvancingStop) return false;
    return _currentStopIndex >= 0 && _currentStopIndex < _stopPoints.length - 1;
  }

  // Funcion para saltar manualmente a la siguiente parada, pidiendo confirmacion antes
  Future<void> _confirmSkipToNextStop() async {
    if (!_hasNextStop) return;

    final currentLabel = _getCurrentTargetLabel();
    final nextLabel = _stopLabels[_findNextStopIndex(_currentStopIndex + 1)];

    final confirm = await showConfirmationModal(
      context,
      title: 'Ir a la siguiente parada',
      message: '¿Dar por completada "$currentLabel" y continuar hasta "$nextLabel"?',
      confirmText: 'Continuar',
      cancelText: 'Cancelar',
    );

    if (!confirm || !mounted) return;

    // Mientras se confirmaba el GPS pudo avanzar la parada por su cuenta
    if (!_hasNextStop) return;

    _lastArrivalStopIndex = _currentStopIndex;
    setState(() {
      _isAdvancingStop = true;
    });
    await _advanceToNextStop();
    if (!mounted) {
      _isAdvancingStop = false;
      return;
    }
    setState(() {
      _isAdvancingStop = false;
    });
  }

  // Avanza a la siguiente parada y recalcula la ruta
  Future<void> _advanceToNextStop() async {
    if (_currentStopIndex >= _stopPoints.length) return;
    final reachedLabel = _getCurrentTargetLabel();
    final pickup = _stopPickups[_currentStopIndex];
    final isFinal = pickup == null;

    if (pickup != null && pickup.id.isNotEmpty) {
      final success = await _requestReachedPickupPoint(pickup.id);
      if (success) {
        pickup.isReached = true;
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo marcar la parada como completada.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    }

    // Si es el destino, se le informa al usuario
    if (isFinal) {
      setState(() {
        _hasReachedFinalDestination = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Has llegado al destino.'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
      return;
    }

    final nextIndex = _findNextStopIndex(_currentStopIndex + 1);
    setState(() {
      _currentStopIndex = nextIndex;
      _currentStepIndex = 0;
      _progress = null;
      _minDistanceToCurrentStop = null;
    });

    if (mounted) {
      final nextLabel = _getCurrentTargetLabel();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Has llegado a $reachedLabel. Siguiente parada: $nextLabel.'),
          backgroundColor: const Color(0xFF4F46E5),
        ),
      );
    }
    _calculateRoute(fromPosition: _currentPosition);
  }

  // Marca un punto como alcanzado
  Future<bool> _requestReachedPickupPoint(String pointId) async {
    final endpoint = "${dotenv.env['TRAVELS_ENDPOINT'] ?? '/travel/'}${widget.travel.id}${dotenv.env['REACHED_PICKUP_POINT_ENDPOINT'] ?? '/reached_pickup_point/'}";
    final response = await _api.requestToApi(
      endpoint,
      op: ApiOptions.post,
      body: {"id_point": pointId},
    );

    return response != null && (response['status'] == 'ok' || response['error'] == null);
  }

  // Comprueba si el conductor se ha desviado de la ruta y recalcula si es necesario
  void _checkRouteDeviation() {
    if (_hasReachedFinalDestination || _currentPosition == null || _routePoints.isEmpty || _isRecalculating) return;

    // Se calcula la distancia del conductor a la ruta
    final distToRoute = OrsRoutingService.distanceToRoute(_currentPosition!, _routePoints);

    if (distToRoute > _deviationThreshold) {
      // Se comprueba que no se haya recalculado hace poco
      final now = DateTime.now();
      if (_lastRecalculationTime != null && now.difference(_lastRecalculationTime!) < _minRecalculationInterval) {
        return;
      }
      _lastRecalculationTime = now;
      // Se recalcula la ruta desde la posicion actual
      _calculateRoute(fromPosition: _currentPosition);
    }
  }

  // Muestra la modal para validar un pasajero mediante codigo o QR
  void _showValidationModal() {
    final codeController = TextEditingController();
    final colors = AppColors.of(context);
    final accent = _accent(colors);
    bool isValidating = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: colors.card,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.verified_user, color: accent),
                  const SizedBox(width: 8),
                  Text('Validar Pasajero', style: TextStyle(color: colors.textPrimary)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Introduce el código del pasajero o escanea su QR',
                    style: TextStyle(color: colors.textSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  // Campo para introducir el codigo manualmente
                  TextField(
                    controller: codeController,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Código de validación',
                      labelStyle: TextStyle(color: colors.textSecondary),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: Icon(Icons.confirmation_number, color: colors.textSecondary),
                      filled: true,
                      fillColor: colors.surfaceLow,
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 12),
                  // Boton para abrir el lector QR
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final scannedCode = await _openQrScanner();
                        if (scannedCode != null) {
                          setDialogState(() {
                            codeController.text = scannedCode;
                          });
                        }
                      },
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Escanear QR'),
                      style: AppButtonStyles.secondary,
                    ),
                  ),
                  if (isValidating)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: CircularProgressIndicator(),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text('Cancelar', style: TextStyle(color: colors.textSecondary)),
                ),
                ElevatedButton(
                  onPressed: isValidating ? null : () async {
                    final code = codeController.text.trim();
                    if (code.isEmpty) return;

                    setDialogState(() {
                      isValidating = true;
                    });

                    // Se llama a la API para validar al pasajero
                    final error = await _validatePassenger(code);

                    setDialogState(() {
                      isValidating = false;
                    });

                    if (!dialogContext.mounted) return;

                    if (error == null) {
                      Navigator.pop(dialogContext);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Pasajero validado correctamente'),
                            backgroundColor: Color(0xFF10B981),
                          ),
                        );
                      }
                    }
                    else {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(
                          content: Text(_validationMessage(error)),
                          backgroundColor: const Color(0xFFEF4444),
                        ),
                      );
                    }
                  },
                  style: AppButtonStyles.primary,
                  child: const Text('Validar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Abre el lector de codigos QR y devuelve el valor leido
  Future<String?> _openQrScanner() async {
    return Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => _QrScannerScreen(),
      ),
    );
  }

  // Llama a la API para validar un pasajero con su codigo, devuelve null si se ha validado, o el motivo concreto del fallo.
  Future<ApiError?> _validatePassenger(String code) async {
    final endpoint = '${dotenv.env['TRAVELS_ENDPOINT'] ?? '/travel/'}${widget.travel.id}${dotenv.env['VALIDATE_PASSENGER_ENDPOINT'] ?? '/validate_passenger/'}';

    final response = await _api.requestToApi(
      endpoint,
      op: ApiOptions.post,
      body: {'code': code},
    );

    if (response == null){
      return ApiError.connection;
    }
    if (response['status'] == 'ok') {
      setState(() {
        _validatedCodes.add(code);
      });
      return null;
    }
    return ApiError.from(response) ?? ApiError.connection;
  }

  // Funcion para traducir el fallo de la validacion al mensaje que ve el conductor
  String _validationMessage(ApiError error) {
    switch (error.code) {
      case ErrorCode.invalidValidationCode:
        return 'Ese código no corresponde a ningún pasajero de este viaje.';
      case ErrorCode.passengerAlreadyValidated:
        return 'Ese pasajero ya estaba validado.';
      case ErrorCode.passengerNotAccepted:
        return 'Ese pasajero no tiene una solicitud aceptada en este viaje.';
      case ErrorCode.tooManyRequests:
        return 'Demasiados intentos seguidos. Espera un momento.';
      case ErrorCode.insufficientCredentials:
        return 'Solo el conductor del viaje puede validar pasajeros.';
      default:
        return error.message;
    }
  }

  // Finaliza el viaje, los pasajeros no validados pasan a estado unvalidated
  Future<void> _finishTravel() async {
    final confirm = await showConfirmationModal(
      context,
      title: 'Finalizar viaje',
      message: '¿Quieres finalizar este viaje? Los pasajeros que no hayan sido validados quedarán como no validados.',
      confirmText: 'Finalizar',
      cancelText: 'Cancelar',
      barrierDismissible: false,
    );

    if (!confirm) return;

    final endpoint = '${dotenv.env['TRAVELS_ENDPOINT'] ?? '/travel/'}${widget.travel.id}${dotenv.env['FINISH_TRAVEL_ENDPOINT'] ?? '/finish_travel/'}';

    final response = await _api.requestToApi(
      endpoint,
      op: ApiOptions.post,
    );

    if (!mounted) return;

    if (response != null && response['status'] == 'ok') {
      // El viaje ha terminado, asi que se apaga el GPS
      _stopPositionUpdates();
      showModal(context, 'Viaje finalizado correctamente.', title: 'Éxito', type: AlertType.success, barrierDismissible: false, backPage: true, returnValue: true);
    }
    else {
      showModal(context, 'No se pudo finalizar el viaje. Inténtalo de nuevo.', barrierDismissible: false);
    }
  }

  // Obtiene el icono de maniobra segun el tipo de paso
  IconData _getManeuverIcon(int type) {
    switch (type) {
      case 0: return Icons.turn_left; // Giro a la izquierda
      case 1: return Icons.turn_right; // Giro a la derecha
      case 2: return Icons.turn_sharp_left;// Giro cerrado izquierda
      case 3: return Icons.turn_sharp_right;// Giro cerrado derecha
      case 4: return Icons.turn_slight_left;// Giro suave izquierda
      case 5: return Icons.turn_slight_right;// Giro suave derecha
      case 6: return Icons.straight; // Continuar recto
      case 7: return Icons.roundabout_left; // Entrar en la rotonda
      case 8: return Icons.roundabout_right; // Salir de la rotonda
      case 9: return Icons.u_turn_left; // Cambio de sentido
      case 10: return Icons.flag; // Llegada al destino
      case 11: return Icons.my_location;// Salida
      case 12: return Icons.turn_slight_left; // Mantenerse a la izquierda
      case 13: return Icons.turn_slight_right;// Mantenerse a la derecha
      default: return Icons.navigation;
    }
  }

  // Color de la pantalla
  Color _accent(AppColors colors) => colors.isDark ? const Color(0xFFA5B4FC) : AppColors.primary;

  // Funcion para constrir la pantalla
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final accent = _accent(colors);

    return Scaffold(
      backgroundColor: colors.background,
      body: _isLoadingRoute
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: accent),
                  const SizedBox(height: 16),
                  Text('Calculando ruta...', style: TextStyle(fontSize: 16, color: colors.textSecondary)),
                ],
              ),
            )
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentPosition ?? LatLng(widget.originLat, widget.originLng),
                    initialZoom: 14,
                    onMapReady: () {
                      if (!mounted) return;
                      setState(() {
                        _isMapReady = true;
                      });
                      if (_isFollowingUser && _currentPosition != null) {
                        _mapController.move(_currentPosition!, _mapController.camera.zoom);
                      }
                    },
                    onTap: (_, _) {
                      setState(() {
                        _isFollowingUser = false;
                      });
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.blablaucm.app',
                    ),

                    // Polilínea de la ruta
                    if (_routePoints.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _routePoints,
                            strokeWidth: 5.0,
                            color: const Color(0xFF4F46E5),
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(widget.originLat, widget.originLng),
                          width: 40, height: 40,
                          child: const Icon(Icons.trip_origin, color: Color(0xFF10B981), size: 32),
                        ),

                        // Marcadores de las paradas intermedias (naranja, numerados)
                        if (_pickupPoints.isNotEmpty)
                          ..._pickupPoints.asMap().entries.map((entry) => Marker(
                                point: entry.value,
                                width: 40, height: 40,
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF59E0B),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${entry.key + 1}',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ),
                                ),
                              )),

                        // Marcador del destino (rojo)
                        Marker(
                          point: LatLng(widget.destLat, widget.destLng),
                          width: 40, height: 40,
                          child: const Icon(Icons.location_on, color: Color(0xFFEF4444), size: 36),
                        ),

                        // Marcador de la posicion actual del conductor (azul)
                        if (_currentPosition != null)
                          Marker(
                            point: _currentPosition!,
                            width: 48, height: 48,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF4F46E5),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF4F46E5).withValues(alpha: 0.4),
                                    blurRadius: 10,
                                    spreadRadius: 3,
                                  ),
                                ],
                              ),
                              child: Transform.rotate(
                                angle: (_currentHeading ?? 0) * math.pi / 180,
                                child: const Icon(Icons.navigation, color: Colors.white, size: 22),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

                // Barra superior con informacion de la ruta
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: colors.isDark ? 0.4 : 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            // Boton para volver atras
                            GestureDetector(
                              onTap: () => Navigator.pop(context, false),
                              child: Icon(Icons.arrow_back, color: colors.textPrimary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${widget.travel.origin} → ${widget.travel.destination}',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: colors.textPrimary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (_routeResult != null)
                                    Text(
                                      '${OrsRoutingService.formatDistance(_progress?.remainingDistance ?? _routeResult!.totalDistance)}'
                                      ' · ${OrsRoutingService.formatDuration(_progress?.remainingDuration ?? _routeResult!.totalDuration)}',
                                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
                                    ),
                                ],
                              ),
                            ),
                            if (_isRecalculating)
                              SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                              ),
                          ],
                        ),

                        // Parada a la que se esta yendo y salto manual a la siguiente
                        if (_stopLabels.isNotEmpty) ...[
                          Divider(height: 20, color: colors.border),
                          Row(
                            children: [
                              Icon(
                                _hasReachedFinalDestination ? Icons.flag : Icons.place,
                                size: 20,
                                color: _hasReachedFinalDestination ? AppColors.success : accent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _hasReachedFinalDestination ? 'Viaje completado' : 'Yendo a',
                                      style: TextStyle(color: colors.textSecondary, fontSize: 11),
                                    ),
                                    Text(
                                      _hasReachedFinalDestination
                                        ? 'Has llegado al destino'
                                        : '${_getCurrentTargetLabel()} (${_currentStopIndex + 1}/${_stopLabels.length})',
                                      style: TextStyle(
                                        color: colors.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              // Solo se ofrece si queda alguna parada por delante
                              if (_hasNextStop)
                                TextButton.icon(
                                  onPressed: _confirmSkipToNextStop,
                                  icon: const Icon(Icons.skip_next, size: 18),
                                  label: const Text('Siguiente'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: accent,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    visualDensity: VisualDensity.compact,
                                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: colors.isDark ? 0.5 : 0.1),
                          blurRadius: 15,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Siguiente maniobra
                          if (_routeSteps.isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48, height: 48,
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: colors.isDark ? 0.22 : 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      _getManeuverIcon(_routeSteps[_displayStepIndex].type),
                                      color: accent,
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _routeSteps[_displayStepIndex].instruction,
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colors.textPrimary),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _distanceToNextManeuver >= 15
                                              ? 'En ${OrsRoutingService.formatDistance(_distanceToNextManeuver)}'
                                              : 'Ahora',
                                          style: TextStyle(color: colors.textSecondary, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: colors.surfaceLow,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '${_displayStepIndex + 1}/${_routeSteps.length}',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colors.textSecondary),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Row(
                              children: [
                                // Boton de validar pasajero
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _showValidationModal,
                                    icon: const Icon(Icons.qr_code_scanner, size: 20),
                                    label: const Text('Validar'),
                                    style: AppButtonStyles.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Boton de finalizar viaje
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _finishTravel,
                                    icon: const Icon(Icons.flag, size: 20),
                                    label: const Text('Finalizar'),
                                    style: AppButtonStyles.danger,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Boton para centrar en la posicion actual
                Positioned(
                  right: 16,
                  bottom: 200,
                  child: FloatingActionButton.small(
                    heroTag: 'centerBtn',
                    backgroundColor: colors.card,
                    tooltip: _isGpsActive ? 'Centrar en mi posición' : 'Reanudar la guía',
                    onPressed: _isRetryingGps
                      ? null
                      : () {
                          if (!_isGpsActive) {
                            _retryGps();
                            return;
                          }
                          if (_isMapReady && _currentPosition != null) {
                            setState(() {
                              _isFollowingUser = true;
                            });
                            _mapController.move(_currentPosition!, 16);
                          }
                        },
                    child: _isRetryingGps
                      ? SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                        )
                      : Icon(
                          !_isGpsActive
                              ? Icons.location_disabled
                              : _isFollowingUser ? Icons.my_location : Icons.location_searching,
                          color: _isGpsActive ? accent : colors.danger,
                        ),
                  ),
                ),
              ],
            ),
    );
  }
}

// Pantalla del lector de codigos QR
class _QrScannerScreen extends StatefulWidget {
  @override
  State<_QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<_QrScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _hasScanned = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear QR'),
        backgroundColor: const Color(0xFF4F46E5),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: (BarcodeCapture capture) {
              if (_hasScanned) return;
              final barcode = capture.barcodes.firstOrNull;
              if (barcode?.rawValue != null) {
                setState(() {
                  _hasScanned = true;
                });
                Navigator.pop(context, barcode!.rawValue);
              }
            },
          ),
          Center(
            child: Container(
              width: 250, height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF4F46E5), width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          // Texto informativo
          Positioned(
            bottom: 80,
            left: 0, right: 0,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Apunta la cámara al código QR del pasajero',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
