import 'package:blablaucm/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:blablaucm/models/vehicle_model.dart';
import 'package:flutter/services.dart';

class VehicleDetailsScreen extends StatefulWidget {
  final VehicleModel vehicle;
  final Function(VehicleModel) onDelete;   // callback para eliminar
  final Function(VehicleModel) onUpdate;   // callback para actualizar

  const VehicleDetailsScreen({
    super.key,
    required this.vehicle,
    required this.onDelete,
    required this.onUpdate,
  });

  @override
  State<VehicleDetailsScreen> createState() => _VehicleDetailsScreenState();
}

class _VehicleDetailsScreenState extends State<VehicleDetailsScreen> {
  bool editMode = false;

  late TextEditingController plateCtrl;
  late TextEditingController brandCtrl;
  late TextEditingController modelCtrl;
  late TextEditingController seatsCtrl;
  late VehicleModel localVehicle;

  @override
  void initState() {
    super.initState();
    plateCtrl = TextEditingController(text: widget.vehicle.plate);
    brandCtrl = TextEditingController(text: widget.vehicle.brand);
    modelCtrl = TextEditingController(text: widget.vehicle.model);
    seatsCtrl = TextEditingController(text: widget.vehicle.numSeats.toString());
    localVehicle = widget.vehicle;
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Eliminar vehículo"),
          content: Text(
            "¿Seguro que quieres eliminar el vehículo:\n\n${widget.vehicle.vehiclePreview()}?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: () {
                widget.onDelete(widget.vehicle);
                Navigator.pop(context); // cerrar modal
                Navigator.pop(context); // volver atrás
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text("Eliminar"),
            ),
          ],
        );
      },
    );
  }

  void _cancelEdit() {
  setState(() {
    // Restaurar los valores originales
    plateCtrl.text = widget.vehicle.plate;
    brandCtrl.text = widget.vehicle.brand;
    modelCtrl.text = widget.vehicle.model;
    seatsCtrl.text = widget.vehicle.numSeats.toString();
    localVehicle = widget.vehicle;

    editMode = false;
  });
}


  void _confirmSave() {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text("Confirmar cambios"),
        content: const Text(
          "¿Deseas guardar las modificaciones realizadas en este vehículo?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // cerrar modal
              _saveChanges();         // guardar cambios reales
            },
            child: const Text("Guardar"),
          ),
        ],
      );
    },
  );
}


  void _saveChanges() {
    final updated = VehicleModel(
      id: widget.vehicle.id,
      plate: plateCtrl.text,
      brand: brandCtrl.text,
      model: modelCtrl.text,
      numSeats: int.tryParse(seatsCtrl.text) ?? widget.vehicle.numSeats,
      envSticker: localVehicle.envSticker,
    );

    widget.onUpdate(updated);

    setState(() {
      localVehicle = updated;   
      editMode = false;
    });
  }


  @override
  Widget build(BuildContext context) {
    final v = localVehicle;


    return Scaffold(
      appBar: AppBar(
        title: const Text("Detalles del vehículo"),
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.directions_car, size: 70, color: Colors.blue),
                      const SizedBox(height: 18),

                      _infoRow("Matrícula", v.plate, plateCtrl),
                      _infoRow("Marca", v.brand, brandCtrl),
                      _infoRow("Modelo", v.model, modelCtrl),
                      _infoRowEnvSticker("Distintivo ambiental", v.envSticker),
                      // TODO Antes de permitir cambiar el numero de asientos, verificar que no haya viajes que sobrepasen ese nuevo limite
                      _infoRow("Número de asientos", v.numSeats.toString(), seatsCtrl, isNumber: true),
                      
                      const SizedBox(height: 18),

                      if (!editMode)
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _confirmDelete, // TODO Llamar al WS para que borre el vehiculo
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red, // TODO Cambiar el color
                                ),
                                child: const Text("Eliminar"),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  setState(() => editMode = true);
                                },
                                child: const Text("Editar"),
                              ),
                            ),
                          ],
                        ),

                      if (editMode)
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _cancelEdit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey.shade300,
                                  foregroundColor: Colors.black,
                                ),
                                child: const Text("Cancelar"),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _confirmSave, // TODO Llamar al WS para que guarde los nuevos datos del vehiculo
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

  Widget _infoRow(String label,String value,TextEditingController? controller, {bool isNumber = false,}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: editMode && controller != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                TextField(
                  controller: controller,
                  keyboardType: isNumber ? TextInputType.number : TextInputType.text,
                  inputFormatters: isNumber
                      ? [FilteringTextInputFormatter.digitsOnly]
                      : [],
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  ),
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                Text(value, style: const TextStyle(fontSize: 16)),
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
                Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                DropdownButtonFormField<EnvSticker>(
                  initialValue: current,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  ),
                  items: EnvSticker.values.map((sticker) {
                    return DropdownMenuItem(
                      value: sticker,
                      child: Text(sticker.label),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      localVehicle = VehicleModel(
                        id: localVehicle.id,
                        plate: localVehicle.plate,
                        brand: localVehicle.brand,
                        model: localVehicle.model,
                        numSeats: localVehicle.numSeats,
                        envSticker: value,
                      );
                    });
                  },
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                Text(current?.label ?? "N/A", style: const TextStyle(fontSize: 16)),
              ],
            ),
    );
  }
}
