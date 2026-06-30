import 'package:flutter/material.dart';
import 'package:blablaucm/models/vehicle_model.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/screens/custom_form_fields.dart';
import 'package:blablaucm/screens/env_sticker_widget.dart';

// Pantalla para mostrar los detalles de un vehiculo, si esta en modo edicion, se permite modificar los campos

class VehicleDetailsScreen extends StatelessWidget {
  final VehicleModel vehicle;
  final bool editMode; // Indica si esta en modo edicion o solo visualizacion

  final TextEditingController plateCtrl;
  final TextEditingController brandCtrl;
  final TextEditingController modelCtrl;
  final TextEditingController seatsCtrl;

  final Function(EnvSticker?) onEnvStickerChanged;
  final Function(CarColor?) onColorChanged;
  final String? plateError;
  final String? seatsError;

  const VehicleDetailsScreen({
    super.key,
    required this.vehicle,
    required this.editMode,
    required this.plateCtrl,
    required this.brandCtrl,
    required this.modelCtrl,
    required this.seatsCtrl,
    required this.onEnvStickerChanged,
    required this.onColorChanged,
    this.plateError,
    this.seatsError,
  });

  // Funcion para construir la pantalla
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Icon(
                          Icons.directions_car,
                          size: 70,
                          color: Colors.blue,
                        ),
                        const SizedBox(width: 6),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: EnvStickerBadge(sticker: v.envSticker, size: 32, showEmpty: true),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Se ponen las filas por cada elemento del vehiculo
                    // Se añade el campo de la matricula
                    buildInfoRow(
                      label: "Matrícula",
                      value: v.plate,
                      controller: plateCtrl,
                      editMode: editMode,
                      errorText: plateError,
                      maxLength: 10,
                    ),
                    // Se añade el campo de la marca
                    buildInfoRow(
                      label: "Marca",
                      value: v.brand,
                      controller: brandCtrl,
                      editMode: editMode,
                    ),
                    // Se añade el campo del modelo
                    buildInfoRow(
                      label: "Modelo",
                      value: v.model,
                      controller: modelCtrl,
                      editMode: editMode,
                    ),
                    // Se añade el campo del numero de asientos
                    buildInfoRow(
                      label: "Número de asientos",
                      value: v.numSeats.toString(),
                      controller: seatsCtrl,
                      editMode: editMode,
                      isNumber: true,
                      errorText: seatsError,
                      tooltipText: editMode ? "Indica el número total de asientos del vehículo, incluyendo el del conductor. Debe ser un número entre 2 y 10." : null,
                    ),
                    
                    // El distintivo ambiental se muestra junto al icono del vehiculo en modo visualizacion
                    // En modo edicion se muestra el desplegable para poder cambiarlo
                    if (editMode)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            buildLabelWidget("Etiqueta medioambiental", null),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<EnvSticker>(
                              initialValue: v.envSticker,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              ),
                              items: EnvSticker.values.map((envSticker) {
                                return DropdownMenuItem(
                                  value: envSticker,
                                  child: Row(
                                    children: [
                                      EnvStickerBadge(sticker: envSticker == EnvSticker.all ? null : envSticker, showEmpty: true),
                                      const SizedBox(width: 10),
                                      Text(envSticker.label),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) => onEnvStickerChanged(value),
                            ),
                          ],
                        ),
                      ),
                    // Se añade un menu desplegable para el color del vehiculo
                    buildDropdownRow<CarColor>(
                      label: "Color",
                      currentValue: v.color,
                      items: CarColor.values,
                      editMode: editMode,
                      onChanged: onColorChanged,
                      labelGetter: (color) => color.label,
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
}