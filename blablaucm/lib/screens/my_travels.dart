import 'package:flutter/material.dart';
import 'package:blablaucm/screens/created_travels.dart';
import 'package:blablaucm/screens/requested_travels.dart';
import 'package:blablaucm/screens/helper.dart';

// Pantalla para consultar los viajes del usuario

class MyTravelsScreen extends StatelessWidget {
  const MyTravelsScreen({super.key});

  // Funcion para construir la pantalla
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      //appBar: AppBar(title: const Text("Mis viajes")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [ // Se le da dos opciones, creados o solicitados

              const Text(
                "¿Qué viajes desea consultar?",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [

                  ElevatedButton(
                    onPressed: () { // Se abre la pantalla de viajes creados
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CreatedTravelsScreen(),
                        ),
                      );
                    },
                    style: AppButtonStyles.primary.copyWith(
                      padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      ),
                    ),
                    child: const Text("Creados"),
                  ),

                  const SizedBox(width: 20),

                  ElevatedButton( // Se abre la pantalla de viajes solicitados
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RequestedTravelsScreen(),
                        ),
                      );
                    },
                    style: AppButtonStyles.secondary.copyWith(
                      padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      ),
                    ),
                    child: const Text("Solicitados"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
