import 'package:flutter/material.dart';
import 'package:blablaucm/models/vehicle_model.dart';
import 'package:blablaucm/models/enums.dart';

class CreatedVehicleDetailsScreen extends StatefulWidget {

  final Function(VehicleModel) onSave;

  const CreatedVehicleDetailsScreen({
    super.key,
    required this.onSave,
  });

  @override
  State<CreatedVehicleDetailsScreen> createState() =>
      _CreatedVehicleDetailsScreenState();
}

class _CreatedVehicleDetailsScreenState
    extends State<CreatedVehicleDetailsScreen> {

  final plateCtrl = TextEditingController();
  final brandCtrl = TextEditingController();
  final modelCtrl = TextEditingController();
  final seatsCtrl = TextEditingController();

  EnvSticker? envSticker;

  void _save() {

    final vehicle = VehicleModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      plate: plateCtrl.text,
      brand: brandCtrl.text,
      model: modelCtrl.text,
      numSeats: int.tryParse(seatsCtrl.text) ?? 0,
      envSticker: envSticker,
    );

    widget.onSave(vehicle);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text("Nuevo vehículo"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [

            TextField(
              controller: plateCtrl,
              decoration:
                  const InputDecoration(labelText: "Matrícula"),
            ),

            TextField(
              controller: brandCtrl,
              decoration:
                  const InputDecoration(labelText: "Marca"),
            ),

            TextField(
              controller: modelCtrl,
              decoration:
                  const InputDecoration(labelText: "Modelo"),
            ),

            TextField(
              controller: seatsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Número de asientos",
              ),
            ),

            DropdownButtonFormField<EnvSticker>(
              decoration: const InputDecoration(
                  labelText: "Distintivo ambiental"),
              items: EnvSticker.values.map((e) {
                return DropdownMenuItem(
                  value: e,
                  child: Text(e.label),
                );
              }).toList(),
              onChanged: (val) {
                envSticker = val;
              },
            ),

            const SizedBox(height: 30),

            Row(
              children: [

                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text("Cancelar"),
                  ),
                ),

                const SizedBox(width: 16),

                Expanded(
                  child: ElevatedButton(
                    onPressed: _save,
                    child: const Text("Guardar"),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}