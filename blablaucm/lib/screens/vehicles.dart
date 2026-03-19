import 'package:blablaucm/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:blablaucm/models/vehicle_model.dart';
import 'package:blablaucm/screens/vehicle_details_profile.dart';

class VehiclesScreen extends StatefulWidget {
  final List<VehicleModel> vehicles;

  const VehiclesScreen({super.key, required this.vehicles});

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  late List<VehicleModel> localVehicles;

  @override
  void initState() {
    super.initState();
    localVehicles = List.from(widget.vehicles); // copia segura
  }

  void _confirmDelete(VehicleModel vehicle) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Eliminar vehículo"),
          content: Text(
            "¿Seguro que quieres eliminar el vehículo:\n\n${vehicle.vehiclePreview()}?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  widget.vehicles.removeWhere((v) => v.id == vehicle.id);
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text("Eliminar"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final vehicles = widget.vehicles;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Mis vehículos"),
      ),
      body: vehicles.isEmpty
          ? const Center(
              child: Text(
                "No tienes vehículos registrados",
                style: TextStyle(fontSize: 18),
              ),
            )
          : ListView.builder(
              itemCount: localVehicles.length,
              itemBuilder: (context, index) {
                final v = localVehicles[index];


                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.directions_car, size: 32),
                    title: Text(v.vehiclePreview()),
                    subtitle: Text(
                      "Asientos: ${v.numSeats}  |  Etiqueta: ${v.envSticker?.label ?? "N/A"}",
                    ),
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) {
                        if (value == "delete") {
                          _confirmDelete(v);  
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: "delete",
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: Colors.red),
                              SizedBox(width: 8),
                              Text("Eliminar"),
                            ],
                          ),
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => VehicleDetailsProfileScreen(
                            vehicle: v,
                            onDelete: (veh) {
                              setState(() {
                                localVehicles.removeWhere((x) => x.id == veh.id);
                              });
                            },
                            onUpdate: (veh) {
                              setState(() {
                                final index =
                                    localVehicles.indexWhere((x) => x.id == veh.id);
                                if (index != -1) {
                                  localVehicles[index] = veh;
                                }
                              });
                            },
                          ),
                        ),
                      );
                    },


                  ),
                );
              },
            ),
    );
  }
}
