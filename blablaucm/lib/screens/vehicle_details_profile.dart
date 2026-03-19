import 'package:flutter/material.dart';
import 'package:blablaucm/models/vehicle_model.dart';
import 'package:blablaucm/screens/vehicle_details.dart';

class VehicleDetailsProfileScreen extends StatefulWidget {
  final VehicleModel vehicle;
  final Function(VehicleModel) onDelete;
  final Function(VehicleModel) onUpdate;

  const VehicleDetailsProfileScreen({
    super.key,
    required this.vehicle,
    required this.onDelete,
    required this.onUpdate,
  });

  @override
  State<VehicleDetailsProfileScreen> createState() =>
      _VehicleDetailsProfileScreenState();
}

class _VehicleDetailsProfileScreenState
    extends State<VehicleDetailsProfileScreen> {
  bool editMode = false;

  late TextEditingController plateCtrl;
  late TextEditingController brandCtrl;
  late TextEditingController modelCtrl;
  late TextEditingController seatsCtrl;

  late VehicleModel localVehicle;

  @override
  void initState() {
    super.initState();

    localVehicle = widget.vehicle;

    plateCtrl = TextEditingController(text: widget.vehicle.plate);
    brandCtrl = TextEditingController(text: widget.vehicle.brand);
    modelCtrl = TextEditingController(text: widget.vehicle.model);
    seatsCtrl =
        TextEditingController(text: widget.vehicle.numSeats.toString());
  }

  void _cancelEdit() {
    setState(() {
      plateCtrl.text = widget.vehicle.plate;
      brandCtrl.text = widget.vehicle.brand;
      modelCtrl.text = widget.vehicle.model;
      seatsCtrl.text = widget.vehicle.numSeats.toString();

      localVehicle = widget.vehicle;
      editMode = false;
    });
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                widget.onDelete(widget.vehicle);
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text("Eliminar"),
            ),
          ],
        );
      },
    );
  }

  void _confirmSave() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Confirmar cambios"),
          content: const Text(
              "¿Deseas guardar las modificaciones realizadas en este vehículo?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _saveChanges();
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

  Widget _buildButtons() {
    if (!editMode) {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: _confirmDelete,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
      );
    }

    return Row(
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
            onPressed: _confirmSave,
            child: const Text("Guardar"),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Detalles del vehículo"),
      ),
      body: Column(
        children: [
          Expanded(
            child: VehicleDetailsScreen(
              vehicle: localVehicle,
              editMode: editMode,
              plateCtrl: plateCtrl,
              brandCtrl: brandCtrl,
              modelCtrl: modelCtrl,
              seatsCtrl: seatsCtrl,
              onEnvStickerChanged: (value) {
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
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: _buildButtons(),
          ),
        ],
      ),
    );
  }
}