import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/models/travel_model.dart';
import 'package:blablaucm/models/pick_up_points_model.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/services/route_services/ors_routing_service.dart';
import 'package:blablaucm/screens/helper.dart';

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
  bool _isFollowingUser = true;

  // Estado de la ruta
  RouteResult? _routeResult;
  List<LatLng> _routePoints = [];
  List<RouteStep> _routeSteps = [];
  int _currentStepIndex = 0;
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
  static const double _arrivalThreshold = 35.0;
  // Tiempo minimo entre recalculos para no saturar la API
  DateTime? _lastRecalculationTime;
  static const Duration _minRecalculationInterval = Duration(seconds: 15);

  // Lista de pasajeros validados
  final Set<String> _validatedCodes = {};

  @override
  void initState() {
    super.initState();
    _initLocationAndRoute();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  // Se inicializa el GPS y calcula la ruta inicial
  Future<void> _initLocationAndRoute() async {
    await _initGps();
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

  // Inicializa el servicio de geolocalizacion
  Future<void> _initGps() async {
    // Se comprueba que el servicio de localizacion este habilitado
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        showModal(context, 'Por favor, activa el GPS para usar la navegación.');
      }
      return;
    }

    // Se comprueba y solicita los permisos de ubicacion
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          showModal(context, 'Se necesitan permisos de ubicación para la navegación.');
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        showModal(context, 'Los permisos de ubicación están permanentemente denegados. Actívalos en ajustes.');
      }
      return;
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

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Se actualiza cada 10 metros de movimiento
      ),
    ).listen((Position position) async {
      if (!mounted) return;
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
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
    });
  }

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
      });

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

  // Actualiza el paso actual basandose en la posicion del conductor
  void _updateCurrentStep() {
    if (_routeSteps.isEmpty || _currentPosition == null) return;
    final newIndex = OrsRoutingService.findCurrentStepIndex(_currentPosition!, _routeSteps);
    if (newIndex != _currentStepIndex) {
      setState(() {
        _currentStepIndex = newIndex;
      });
    }
  }

  // Comprueba si el conductor ha llegado a la parada actual y si ha llegado avanza a la siguiente
  Future<void> _checkArrivalToTarget() async {
    if (_hasReachedFinalDestination || _currentPosition == null || _isAdvancingStop) return;
    final target = _getCurrentTarget();
    if (target == null) return;
    if (_currentStopIndex == _lastArrivalStopIndex) return;

    final distToTarget = _distanceCalc.as(LengthUnit.Meter, _currentPosition!, target);
    if (distToTarget <= _arrivalThreshold) {
      _lastArrivalStopIndex = _currentStopIndex;
      _isAdvancingStop = true;
      await _advanceToNextStop();
      _isAdvancingStop = false;
    }
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
    bool isValidating = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.verified_user, color: Color(0xFF4F46E5)),
                  SizedBox(width: 8),
                  Text('Validar Pasajero'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Introduce el código del pasajero o escanea su QR',
                    style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  // Campo para introducir el codigo manualmente
                  TextField(
                    controller: codeController,
                    decoration: InputDecoration(
                      labelText: 'Código de validación',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.confirmation_number),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
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
                  child: const Text('Cancelar', style: TextStyle(color: Color(0xFF6B7280))),
                ),
                ElevatedButton(
                  onPressed: isValidating ? null : () async {
                    final code = codeController.text.trim();
                    if (code.isEmpty) return;

                    setDialogState(() {
                      isValidating = true;
                    });

                    // Se llama a la API para validar al pasajero
                    final success = await _validatePassenger(code);

                    setDialogState(() {
                      isValidating = false;
                    });

                    if (!dialogContext.mounted) return;

                    if (success) {
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
                        const SnackBar(
                          content: Text('Código no válido o pasajero no encontrado'),
                          backgroundColor: Color(0xFFEF4444),
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

  // Llama a la API para validar un pasajero con su codigo
  Future<bool> _validatePassenger(String code) async {
    final endpoint = '${dotenv.env['TRAVELS_ENDPOINT'] ?? '/travel/'}${widget.travel.id}${dotenv.env['VALIDATE_PASSENGER_ENDPOINT'] ?? '/validate_passenger/'}';

    final response = await _api.requestToApi(
      endpoint,
      op: ApiOptions.post,
      body: {'code': code},
    );

    if (response != null && response['status'] == 'ok') {
      setState(() {
        _validatedCodes.add(code);
      });
      return true;
    }
    return false;
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
      case 7: return Icons.roundabout_left; // Rotonda
      case 10: return Icons.flag; // Llegada al destino
      case 11: return Icons.my_location;// Salida
      default: return Icons.navigation;
    }
  }

  // Funcion para constrir la pantalla
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoadingRoute
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF4F46E5)),
                  SizedBox(height: 16),
                  Text('Calculando ruta...', style: TextStyle(fontSize: 16, color: Color(0xFF6B7280))),
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
                              child: const Icon(Icons.navigation, color: Colors.white, size: 22),
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Boton para volver atras
                        GestureDetector(
                          onTap: () => Navigator.pop(context, false),
                          child: const Icon(Icons.arrow_back, color: Color(0xFF4B5563)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${widget.travel.origin} → ${widget.travel.destination}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (_routeResult != null)
                                Text(
                                  '${OrsRoutingService.formatDistance(_routeResult!.totalDistance)} · ${OrsRoutingService.formatDuration(_routeResult!.totalDuration)}',
                                  style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                                ),
                              if (_stopLabels.isNotEmpty)
                                Text(
                                  _hasReachedFinalDestination
                                      ? 'Has llegado al destino'
                                      : 'Destino actual: ${_getCurrentTargetLabel()} (${_currentStopIndex + 1}/${_stopLabels.length})',
                                  style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                                ),
                            ],
                          ),
                        ),
                        if (_isRecalculating)
                          const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4F46E5)),
                          ),
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
                      color: Colors.white,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
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
                          // Instruccion actual
                          if (_routeSteps.isNotEmpty && _currentStepIndex < _routeSteps.length)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48, height: 48,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      _getManeuverIcon(_routeSteps[_currentStepIndex].type),
                                      color: const Color(0xFF4F46E5),
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _routeSteps[_currentStepIndex].instruction,
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          OrsRoutingService.formatDistance(_routeSteps[_currentStepIndex].distance),
                                          style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF3F4F6),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '${_currentStepIndex + 1}/${_routeSteps.length}',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF6B7280)),
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
                    backgroundColor: Colors.white,
                    onPressed: () {
                      if (_isMapReady && _currentPosition != null) {
                        setState(() {
                          _isFollowingUser = true;
                        });
                        _mapController.move(_currentPosition!, 16);
                      }
                    },
                    child: Icon(
                      _isFollowingUser ? Icons.my_location : Icons.location_searching,
                      color: const Color(0xFF4F46E5),
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
