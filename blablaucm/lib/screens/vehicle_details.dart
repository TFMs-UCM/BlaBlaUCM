import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:blablaucm/models/vehicle_model.dart';
import 'package:blablaucm/models/enums.dart';

class VehicleDetailsScreen extends StatelessWidget {
  final VehicleModel vehicle;
  final bool editMode;

  final TextEditingController plateCtrl;
  final TextEditingController brandCtrl;
  final TextEditingController modelCtrl;
  final TextEditingController seatsCtrl;

  final Function(EnvSticker?) onEnvStickerChanged;

  const VehicleDetailsScreen({
    super.key,
    required this.vehicle,
    required this.editMode,
    required this.plateCtrl,
    required this.brandCtrl,
    required this.modelCtrl,
    required this.seatsCtrl,
    required this.onEnvStickerChanged,
  });

  @override
  Widget build(BuildContext context) {
    final v = vehicle;

    return Center(
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.directions_car,
                      size: 70,
                      color: Colors.blue,
                    ),
                    const SizedBox(height: 18),

                    _infoRow("Matrícula", v.plate, plateCtrl),
                    _infoRow("Marca", v.brand, brandCtrl),
                    _infoRow("Modelo", v.model, modelCtrl),

                    _infoRowEnvSticker(
                      "Distintivo ambiental",
                      v.envSticker,
                    ),

                    _infoRow(
                      "Número de asientos",
                      v.numSeats.toString(),
                      seatsCtrl,
                      isNumber: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(
    String label,
    String value,
    TextEditingController? controller, {
    bool isNumber = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: editMode && controller != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: controller,
                  keyboardType:
                      isNumber ? TextInputType.number : TextInputType.text,
                  inputFormatters: isNumber
                      ? [FilteringTextInputFormatter.digitsOnly]
                      : [],
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  ),
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w500),
                ),
                Text(
                  value,
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
    );
  }

  Widget _infoRowEnvSticker(String label, EnvSticker? current) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: editMode
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<EnvSticker>(
                  initialValue: current,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  ),
                  items: EnvSticker.values.map((sticker) {
                    return DropdownMenuItem(
                      value: sticker,
                      child: Text(sticker.label),
                    );
                  }).toList(),
                  onChanged: onEnvStickerChanged,
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w500),
                ),
                Text(
                  current?.label ?? "N/A",
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
    );
  }
}