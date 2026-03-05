import 'package:flutter/material.dart';
import 'package:blablaucm/models/travel_model.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/screens/travel_details.dart';


class RequestedTravelsDetailsScreen extends StatefulWidget {
  final TravelModel travel;

  const RequestedTravelsDetailsScreen({
    super.key,
    required this.travel,
  });

  @override
  State<RequestedTravelsDetailsScreen> createState() =>
      _RequestedTravelsDetailsScreenState();
}

class _RequestedTravelsDetailsScreenState
    extends State<RequestedTravelsDetailsScreen> {

  @override
  Widget build(BuildContext context) {
    final bool isActive = widget.travel.status == TravelStatus.active;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Datos del viaje"),
      ),
      body: Column(
        children: [
          Expanded(
            child: TravelDetailsScreen(
              key: ValueKey(widget.travel.isPeriodic),
              travel: widget.travel,
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: isActive
                ? Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          onPressed: () => _deleteTravel(context),
                          child: const Text("Eliminar"),
                        ),
                      ),
                    ],
                  )
                : SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: () => _deleteTravel(context),
                      child: const Text("Eliminar"),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ELIMINAR VIAJE

  void _deleteTravel(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Eliminar viaje"),
        content: const Text(
            "¿Estás seguro de que quieres eliminar este viaje?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () {
              Navigator.pop(context);

              // TODO: Llamada al WS

            },
            child: const Text("Eliminar"),
          ),
        ],
      ),
    );
  }
}