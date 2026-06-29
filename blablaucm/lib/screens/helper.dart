import 'package:flutter/material.dart';
import 'package:blablaucm/models/pair.dart';
import 'package:shimmer/shimmer.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/models/pick_up_points_model.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/services/api_service.dart';

// En este archivo se engloban funciones que se utilizan en varias pantallas

// Funcion para abrir una modal que muestre las valoraciones
Future<void> showRatingsDialog(BuildContext context, List<Pair<RatingsTypes,double>> ratings, {String? title, int? numRatings}) async {
  double avg = ratings.isNotEmpty ? ratings.map((e) => e.second).reduce((a, b) => a + b) / ratings.length : 0.0;
  await showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: title != null ? Text(title) : null,
        content: SizedBox(
          width: 350,
          child: SingleChildScrollView( 
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              // Se muestra la media de las valoraciones
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Valoración media: ",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    avg.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),

              // Si tiene valoraciones, se muestra el numero de valoraciones que tiene el usuario
              if (numRatings != null) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "$numRatings valoraciones",
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 8),
              // Se muestra las valoraciones con estrellas
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  buildStars(avg, size: 22),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                "Valoraciones detalladas:",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              // Se muestra cada una de los campos de valoracion, con su puntuacion y estrellas
              for (int i = 0; i < ratings.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          ratings[i].first.label,
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                      buildStars(ratings[i].second > 0 ? ratings[i].second : 0.0, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        ratings[i].second > 0 ? ratings[i].second.toStringAsFixed(1) : '0.0',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        ),
        actions: [ // Boton para cerrar la modal
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cerrar"),
          ),
        ],
      );
    },
  );
}

// Modal generica para pedir confirmacion al usuario
// Permite modificar el texto que se muestra, los colores y nombres de los botones
Future<bool> showConfirmationModal(BuildContext context, {required String title, required String message, String confirmText = "Aceptar", 
    String cancelText = "Cancelar", Color confirmColor = const Color(0xFF4F46E5), bool barrierDismissible = true}) async {
  // Devuelve true solo si se pulsa el boton aceptar (aunque se le puede cambiar el nombre si se le pasa otro en confirmText)
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          title, // Se muestra el titulo que se desea
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF111827),
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: Color(0xFF374151),
            fontSize: 15,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              cancelText, // En el boton de cancelar se asigna el texto que se desea para dicho boton
              style: const TextStyle(color: Color(0xFF6B7280)), // Gris para cancelar (no cambia este color)
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor, // En el boton de confirmar, se permite poner el color que se desee
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(dialogContext, true), // Solo se devulve true si se pulsa este boton
            child: Text(
              confirmText, // Texto que aparece en el boton de aceptar
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

// FUncion para crear el widget para valorar a un conductor
Future<Map<String, double>?> showDriverRatingsInputModal(BuildContext context, {String title = "Puntuar conductor",String? subtitle}) async {
  // Se inicializan todas las valoraciones a 0
  final Map<RatingsTypes, double> selectedRatings = {
    for (final ratingType in RatingsTypes.values) ratingType: 0.0,
  };

  String? errorText;

  return showDialog<Map<String, double>>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (subtitle != null) ...[
                      Text(subtitle),
                      const SizedBox(height: 12),
                    ],
                    const Text( // Se le indica al usuario de que las valoraciones son anonimas
                      "Todas las valoraciones son anónimas",
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    ...RatingsTypes.values.map((ratingType) {
                      final currentValue = selectedRatings[ratingType] ?? 0.0;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ratingType.label, // Se muestra que campo se esta evaluando
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _buildInteractiveStars( // Se muestran las estrellas con la puntuacion
                                      rating: currentValue,
                                      onRatingChanged: (newValue) {
                                        setDialogState(() {
                                          selectedRatings[ratingType] = newValue;
                                          errorText = null;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                IconButton( // Boton para poner a 0 esa valoracion
                                  tooltip: "Poner a 0", // Se le añade un icono de informacion indicandole que se bone a 0 esa valoracion
                                  icon: const Icon(Icons.clear),
                                  onPressed: currentValue == 0.0 ? null // Si es 0 no hace nada
                                      : () { // Si no, se pone a 0
                                          setDialogState(() {
                                            selectedRatings[ratingType] = 0.0;
                                            errorText = null;
                                          });
                                        },
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text( // Muestra el valor en numeros para dejarlo mas claro que con las estrellas
                              "${currentValue.toStringAsFixed(1)} / 5.0",
                              style: const TextStyle(fontSize: 13, color: Colors.grey),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (errorText != null) // Si hay un error, se muestra el error
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          errorText!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [ // Botones de aceptar y cerrar
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text("Cerrar"),
              ),
              ElevatedButton( // Al darle a aceptar, se devuelven las valoraciones
                onPressed: () {
                  final payload = {
                    for (final entry in selectedRatings.entries)
                      entry.key.name: entry.value,
                  };

                  Navigator.pop(dialogContext, payload);
                },
                child: const Text("Aceptar"),
              ),
            ],
          );
        },
      );
    },
  );
}

// Widget para construir las estrellas de la pantalla de valorar a un conductor
Widget _buildInteractiveStars({required double rating,required ValueChanged<double> onRatingChanged,double size = 28}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(5, (index) { 
      final starNumber = index + 1; // Para que haya 5 estrellas

      IconData icon;
      if (rating >= starNumber) { // Si supera esa estrella, se pone la estrella completa
        icon = Icons.star;
      } 
      else if (rating >= starNumber - 0.5) { // Si es menor que ese numero, se pone media estrella
        icon = Icons.star_half;
      } 
      else { // Se rellena con estrellas vacias el resto
        icon = Icons.star_border;
      }

      // Captura la pulsacion para ir rellenando las estrellas
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          final isLeftHalf = details.localPosition.dx <= size / 2;
          final selectedValue = index + (isLeftHalf ? 0.5 : 1.0);

          // Si pulsa dos veces en el mismo punto, se pone a 0, para permitir que pueda borrarlo facilmente
          if ((selectedValue - rating).abs() < 0.001) {
            onRatingChanged(0.0);
            return;
          }

          onRatingChanged(selectedValue);
        },
        child: SizedBox(
          width: size + 6,
          height: size + 6,
          child: Icon(icon, color: Colors.amber, size: size), // Se ponen las estrellas de color amarillo
        ),
      );
    }),
  );
}

// Widget para construir las estrellas de las valoraciones (solo mostarlas, no se puede editar)
Widget buildStars(double rating, {double size = 22}) {
  List<Widget> stars = []; // Lista de estrellas
  for (int i = 1; i <= 5; i++) {
    IconData icon;
    if (rating >= i) { // Si es un numero entero, se pone una estrella completa
      icon = Icons.star;
    } 
    else if (rating >= i - 0.5) { // Si es decimal, se pone media estrella
      icon = Icons.star_half;
    } 
    else { // Se rellena el resto con estrellas vacias
      icon = Icons.star_border;
    }
    stars.add(Icon(icon, color: Colors.amber, size: size)); // Se ponen las estrellas amarillas
  }
  return Row(children: stars);
}

// Esqueleto de un objeto para mostar mientras se esta cargando el objeto
Widget skeletonItem() {
  return Shimmer.fromColors(
    baseColor: Colors.grey.shade300,
    highlightColor: Colors.grey.shade100,
    child: Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: Container(width: 40, height: 40, color: Colors.white),
        title: Container(height: 14, color: Colors.white),
        subtitle: Container(height: 12, color: Colors.white),
      ),
    ),
  );
}

// Clase para englobar las valoraciones
class DriverRatingsWidget extends StatelessWidget {
  final List<Pair<RatingsTypes, double>> ratings;
  final int? numRatings;

  const DriverRatingsWidget({
    super.key,
    required this.ratings,
    this.numRatings,
  });

  // Funcion para mostrar el widget
  @override
  Widget build(BuildContext context) {
    double avg = ratings.isNotEmpty ? ratings.map((e) => e.second).reduce((a, b) => a + b) / ratings.length : 0.0;

    // Si no tiene valoraciones, se muestra un mensaje
    if (ratings.isEmpty) {
      return const Center(
        child: Text(
          "Este conductor aún no tiene valoraciones.",
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [ // Se muestra la valoracion media
            const Text( 
              "Valoración media: ",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text( 
              avg.toStringAsFixed(1),
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),

        if (numRatings != null) ...[ // Si tiene valoraciones, se indica el numero de valoraciones que tiene
          const SizedBox(height: 4),
          Text(
            numRatings == 1 ? "1 valoración" : "$numRatings valoraciones",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],

        const SizedBox(height: 8),
        
        // Se muestra el la media de las valoraciones con estrellas
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            buildStars(avg, size: 22),
          ],
        ),
        
        const SizedBox(height: 24),
        const Text(
          "Valoraciones detalladas:",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),

        // Se muestra cada uno de los campos de las valoraciones con su puntuacion y las estrellas
        ...ratings.map((rating) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    rating.first.label, 
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                buildStars(rating.second > 0 ? rating.second : 0.0, size: 18),
                const SizedBox(width: 8),
                Text(
                  rating.second > 0 ? rating.second.toStringAsFixed(1) : '0.0',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// Clase para mostrar las preferencias del conductor
class DriverPreferencesWidget extends StatelessWidget {
  final List<DriverPreferences> preferences;
  
  const DriverPreferencesWidget({
    super.key, 
    required this.preferences,
  });

  @override
  Widget build(BuildContext context) {
    // Si no hay preferencias, se muestra un mensaje indicandolo
    if (preferences.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_outline, size: 48, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                "Este usuario no ha indicado sus preferencias.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // Si tiene, se muestran las preferencias en formato chip
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        const Text(
          "Preferencias del viaje",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8.0,
          runSpacing: 10.0, 
          children: preferences.map((pref) {
            return Chip(
              label: Text(
                pref.label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              backgroundColor: Colors.blue.shade50, 
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              avatar: const Icon(
                Icons.check_circle, 
                size: 18, 
                color: Colors.blue,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// Clase para meter los datos de los viajes futuros
class FutureTravelExtraData {
  final String travelId; // El id del viaje
  final int remainingSeats; // El numero de plazas disponibles
  final DateTime date; // La fecha del viaje
  final bool isRequested; // Si ha sido solicitado por alguien

  FutureTravelExtraData({
    required this.travelId,
    required this.remainingSeats,
    required this.date,
    required this.isRequested,
  });
}

// Clase para englobar los datos extra de un viaje futuro, con los datos necesarios y sus viajes futuros asociados
class TravelExtraData {
  final Map<String, dynamic> rawRatings; // Mapa con las cada valoracion y su puntuacion
  final int numRatings;
  final List<DriverPreferences> preferences;
  final List<PickUpPointModel> pickUpPoints;
  final List<String> passengers;
  final bool isRequested;
  final List<FutureTravelExtraData>? futureTravels; // Viajes futuros asociados
  final List<UsersType> deniedRoles;

  TravelExtraData({
    required this.rawRatings,
    required this.numRatings,
    required this.preferences,
    required this.pickUpPoints,
    required this.passengers,
    required this.isRequested,
    required this.deniedRoles,
    List<FutureTravelExtraData>? futureTravels,
  }) : futureTravels = futureTravels ?? [];
}

// Funcion para parsear las fechas
DateTime? _parseTravelDate(dynamic value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  return null;
}

// Funcion para obtener los datos extra de un viaje
Future<TravelExtraData> fetchTravelExtraData({required String travelId, required ApiService api, bool loadFutureTravels = false}) async {
  // Se construye el endpoint
  final endpoint = "${dotenv.env['TRAVELS_ENDPOINT'] ?? 'travel/'}$travelId/get_travel_details/";

  // Se realiza la peticion, si loadFuterTravel es true, se cargan los datos de los viajes futuros
  final response = await api.requestToApi(endpoint, op: ApiOptions.get, queryParams: {"future_travels": loadFutureTravels.toString()});

  List<DriverPreferences> preferences = [];
  Map<String, dynamic> rawRatings = {};
  List<FutureTravelExtraData>? futureTravels = [];

  if (response != null && response['error'] == null) { // Si no hay errores, se cargan los datos
    // Parseo de valoraciones
    final numRatings = (response['ratings']?['count'] as num?)?.toInt() ?? 0;

    final ratingsResults = response['ratings']?['results'];
    if (ratingsResults is Map<String, dynamic>) {
      rawRatings = ratingsResults;
    } 
    else if (ratingsResults is Map) {
      rawRatings = Map<String, dynamic>.from(ratingsResults);
    }

    // Parseo de preferencias
    final allPreferences = (response['preferences'] as List<dynamic>?)
            ?.map((pref) => parseEnum<DriverPreferences>(pref, DriverPreferences.values))
            .toList() ?? [];
    preferences = allPreferences.whereType<DriverPreferences>().toList();

    // Parseo de puntos de recogida
    final pickUpPoints = (response['pickup_points'] as List<dynamic>?)
            ?.map((point) => PickUpPointModel.fromJson(point))
            .toList() ?? [];

    // Parseo de pasajeros
    final passengers = (response['passengers'] as List<dynamic>?)
            ?.map((passenger) => passenger.toString())
            .toList() ?? [];

    // Parseo de si el usuario ha solicitado plaza en el viaje
    final isRequested = response['is_requested'] ?? false;

    // Parseo de futuros viajes (si los hay)
    if(loadFutureTravels) {
      final nextTravels = response['next_travels'];
      if (nextTravels != null && nextTravels is Map) {
        for (final nextEntry in nextTravels.entries) {
          final entry = nextEntry.value;
          if (entry is Map) {
            final travelId = entry['id']?.toString() ?? nextEntry.key.toString();
            final remainingSeats = (entry['remaining_seats'] as num?)?.toInt();
            final date = _parseTravelDate(entry['travel_date']);
            if (remainingSeats != null && date != null) {
              futureTravels.add(
                FutureTravelExtraData(
                  travelId: travelId,
                  remainingSeats: remainingSeats,
                  date: date,
                  isRequested: entry['is_requested'] ?? false,
                ),
              );
            }
          }
        }
      }
    }

    final List<UsersType> usersDenied = (response['denied_roles'] as List<dynamic>?)
            ?.map((role) => parseEnum<UsersType>(role, UsersType.values))
            .whereType<UsersType>()
            .toList() ?? [];

    // Se devuelven los datos
    return TravelExtraData(
      rawRatings: rawRatings,
      numRatings: numRatings,
      preferences: preferences,
      pickUpPoints: pickUpPoints,
      passengers: passengers,
      isRequested: isRequested,
      futureTravels: futureTravels,
      deniedRoles: usersDenied,
    );
  } 
  else {
    // Si hay un error, se lanza para que el widget lo capture
    throw Exception("Error del servidor al obtener detalles del viaje");
  }
}

// Funcion para mostrar una ventana modal para mostrar un mensaje, permite distinguir si es error o no, eso cambia el color del texto y el icono
void showModal(BuildContext context, String message, {String title = "Error", bool isError = true, bool backPage = false, bool? returnValue, bool barrierDismissible = true}) {
  showDialog(
    context: context,
    barrierDismissible: barrierDismissible, // Para evitar cerrar la modal al pulsar fuera, por defecto se puede
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Row(
        children: [
          Icon( // Si hay error, se muestra un icono y si es correcto otro
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
            size: 24,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        message, // Se añade el texto que se desea
        style: const TextStyle(
          color: Color(0xFF374151), // textGray700
          fontSize: 15,
        ),
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom( // Si es error, el boton es rojo, si no, verde
            backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: () {
            Navigator.pop(dialogContext); // Cierra el modal
            if (backPage) { // Si se especifica, se vuelve a la pantalla anterior, si no solo cierra la modal
              Navigator.pop(context, returnValue); 
            }
          },
          child: const Text(
            "Aceptar", // Solo esta este boton, que cierra la modal
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

// Clase para englobar los temas de la aplicacion
class AppTheme {
  // Colores principales
  static const Color primaryColor = Color(0xFF4F46E5); 
  static const Color primaryColorDark = Color(0xFF4338CA);
  static const Color successColor = Color(0xFF10B981); 
  static const Color warningColor = Color(0xFFF59E0B);

  // Determinar si es modo oscuro o no
  static bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

  // Cambiar el color dependiendo del modo
  static Color bgColor(BuildContext context) => isDark(context) ? const Color(0xFF0F172A) : const Color(0xFFF3F4F6);
  static Color cardColor(BuildContext context) => isDark(context) ? const Color(0xFF1E293B) : Colors.white;
  static Color surfaceLow(BuildContext context) => isDark(context) ? const Color(0xFF334155) : const Color(0xFFF9FAFB);
  static Color borderColor(BuildContext context) => isDark(context) ? const Color(0xFF475569) : const Color(0xFFE5E7EB);
  static Color textColor(BuildContext context) => isDark(context) ? const Color(0xFFF8FAFC) : const Color(0xFF111827);
  static Color textMuted(BuildContext context) => isDark(context) ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);
  static Color errorColor(BuildContext context) => isDark(context) ? const Color(0xFFF87171) : const Color(0xFFEF4444);

  // Widget para construir un card unificado
  static Widget buildCard(BuildContext context, {required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor(context), width: 1),
        boxShadow: isDark(context) ? [] : [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))
        ],
      ),
      padding: padding ?? const EdgeInsets.all(20),
      child: child,
    );
  }

  // Widget para crear un imput decorator
  static InputDecoration customInputDecoration(BuildContext context, String label, {bool hasError = false, String? errorText, IconData? prefixIcon, Color? iconColor}) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: textMuted(context), fontSize: 13, fontWeight: FontWeight.w500),
      filled: true,
      fillColor: surfaceLow(context),
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: iconColor ?? primaryColor) : null,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor(context))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: primaryColor)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: errorColor(context))),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      errorText: hasError ? errorText : null,
    );
  }

  // Widget para crear un footer
  static Widget buildStickyFooter(BuildContext context, {required List<Widget> children}) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        color: cardColor(context).withValues(alpha: 0.95),
        border: Border(top: BorderSide(color: borderColor(context))),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, -4))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  // Widget para construir un boton
  static Widget buildPrimaryButton({required VoidCallback? onPressed, required String text, bool isLoading = false, Color? color}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? primaryColor,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Text(text, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

