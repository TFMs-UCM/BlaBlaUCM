
import 'package:blablaucm/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:blablaucm/models/travel_model.dart';
import 'package:blablaucm/screens/helper.dart';

class TravelDetailsScreen extends StatefulWidget {
  final TravelModel travel;

  const TravelDetailsScreen({super.key, required this.travel});

  @override
  State<TravelDetailsScreen> createState() => _TravelDetailsScreenState();
}

class _TravelDetailsScreenState extends State<TravelDetailsScreen> {

  // =============================
  // CALCULAR VALORACIÓN MEDIA
  // =============================
  double _calculateAverageRating(List<double>? ratings) {
    if (ratings == null || ratings.isEmpty) return 0.0;
    double sum = ratings.reduce((a, b) => a + b);
    return sum / ratings.length;
  }

  @override
  Widget build(BuildContext context) {
    final driver = widget.travel.driver;
    final avgRating = _calculateAverageRating(driver.ratings);

    final salida = widget.travel.startDate;
    final llegada = salida.add(Duration(minutes: widget.travel.duration));

    final fecha = DateFormat("EEEE d 'de' MMMM", "es_ES").format(salida);
    final horaSalida =
        "${salida.hour.toString().padLeft(2, '0')}:${salida.minute.toString().padLeft(2, '0')}";
    final horaLlegada =
        "${llegada.hour.toString().padLeft(2, '0')}:${llegada.minute.toString().padLeft(2, '0')}";

    // =============================
    // MATERIAL Y SCROLL
    // =============================
    return Material(
      color: Colors.transparent,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // =============================
            // CONDUCTOR
            // =============================
            Center(
              child: Column(
                children: [
                  Text(
                    driver.username,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 26),
                      const SizedBox(width: 4),
                      Text(
                        avgRating.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 20),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  ElevatedButton(
                    onPressed: () {
                      showRatingsDialog(
                        context,
                        driver.ratings ?? [],
                        // TODO dividir en valoraciones y preferencias
                      );
                    },
                    child: const Text("Más información"),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // =============================
            // CARD CON INFORMACIÓN DEL VIAJE
            // =============================
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    Text(
                      widget.travel.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 12),

                    _infoRow(Icons.calendar_today, fecha),

                    _infoRow(
                      Icons.location_on,
                      "${widget.travel.origin} → ${widget.travel.destination}",
                    ),

                    _infoRow(
                      Icons.access_time,
                      "$horaSalida → $horaLlegada",
                    ),

                    _infoRow(
                      Icons.directions_car,
                      "${widget.travel.vehicle.model} ${widget.travel.vehicle.brand} (${widget.travel.vehicle.envSticker!.label})", 
                      // TODO Cambiar por imagen del distintivo medioambiental
                    ),

                    _infoRow(
                      Icons.event_seat,
                      "Asientos disponibles: ${widget.travel.remainingSeats}",
                    ),

                    _infoRow(
                      Icons.person,
                      "Colectivo del conductor: ${driver.role.label}",
                    ),

                    // =============================
                    // TIPO DE VIAJE
                    // =============================
                    // 🔹 Ahora esto se actualizará al instante gracias a StatefulWidget
                    _infoRow(
                      Icons.card_membership,
                      "Tipo de viaje: ${widget.travel.isPeriodic ? "Periódico" : "Puntual"}",
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // =============================
            // BOTÓN PARA VER PARADAS
            // =============================
            Align(
              alignment: Alignment.center,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _showStopsDialog(context),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.alt_route, size: 20, color: Colors.blue),
                      SizedBox(width: 8),
                      Text(
                        "Ver paradas",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =============================
  // FILA DE INFORMACIÓN
  // =============================
  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  // =============================
  // DIÁLOGO DE PARADAS
  // =============================
  void _showStopsDialog(BuildContext context) {
    final salida = widget.travel.startDate;
    final llegada = salida.add(Duration(minutes: widget.travel.duration));

    // Lista completa: origen + intermedias + destino
    final List<Map<String, dynamic>> stops = [];

    stops.add({
      "hora": salida,
      "nombre": widget.travel.origin,
    });

    for (var stop in widget.travel.pickUpPoints) {
      stops.add({
        "hora": stop.second,
        "nombre": stop.first,
      });
    }

    stops.add({
      "hora": llegada,
      "nombre": widget.travel.destination,
    });

    const double itemHeight = 80;
    const double horaWidth = 80;
    const double timelineWidth = 40;
    final double lineLeft = horaWidth + (timelineWidth / 2) - 1;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 80),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxHeight: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [

                const Text(
                  "Recorrido del viaje",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 24),

                Expanded(
                  child: Stack(
                    children: [

                      // Línea vertical continua (entre centros)
                      Positioned(
                        left: lineLeft,
                        top: itemHeight / 2,
                        bottom: itemHeight / 2,
                        child: Container(
                          width: 2,
                          color: Colors.grey.shade400,
                        ),
                      ),

                      // Lista de paradas
                      ListView.builder(
                        itemCount: stops.length,
                        itemBuilder: (context, index) {
                          final stop = stops[index];
                          final isFirst = index == 0;
                          final isLast = index == stops.length - 1;

                          final hora =
                              "${stop["hora"].hour.toString().padLeft(2, '0')}:${stop["hora"].minute.toString().padLeft(2, '0')}";

                          return SizedBox(
                            height: itemHeight,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [

                                // Hora centrada
                                SizedBox(
                                  width: horaWidth,
                                  child: Center(
                                    child: Text(
                                      hora,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                  ),
                                ),

                                // Punto
                                SizedBox(
                                  width: timelineWidth,
                                  child: Center(
                                    child: Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: isFirst
                                            ? Colors.green
                                            : isLast
                                                ? Colors.red
                                                : Colors.blue,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),

                                // Nombre centrado
                                Expanded(
                                  child: Center(
                                    child: Text(
                                      stop["nombre"],
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: isFirst || isLast
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cerrar"),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}



//=======================================
//=======================================
//          OLD
//=======================================
//=======================================

// import 'package:blablaucm/models/enums.dart';
// import 'package:flutter/material.dart';
// import 'package:intl/intl.dart';
// import 'package:blablaucm/models/travel_model.dart';
// import 'package:blablaucm/screens/helper.dart';

// class TravelDetailsScreen extends StatelessWidget {
//   final TravelModel travel;

//   const TravelDetailsScreen({super.key, required this.travel});

//   double _calculateAverageRating(List<double>? ratings) {
//     if (ratings == null || ratings.isEmpty) return 0.0;
//     double sum = ratings.reduce((a, b) => a + b);
//     return sum / ratings.length;
//   }

//   @override
//   Widget build(BuildContext context) {
//     final driver = travel.driver;
//     final avgRating = _calculateAverageRating(driver.ratings);

//     final salida = travel.startDate;
//     final llegada = salida.add(Duration(minutes: travel.duration));

//     final fecha = DateFormat("EEEE d 'de' MMMM", "es_ES").format(salida);
//     final horaSalida =
//         "${salida.hour.toString().padLeft(2, '0')}:${salida.minute.toString().padLeft(2, '0')}";
//     final horaLlegada =
//         "${llegada.hour.toString().padLeft(2, '0')}:${llegada.minute.toString().padLeft(2, '0')}";

//     return Scaffold(
//       appBar: AppBar(
//         title: const Text("Detalles del viaje"),
//       ),

//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
            
//             // CONDUCTOR

//             Center(
//               child: Column(
//                 children: [
//                   Text(
//                     driver.username,
//                     style: const TextStyle(
//                       fontSize: 28,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),

//                   const SizedBox(height: 6),

//                   Row(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     children: [
//                       const Icon(Icons.star, color: Colors.amber, size: 26),
//                       const SizedBox(width: 4),
//                       Text(
//                         avgRating.toStringAsFixed(1),
//                         style: const TextStyle(fontSize: 20),
//                       ),
//                     ],
//                   ),

//                   const SizedBox(height: 10),

//                   ElevatedButton(
//                     onPressed: () {
//                       showRatingsDialog(
//                         context,
//                         driver.ratings ?? [],
//                         //title: "Valoraciones del conductor",
//                       );
//                     },
//                     child: const Text("Más información"), // TODO dividir en valoraciones y preferencias
//                   ),
//                 ],
//               ),
//             ),

//             const SizedBox(height: 24),

//             // CARD CON INFORMACIÓN DEL VIAJE

//             Card(
//               elevation: 3,
//               shape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(16),
//               ),
//               child: Padding(
//                 padding: const EdgeInsets.all(18),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [

//                     Text(
//                       travel.name,
//                       style: const TextStyle(
//                         fontSize: 22,
//                         fontWeight: FontWeight.bold,
//                       ),
//                     ),

//                     const SizedBox(height: 12),

//                     Row(
//                       children: [
//                         const Icon(Icons.calendar_today, size: 20),
//                         const SizedBox(width: 8),
//                         Text(
//                           fecha,
//                           style: const TextStyle(fontSize: 16),
//                         ),
//                       ],
//                     ),

//                     const SizedBox(height: 8),

//                     Row(
//                       children: [
//                         const Icon(Icons.location_on, size: 20),
//                         const SizedBox(width: 8),
//                         Text(
//                           "${travel.origin} → ${travel.destination}",
//                           style: const TextStyle(fontSize: 16),
//                         ),
//                       ],
//                     ),

//                     const SizedBox(height: 8),

//                     Row(
//                       children: [
//                         const Icon(Icons.access_time, size: 20),
//                         const SizedBox(width: 8),
//                         Text(
//                           "$horaSalida → $horaLlegada",
//                           style: const TextStyle(fontSize: 16),
//                         ),
//                       ],
//                     ),
//                     const SizedBox(height: 8),

//                     Row(
//                       children: [
//                         const Icon(Icons.directions_car, size: 20),
//                         const SizedBox(width: 8),
//                         Text(
//                           "${travel.vehicle.model} ${travel.vehicle.brand} (${travel.vehicle.envSticker!.label})", // TODO Cambiar por imagen del distintivo medioambiental
//                           style: const TextStyle(fontSize: 16),
//                         ),
//                       ],
//                     ),

//                     const SizedBox(height: 8),

//                     Row(
//                       children: [
//                         const Icon(Icons.event_seat, size: 20),
//                         const SizedBox(width: 8),
//                         Text(
//                           "Asientos disponibles: ${travel.remainingSeats}",
//                           style: const TextStyle(fontSize: 16),
//                         ),
//                       ],
//                     ),

//                     const SizedBox(height: 8),

//                     Row(
//                       children: [
//                         const Icon(Icons.person, size: 20),
//                         const SizedBox(width: 8),
//                         Text(
//                           "Colectivo del conductor: ${driver.role.label}",
//                           style: const TextStyle(fontSize: 16),
//                         ),
//                       ],
//                     ),

//                     const SizedBox(height: 8),

//                     Row(
//                       children: [
//                         const Icon(Icons.card_membership, size: 20),
//                         const SizedBox(width: 8),
//                         Text(
//                           "Tipo de viaje: ${travel.isPeriodic? "Periodico": "Puntual"}",
//                           style: const TextStyle(fontSize: 16),
//                         ),
//                       ],
//                     ),
//                   ],
//                 ),
//               ),
//             ),

//             const SizedBox(height: 12),

//             Align(
//               alignment: Alignment.center,
//               child: InkWell(
//                 borderRadius: BorderRadius.circular(12),
//                 onTap: () => _showStopsDialog(context),
//                 child: Padding(
//                   padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
//                   child: Row(
//                     mainAxisSize: MainAxisSize.min, // Esto hace que solo ocupe lo necesario
//                     children: const [
//                       Icon(Icons.alt_route, size: 20, color: Colors.blue),
//                       SizedBox(width: 8),
//                       Text(
//                         "Ver paradas",
//                         style: TextStyle(
//                           fontSize: 16,
//                           fontWeight: FontWeight.w600,
//                           color: Colors.blue,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             ),

//             const SizedBox(height: 30),

//             // BOTÓN SOLICITAR VIAJE

//             SizedBox(
//               width: double.infinity,
//               child: ElevatedButton(
//                 onPressed: () {
//                   // TODO: Implementar solicitud de viaje con llamada al WS
//                 },
//                 style: ElevatedButton.styleFrom(
//                   padding: const EdgeInsets.symmetric(vertical: 16),
//                 ),
//                 child: const Text(
//                   "Solicitar viaje",
//                   style: TextStyle(fontSize: 18),
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
    
//   }

//   void _showStopsDialog(BuildContext context) {
//     final salida = travel.startDate;
//     final llegada = salida.add(Duration(minutes: travel.duration));

//     // Lista completa: origen + intermedias + destino
//     final List<Map<String, dynamic>> stops = [];

//     stops.add({
//       "hora": salida,
//       "nombre": travel.origin,
//     });

//     for (var stop in travel.pickUpPoints) {
//       stops.add({
//         "hora": stop.second,
//         "nombre": stop.first,
//       });
//     }

//     stops.add({
//       "hora": llegada,
//       "nombre": travel.destination,
//     });

//     const double itemHeight = 80;
//     const double horaWidth = 80;
//     const double timelineWidth = 40;
//     final double lineLeft = horaWidth + (timelineWidth / 2);

//     showDialog(
//       context: context,
//       builder: (context) {
//         return Dialog(
//           insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 80),
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(20),
//           ),
//           child: Container(
//             padding: const EdgeInsets.all(24),
//             constraints: const BoxConstraints(maxHeight: 500),
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               crossAxisAlignment: CrossAxisAlignment.center,
//               children: [

//                 const Text(
//                   "Recorrido del viaje",
//                   textAlign: TextAlign.center,
//                   style: TextStyle(
//                     fontSize: 20,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),

//                 const SizedBox(height: 24),

//                 Expanded(
//                   child: Stack(
//                     children: [

//                       // Línea vertical continua (entre centros)
//                       Positioned(
//                         left: lineLeft,
//                         top: itemHeight / 2,
//                         bottom: itemHeight / 2,
//                         child: Container(
//                           width: 2,
//                           color: Colors.grey.shade400,
//                         ),
//                       ),

//                       // Lista
//                       ListView.builder(
//                         itemCount: stops.length,
//                         itemBuilder: (context, index) {
//                           final stop = stops[index];
//                           final isFirst = index == 0;
//                           final isLast = index == stops.length - 1;

//                           final hora =
//                               "${stop["hora"].hour.toString().padLeft(2, '0')}:${stop["hora"].minute.toString().padLeft(2, '0')}";

//                           return SizedBox(
//                             height: itemHeight,
//                             child: Row(
//                               crossAxisAlignment: CrossAxisAlignment.center,
//                               children: [

//                                 // Hora centrada
//                                 SizedBox(
//                                   width: horaWidth,
//                                   child: Center(
//                                     child: Text(
//                                       hora,
//                                       textAlign: TextAlign.center,
//                                       style: const TextStyle(fontSize: 15),
//                                     ),
//                                   ),
//                                 ),

//                                 // Punto
//                                 SizedBox(
//                                   width: timelineWidth,
//                                   child: Center(
//                                     child: Container(
//                                       width: 16,
//                                       height: 16,
//                                       decoration: BoxDecoration(
//                                         color: isFirst
//                                             ? Colors.green
//                                             : isLast
//                                                 ? Colors.red
//                                                 : Colors.blue,
//                                         shape: BoxShape.circle,
//                                       ),
//                                     ),
//                                   ),
//                                 ),

//                                 // Nombre centrado
//                                 Expanded(
//                                   child: Center(
//                                     child: Text(
//                                       stop["nombre"],
//                                       textAlign: TextAlign.center,
//                                       style: TextStyle(
//                                         fontSize: 16,
//                                         fontWeight: isFirst || isLast
//                                             ? FontWeight.bold
//                                             : FontWeight.w500,
//                                       ),
//                                     ),
//                                   ),
//                                 ),
//                               ],
//                             ),
//                           );
//                         },
//                       ),
//                     ],
//                   ),
//                 ),

//                 const SizedBox(height: 16),

//                 TextButton(
//                   onPressed: () => Navigator.pop(context),
//                   child: const Text("Cerrar"),
//                 ),
//               ],
//             ),
//           ),
//         );
//       },
//     );
//   }

// }
