import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/models/travel_model.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/screens/helper.dart';
import 'package:blablaucm/screens/travel_details.dart';
import 'package:blablaucm/theme/app_colors.dart';

// Pantalla de solo lectura que muestra el detalle de un viaje a partir de su id.

class TravelViewScreen extends StatefulWidget {
  final String travelId; // id del viaje a mostrar

  const TravelViewScreen({super.key, required this.travelId});

  @override
  State<TravelViewScreen> createState() => _TravelViewScreenState();
}

class _TravelViewScreenState extends State<TravelViewScreen> {
  final ApiService _api = ApiService();

  TravelModel? _travel;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadTravel();
  }

  // Funcion para cargar el viaje
  Future<void> _loadTravel() async {
    try {
      // Se crea el endpoint
      final endpoint = "${dotenv.env['TRAVELS_ENDPOINT'] ?? '/travel/'}${widget.travelId}/";
      // Se realiza la peticion a la api
      final response = await _api.requestToApi(endpoint);

      if (response == null || response['id_travel'] == null) {
        throw Exception("Respuesta no válida del servidor");
      }

      final travel = TravelModel.fromJson(response);

      // Se añaden los datos extra
      final extra = await fetchTravelExtraData(travelId: widget.travelId, api: _api);
      travel.driver.addRatings(extra.rawRatings);
      travel.driver.numRatings = extra.numRatings;
      travel.driver.preferences = extra.preferences;
      travel.pickUpPoints = extra.pickUpPoints;
      travel.addPassengers(extra.passengers);
      travel.deniedRoles = extra.deniedRoles;

      if (!mounted) return;
      setState(() {
        _travel = travel;
        _isLoading = false;
      });
    } 
    catch (_) { // Si hay un error, se muestra un mensaje de error al usuario
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  // Funcion para construir la pantalla
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text("Detalles del viaje")),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _hasError || _travel == null
          ? Center( // Si no se puede cargar el viaje, se muestra un mensaje de error
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 56, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text(
                      "No se pudo cargar el viaje.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            )
          : TravelDetailsScreen(travel: _travel!), // SI si se puede, se muestran los datos del viaje
    );
  }
}
