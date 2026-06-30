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

  RouteStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.startPoint,
    required this.type,
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
          final startIdx = wayPoints[0] as int;
          // Se obtiene el punto de inicio de cada paso
          final startCoord = coords[startIdx];
          steps.add(RouteStep(
            instruction: step['instruction'] ?? '',
            distance: (step['distance'] as num).toDouble(),
            duration: (step['duration'] as num).toDouble(),
            startPoint: LatLng(startCoord[1].toDouble(), startCoord[0].toDouble()),
            type: step['type'] ?? 0,
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

  // Encuentra el indice del paso actual basandose en la posicion del conductor
  static int findCurrentStepIndex(LatLng currentPos, List<RouteStep> steps) {
    const distance = Distance();
    double minDist = double.infinity;
    int closestIdx = 0;

    for (int i = 0; i < steps.length; i++) {
      final d = distance.as(LengthUnit.Meter, currentPos, steps[i].startPoint);
      if (d < minDist) {
        minDist = d;
        closestIdx = i;
      }
    }
    return closestIdx;
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
