import 'package:flutter/material.dart';
import 'package:blablaucm/models/travel_model.dart';
import 'travel_details.dart';

class SearchTravelDetailsScreen extends StatelessWidget {
  final TravelModel travel;

  const SearchTravelDetailsScreen({
    super.key,
    required this.travel,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Detalles del viaje"),
      ),
      body: Column(
        children: [

          /// Parte reutilizable
          Expanded(
            child: TravelDetailsScreen(travel: travel),
          ),

          /// Botón específico de esta pantalla
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  // TODO: llamada al WS
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  "Solicitar viaje",
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}