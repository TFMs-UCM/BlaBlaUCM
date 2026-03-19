import 'package:flutter/material.dart';
import 'package:blablaucm/models/travel_model.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/screens/travel_details.dart';


class CreatedTravelsDetailsScreen extends StatefulWidget {
  final TravelModel travel;

  const CreatedTravelsDetailsScreen({
    super.key,
    required this.travel,
  });

  @override
  State<CreatedTravelsDetailsScreen> createState() =>
      _CreatedTravelsDetailsScreenState();
}

class _CreatedTravelsDetailsScreenState
    extends State<CreatedTravelsDetailsScreen> {

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
                          onPressed: () =>
                              _showChangeTypeDialog(context),
                          child: const Text("Cambiar tipo"),
                        ),
                      ),
                      const SizedBox(width: 12),
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

  // CAMBIAR TIPO DE VIAJE

  void _showChangeTypeDialog(BuildContext context) {
    if (widget.travel.isPeriodic) {
      _showPeriodicToSingleDialog(context);
    } else {
      _showSingleToPeriodicDialog(context);
    }
  }

  void _showPeriodicToSingleDialog(BuildContext context) {
    DateTime? selectedDate;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text("Cambiar a viaje puntual"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("El viaje dejará de ser periódico..."),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 365)),
                      initialDate: now,
                    );

                    if (picked != null) {
                      setDialogState(() {
                        selectedDate = picked;
                      });
                    }
                  },
                  child: const Text("Seleccionar fecha"),
                ),
                if (selectedDate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                        "Desde: ${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}"),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancelar"),
              ),
              ElevatedButton(
                onPressed: selectedDate == null
                    ? null
                    : () {
                        Navigator.pop(context);
                        // TODO Implementar la llamada al WS
                        setState(() {
                          widget.travel.isPeriodic = false;
                        });
                      },
                child: const Text("Confirmar"),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSingleToPeriodicDialog(BuildContext context) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Cambiar a viaje periódico"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                "Introduce cada cuántos días (1-31) debe repetirse el viaje:"),

            const SizedBox(height: 12),

            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: "Número de días",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () {
              final int? days = int.tryParse(controller.text);

              if (days == null || days < 1 || days > 31) {
                return;
              }

              Navigator.pop(context);

              setState(() {
                widget.travel.isPeriodic = true;
                widget.travel.periodicInterval = days;
              });

              // TODO Implementar llamada al WS

            },
            child: const Text("Confirmar"),
          ),
        ],
      ),
    );
  }
}