import 'package:flutter/material.dart';
import 'package:blablaucm/models/vehicle_model.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/providers/storage_provider.dart';
import 'package:blablaucm/screens/helper.dart';
import 'package:blablaucm/screens/custom_form_fields.dart'; 

// Pantalla para mostrar los detalles de un vehiculo cuando se crea un viaje
class CreatedVehicleDetailsScreen extends StatefulWidget {
  final Function(VehicleModel) onSave;

  const CreatedVehicleDetailsScreen({
    super.key,
    required this.onSave,
  });

  @override
  State<CreatedVehicleDetailsScreen> createState() => _CreatedVehicleDetailsScreenState();
}

class _CreatedVehicleDetailsScreenState extends State<CreatedVehicleDetailsScreen> {
  final plateCtrl = TextEditingController();
  final brandCtrl = TextEditingController();
  final modelCtrl = TextEditingController();
  final seatsCtrl = TextEditingController();

  EnvSticker? envSticker;
  CarColor? carColor;

  final ApiService api = ApiService();
  final SecureStorageService storage = SecureStorageService();

  bool isSaving = false;

  // Funcion para mostrar un mensaje de error en la parte inferior de la pantalla
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red));
  }

  // Funcion para enviar a la api los datos del vehiculo para crearlo
  Future<void> _save() async {
    final plate = plateCtrl.text.trim();
    final brand = brandCtrl.text.trim();
    final model = modelCtrl.text.trim();
    final numSeats = int.tryParse(seatsCtrl.text) ?? 0;

    // Antes de enviarlo a la api, se hacen las validaciones de los campos

    // Se comprueba que no haya campos vacios
    if (plate.isEmpty || brand.isEmpty || model.isEmpty || numSeats <= 0) {
      _showError("La matricula, marca, modelo y número de asientos son obligatorios.");
      return;
    }

    // Evita que se envie una matricula demasiado larga, aunque ya se impide en el TextField
    if (plate.length > 10) {
      _showError("La matrícula no puede tener más de 10 caracteres.");
      return;
    }

    // Se comprueba que el numero de asientos sea correcto, debe ser entre 2 y 10, ya que el conductor consume una plaza
    if (numSeats < 2 || numSeats > 10) {
      _showError("El número de asientos debe estar entre 2 y 10.");
      return;
    }

    // Se rellenan los datos del vehiculo con los de los campos
    final userId = await storage.getElement("user_id");
    final vehicleData = {
      "license_plate": plate,
      "brand": brand,
      "model": model,
      "color": carColor?.name.toUpperCase() ?? CarColor.none.name.toUpperCase(),
      "seats": numSeats,
      "env_sticker": envSticker?.name ?? EnvSticker.all.name,
      "id_user": userId,
    };

    setState(() => isSaving = true);

    try {
      // Se crea la url
      final endpoint = "/vehicles/";
      // Se realiza la peticion a la api
      final response = await api.requestToApi(endpoint, op: ApiOptions.post, body: vehicleData);
      
      // Si la respeusta es nula o tiene un error, muestra un mensaje de error
      if (response == null || response["error"] != null) {
        if (!context.mounted) return;
        final errorMessage = response?["error"]["message"] ?? "Error al crear vehículo";
        showModal(context, errorMessage);
      } 
      else {// Si ha ido todo bien, se añade el vehiculo
        final vehicle = VehicleModel(
          id: response["id_vehicle"]?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
          plate: plate,
          brand: brand,
          model: model,
          numSeats: numSeats,
          envSticker: envSticker,
          color: carColor,
          userId: userId
        );

        widget.onSave(vehicle);
        if (!context.mounted) return;
        Navigator.pop(context);
      }
    } 
    catch (e) { // Si hay un error no manejado, se muestra un mensaje de error generico
      _showError("Error de conexión, inténtalo de nuevo.");
    } 
    finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  // FUncion para crear la pantalla
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Nuevo vehículo"),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const Icon(
                        Icons.directions_car,
                        size: 70,
                        color: Colors.blue,
                      ),
                      const SizedBox(height: 20),
                      // Se pone cada dato en un campo en una fila
                      buildInfoRow( // Campo de la matricula
                        label: "Matrícula",
                        value: "", // Como es se va a editar, no se usa este campo, ya que editMode es true y hay un controlador
                        controller: plateCtrl,
                        editMode: true,
                        maxLength: 10, // Se limita el tamaño a 10 para que no se pueda introducir mas
                      ),
                      buildInfoRow( // Campo de la marca
                        label: "Marca",
                        value: "",
                        controller: brandCtrl,
                        editMode: true,
                      ),
                      buildInfoRow( // Campo del modelo
                        label: "Modelo",
                        value: "",
                        controller: modelCtrl,
                        editMode: true,
                      ),
                      buildInfoRow( // Campo del numero de asientos
                        label: "Número de asientos",
                        value: "",
                        controller: seatsCtrl,
                        editMode: true,
                        isNumber: true, // Solo se pueden introducir numeros
                        // Se muestra un mensaje de ayuda para el usuario
                        tooltipText: "Indica el número total de asientos del vehículo, incluyendo el del conductor. Debe ser un número entre 2 y 10.",
                      ),
                      
                      buildDropdownRow<EnvSticker>( // Campo del distintivo ambiental
                        label: "Distintivo ambiental",
                        currentValue: envSticker,
                        items: EnvSticker.values,
                        editMode: true,
                        onChanged: (val) => setState(() => envSticker = val),
                        labelGetter: (e) => e.label,
                      ),
                      buildDropdownRow<CarColor>( // Campo del color
                        label: "Color",
                        currentValue: carColor,
                        items: CarColor.values,
                        editMode: true,
                        onChanged: (val) => setState(() => carColor = val),
                        labelGetter: (c) => c.label,
                      ),
                      
                      const SizedBox(height: 30),
                      
                      isSaving // Cuando se le da a guardar se muestra un mensaje de guardando
                          ? const Text("Guardando...", style: TextStyle(fontSize: 16))
                          : Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton( // Boton de cancelar
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text("Cancelar"),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: ElevatedButton( // Boton de guardar
                                    onPressed: _save, // El checkeo de los campos se hace al pulsar en guardar
                                    child: const Text("Guardar"),
                                  ),
                                ),
                              ],
                            ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}