import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:latlong2/latlong.dart';

// Clase para representar un paso de la ruta con instrucciones
// Funciones basadas de la informacion ofrecida por OpenRouteService https://openrouteservice.org/

class RouteStep {
  final String instruction; // Instruccion de navegacion
  final double distance; // Distancia en metros de este paso
  final double duration; // Duracion en segundos de este paso
  final LatLng startPoint; // Punto de inicio de este paso
  final int type; // Tipo de maniobra (0=izquierda, 1=derecha, etc.)
  final int wayPointStart; // Indice en routePoints donde empieza el paso
  final int wayPointEnd; // Indice en routePoints donde acaba el paso (la maniobra)

  RouteStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.startPoint,
    required this.type,
    required this.wayPointStart,
    required this.wayPointEnd,
  });
}

// Clase para mostar el progreso del conductor sobre la ruta calculada.
class RouteProgress {
  final int stepIndex; // Paso que se esta recorriendo ahora mismo
  final int routeIndex; // Punto de la polilinea mas cercano al conductor
  final double distanceToManeuver; // Metros que faltan hasta la siguiente maniobra
  final double remainingDistance; // Metros que faltan hasta el final del tramo
  final double remainingDuration; // Segundos estimados hasta el final del tramo

  const RouteProgress({
    required this.stepIndex,
    required this.routeIndex,
    required this.distanceToManeuver,
    required this.remainingDistance,
    required this.remainingDuration,
  });
}

// Clase para representar el resultado completo de la ruta
class RouteResult {
  final List<LatLng> routePoints; // Todos los puntos de la ruta
  final List<RouteStep> steps; // Pasos con instrucciones
  final double totalDistance; // Distancia total en metros
  final double totalDuration; // Duracion total en segundos

  RouteResult({
    required this.routePoints,
    required this.steps,
    required this.totalDistance,
    required this.totalDuration,
  });
}

// Servicio para obtener rutas de conduccion desde OpenRouteService
class OrsRoutingService {
  final String _apiKey = dotenv.env['ORS_API_KEY'] ?? '';

  // Obtiene la ruta entre una lista de paradas
  Future<RouteResult?> getRoute(List<LatLng> waypoints) async {
    if (waypoints.length < 2) return null;

    final url = Uri.parse('https://api.openrouteservice.org/v2/directions/driving-car/geojson');

    // Se construyen las coordenadas en formato [lng, lat]
    final coordinates = waypoints.map((wp) => [wp.longitude, wp.latitude]).toList();

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json, application/geo+json',
          'Authorization': _apiKey,
        },
        body: json.encode({
          'coordinates': coordinates,
          'instructions': true,
          'language': 'es',
          'units': 'm',
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseRouteResponse(data);
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  // Parsea la respuesta GeoJSON de ORS para extraer la ruta y los pasos
  RouteResult? _parseRouteResponse(Map<String, dynamic> data) {
    try {
      final features = data['features'] as List;
      if (features.isEmpty) return null;

      final feature = features[0];
      final geometry = feature['geometry'];
      final properties = feature['properties'];

      final coords = geometry['coordinates'] as List;
      final routePoints = coords.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList();

      // Se extraen los datos del resumen
      final summary = properties['summary'];
      final totalDistance = (summary['distance'] as num).toDouble();
      final totalDuration = (summary['duration'] as num).toDouble();

      // Se extraen los pasos de navegacion
      final segments = properties['segments'] as List;
      final List<RouteStep> steps = [];

      for (final segment in segments) {
        final segSteps = segment['steps'] as List;
        for (final step in segSteps) {
          final wayPoints = step['way_points'] as List;
          final startIdx = (wayPoints[0] as int).clamp(0, routePoints.length - 1);
          final endIdx = (wayPoints[1] as int).clamp(0, routePoints.length - 1);
          final startCoord = coords[startIdx];
          steps.add(RouteStep(
            instruction: step['instruction'] ?? '',
            distance: (step['distance'] as num).toDouble(),
            duration: (step['duration'] as num).toDouble(),
            startPoint: LatLng(startCoord[1].toDouble(), startCoord[0].toDouble()),
            type: step['type'] ?? 0,
            wayPointStart: startIdx,
            wayPointEnd: endIdx,
          ));
        }
      }

      return RouteResult(
        routePoints: routePoints,
        steps: steps,
        totalDistance: totalDistance,
        totalDuration: totalDuration,
      );
    } catch (e) {
      return null;
    }
  }

  // Calcula la distancia minima desde un punto a la linea de la ruta
  static double distanceToRoute(LatLng point, List<LatLng> routePoints) {
    double minDist = double.infinity;
    const distance = Distance();

    for (int i = 0; i < routePoints.length - 1; i++) {
      final d = _distanceToSegment(point, routePoints[i], routePoints[i + 1], distance);
      if (d < minDist) minDist = d;
    }
    return minDist;
  }

  // Calcula la distancia perpendicular de un punto a un segmento de linea
  static double _distanceToSegment(LatLng point, LatLng segA, LatLng segB, Distance distCalc) {
    final dAB = distCalc.as(LengthUnit.Meter, segA, segB);
    if (dAB < 1) return distCalc.as(LengthUnit.Meter, point, segA);

    final dAP = distCalc.as(LengthUnit.Meter, segA, point);
    final dBP = distCalc.as(LengthUnit.Meter, segB, point);

    final s = (dAP * dAP - dBP * dBP + dAB * dAB) / (2 * dAB);

    if (s < 0) return dAP;
    if (s > dAB) return dBP;

    final h2 = dAP * dAP - s * s;
    return h2 > 0 ? sqrt(h2) : 0;
  }

  // Distancia maxima de ruta que se explora por delante del punto ya alcanzado
  static const double _progressSearchWindow = 2000.0;

  // Funcion para calcular por donde va el conductor proyectando su posicion sobre la ruta
  static RouteProgress computeProgress(LatLng currentPos, RouteResult route, {int fromStepIndex = 0}) {
    final points = route.routePoints;
    final steps = route.steps;

    if (points.length < 2 || steps.isEmpty) {
      return const RouteProgress(
        stepIndex: 0,
        routeIndex: 0,
        distanceToManeuver: 0,
        remainingDistance: 0,
        remainingDuration: 0,
      );
    }

    const distance = Distance();
    final safeFrom = fromStepIndex.clamp(0, steps.length - 1);
    final searchStart = steps[safeFrom].wayPointStart.clamp(0, points.length - 1);

    // Se busca el punto de la ruta mas cercano dentro de la ventana de busqueda
    int closestIdx = searchStart;
    double minDist = double.infinity;
    double walked = 0;
    for (int i = searchStart; i < points.length; i++) {
      if (i > searchStart) {
        walked += distance.as(LengthUnit.Meter, points[i - 1], points[i]);
        if (walked > _progressSearchWindow) break;
      }
      final d = distance.as(LengthUnit.Meter, currentPos, points[i]);
      if (d < minDist) {
        minDist = d;
        closestIdx = i;
      }
    }

    // Se localiza el paso que contiene ese punto de la ruta
    int stepIndex = safeFrom;
    for (int i = safeFrom; i < steps.length; i++) {
      if (closestIdx < steps[i].wayPointEnd) {
        stepIndex = i;
        break;
      }
      stepIndex = i;
    }

    // Distancia que queda hasta la siguiente maniobra
    final maneuverIdx = steps[stepIndex].wayPointEnd.clamp(0, points.length - 1);
    double distanceToManeuver = 0;
    for (int i = closestIdx; i < maneuverIdx; i++) {
      distanceToManeuver += distance.as(LengthUnit.Meter, points[i], points[i + 1]);
    }

    double remainingDistance = distanceToManeuver;
    for (int i = maneuverIdx; i < points.length - 1; i++) {
      remainingDistance += distance.as(LengthUnit.Meter, points[i], points[i + 1]);
    }

    final currentStep = steps[stepIndex];
    double remainingDuration = currentStep.distance > 0
        ? currentStep.duration * (distanceToManeuver / currentStep.distance).clamp(0.0, 1.0)
        : 0;
    for (int i = stepIndex + 1; i < steps.length; i++) {
      remainingDuration += steps[i].duration;
    }

    return RouteProgress(
      stepIndex: stepIndex,
      routeIndex: closestIdx,
      distanceToManeuver: distanceToManeuver,
      remainingDistance: remainingDistance,
      remainingDuration: remainingDuration,
    );
  }

  // Formatea la distancia para mostarla al usuario
  static String formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.toInt()} m';
  }

  // Formatea la duracion para mostrarla al usuario
  static String formatDuration(double seconds) {
    final mins = (seconds / 60).ceil();
    if (mins >= 60) {
      final hours = mins ~/ 60;
      final remainMins = mins % 60;
      return '${hours}h ${remainMins}min';
    }
    return '$mins min';
  }
}
