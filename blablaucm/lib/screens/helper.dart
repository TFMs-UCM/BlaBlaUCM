import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:blablaucm/models/pair.dart';
import 'package:shimmer/shimmer.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/models/pick_up_points_model.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/theme/app_colors.dart';

// En este archivo se engloban funciones que se utilizan en varias pantallas

// Clase con los estilos de los botones
class AppButtonStyles {
  AppButtonStyles._();

  static const Color primaryColor = AppColors.success;

  // Boton principal 
  static final ButtonStyle primary = ElevatedButton.styleFrom(
    backgroundColor: primaryColor,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    elevation: 0,
    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  );

  // Boton secundario 
  static final ButtonStyle secondary = ElevatedButton.styleFrom(
    backgroundColor: AppColors.successSurface, // Green-50
    foregroundColor: AppColors.successText, // Green-600
    padding: const EdgeInsets.symmetric(vertical: 16),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: AppColors.successBorder), // Green-100
    ),
    elevation: 0,
    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  );

  // Boton destructivo (para eliminar o cancelar algo)
  static final ButtonStyle danger = ElevatedButton.styleFrom(
    backgroundColor: AppColors.dangerSurface, // Red-50
    foregroundColor: AppColors.light.danger, // Danger Red
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: AppColors.dangerBorder), 
    ),
    elevation: 0,
    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  );
}

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

// Boton para los dialogs
Widget dialogButton(BuildContext context, {required bool isAccept, required String label, VoidCallback? onPressed, bool isLoading = false, Color color = AppColors.success, IconData? icon}) {
  if (!isAccept) {
    return TextButton(
      onPressed: onPressed,
      child: Text(label, style: TextStyle(color: AppColors.of(context).textSecondary)),
    );
  }
  final style = ElevatedButton.styleFrom(
    backgroundColor: color,
    foregroundColor: Colors.white,
    elevation: 0,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  );
  if (isLoading) {
    return ElevatedButton(
      style: style,
      onPressed: null,
      child: const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
    );
  }
  if (icon != null) {
    return ElevatedButton.icon(
      style: style,
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
  return ElevatedButton(
    style: style,
    onPressed: onPressed,
    child: Text(label),
  );
}

// Modal generica para pedir confirmacion al usuario
// Permite modificar el texto que se muestra, los colores y nombres de los botones
Future<bool> showConfirmationModal(BuildContext context, {required String title, required String message, String confirmText = "Aceptar", 
    String cancelText = "Cancelar", Color confirmColor = AppColors.primary, bool barrierDismissible = true}) async {
  // Devuelve true solo si se pulsa el boton aceptar (aunque se le puede cambiar el nombre si se le pasa otro en confirmText)
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) {
      final colors = AppColors.of(dialogContext);
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          title, // Se muestra el titulo que se desea
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 15,
          ),
        ),
        actions: [
          dialogButton(dialogContext, isAccept: false, label: cancelText, onPressed: () => Navigator.pop(dialogContext, false)),
          dialogButton(dialogContext, isAccept: true, label: confirmText, onPressed: () => Navigator.pop(dialogContext, true), color: confirmColor),
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
          final colors = AppColors.of(context);
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: colors.textPrimary)),
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
                    Text( // Se le indica al usuario de que las valoraciones son anonimas
                      "Todas las valoraciones son anónimas",
                      style: TextStyle(fontSize: 13, color: colors.textSecondary),
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
                              style: TextStyle(fontSize: 13, color: colors.textSecondary),
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
              dialogButton(dialogContext, isAccept: false, label: "Cerrar", onPressed: () => Navigator.pop(dialogContext)),
              dialogButton( // Al darle a aceptar, se devuelven las valoraciones
                dialogContext,
                isAccept: true,
                label: "Aceptar",
                onPressed: () async {
                  // Se muestra una modal para confirmar el envio de la puntuacion
                  final shouldSend = await showConfirmationModal(
                    context,
                    title: "Confirmar valoración",
                    message: "¿Deseas enviar esta valoración al conductor?",
                    barrierDismissible: false,
                  );

                  if (!shouldSend) return; // Si no confirma, se cierra la modal y no se envia la puntuacion

                  final payload = {
                    for (final entry in selectedRatings.entries)
                      entry.key.name: entry.value,
                  };
                  Navigator.pop(dialogContext, payload);
                },
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

// Widget que muestra un mensaje para cuando una pantalla no tiene nada que mostrar, muestra un icono y el texto centrados. 
Widget buildEmptyState({required IconData icon, required String message}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ],
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
      return buildEmptyState(
        icon: Icons.star_border,
        message: "Este conductor aún no tiene valoraciones.",
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
      return buildEmptyState(
        icon: Icons.person_outline,
        message: "Este usuario no ha indicado sus preferencias.",
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
  final Pair<String, String?>? driver; // conductor del viaje (nombre y ruta a su foto de perfil)
  final List<Pair<String, String?>> passengers;
  final bool isRequested;
  final List<FutureTravelExtraData>? futureTravels; // Viajes futuros asociados
  final List<UsersType> deniedRoles;
  // Coordenadas del origen y destino del viaje
  final double? originLat;
  final double? originLng;
  final double? destLat;
  final double? destLng;

  TravelExtraData({
    required this.rawRatings,
    required this.numRatings,
    required this.preferences,
    required this.pickUpPoints,
    required this.passengers,
    required this.isRequested,
    required this.deniedRoles,
    this.driver,
    this.originLat,
    this.originLng,
    this.destLat,
    this.destLng,
    List<FutureTravelExtraData>? futureTravels,
  }) : futureTravels = futureTravels ?? [];
}

// Funcion para formatear una fecha sin hora para la api
String formatDateOnly(DateTime date) {
  return "${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
}

// Funcion para parsear las fechas
DateTime? _parseTravelDate(dynamic value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value)?.toLocal();
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
  List<Pair<String, String?>> passengersData = [];

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

    // Parseo de los datos de los pasajeros (nombre y foto de perfil)
    final passengersDataRaw = response['passengers'] as List<dynamic>?;

    passengersData = passengersDataRaw
        ?.map((p) => Pair<String, String?>(
              first: p['username'] as String,
              second: p['profile_picture'] as String?,
            )).toList()?? [];

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

    // Parseo del conductor del viaje (nombre y foto de perfil)
    final driverRaw = response['driver'] as Map<String, dynamic>?;
    final Pair<String, String?>? driver = (driverRaw != null && driverRaw['username'] != null)
        ? Pair<String, String?>(first: driverRaw['username'] as String, second: driverRaw['profile_picture'] as String?)
        : null;

    // Parseo de coordenadas del origen y destino
    final double? originLat = (response['origin_lat'] as num?)?.toDouble();
    final double? originLng = (response['origin_lng'] as num?)?.toDouble();
    final double? destLat = (response['destination_lat'] as num?)?.toDouble();
    final double? destLng = (response['destination_lng'] as num?)?.toDouble();

    // Se devuelven los datos
    return TravelExtraData(
      rawRatings: rawRatings,
      numRatings: numRatings,
      preferences: preferences,
      pickUpPoints: pickUpPoints,
      driver: driver,
      passengers: passengersData,
      isRequested: isRequested,
      futureTravels: futureTravels,
      deniedRoles: usersDenied,
      originLat: originLat,
      originLng: originLng,
      destLat: destLat,
      destLng: destLng
    );
  } 
  else {
    // Si hay un error, se lanza para que el widget lo capture
    throw Exception("Error del servidor al obtener detalles del viaje");
  }
}

// Ruta del documento con los terminos y condiciones dentro de los assets
const String termsAssetPath = 'assets/legal/terms_and_conditions.md';

// El documento se guarda una vez leido para no volver a cargarlo del disco cada vez que se abre la modal
String? _cachedTerms;

// Funcion para cargar el texto de los terminos y condiciones desde los assets
Future<String> loadTermsAndConditions() async {
  _cachedTerms ??= await rootBundle.loadString(termsAssetPath);
  return _cachedTerms!;
}

// Convierte el texto en negrita de markdown (**texto**) en fragmentos de texto con estilo
List<TextSpan> _markdownSpans(String text, TextStyle baseStyle) {
  final spans = <TextSpan>[];
  final parts = text.split('**');
  for (int i = 0; i < parts.length; i++) {
    if (parts[i].isEmpty) continue;
    // Los fragmentos en posicion impar son los que van entre ** y **
    final isBold = i.isOdd;
    spans.add(TextSpan(
      text: parts[i],
      style: isBold ? baseStyle.copyWith(fontWeight: FontWeight.bold) : baseStyle,
    ));
  }
  return spans;
}

// Convierte el documento markdown en widgets.
List<Widget> _markdownToWidgets(String source, AppColors colors) {
  final widgets = <Widget>[];
  final bodyStyle = TextStyle(fontSize: 14, height: 1.4, color: colors.textSecondary);

  for (final rawLine in source.split('\n')) {
    final line = rawLine.trim();

    if (line.isEmpty) { // Las lineas vacias solo separan parrafos
      widgets.add(const SizedBox(height: 8));
      continue;
    }

    if (line == '---') { // Separador
      widgets.add(const Divider(height: 20));
      continue;
    }

    // Titulos, cuanto mas nivel tiene el titulo mas pequeño se muestra
    if (line.startsWith('#')) {
      final level = line.contains(' ') ? line.indexOf(' ') : 1;
      final content = line.substring(level).trim();
      final size = level == 1 ? 20.0 : level == 2 ? 17.0 : 15.0;
      widgets.add(Padding(
        padding: EdgeInsets.only(top: level == 1 ? 0 : 12, bottom: 6),
        child: Text(
          content.replaceAll('**', ''),
          style: TextStyle(fontSize: size, fontWeight: FontWeight.bold, color: colors.textPrimary),
        ),
      ));
      continue;
    }

    // Elementos de una lista, se les añade el punto y una sangria
    if (line.startsWith('- ')) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('•  ', style: bodyStyle),
            Expanded(
              child: RichText(text: TextSpan(children: _markdownSpans(line.substring(2), bodyStyle))),
            ),
          ],
        ),
      ));
      continue;
    }

    // El resto se muestra como un parrafo normal
    widgets.add(Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(text: TextSpan(children: _markdownSpans(line, bodyStyle))),
    ));
  }

  return widgets;
}

// Modal con los terminos y condiciones de uso, devuelve true si el usuario los acepta
Future<bool> showTermsAndConditionsModal(BuildContext context) async {
  bool accepted = false; // Si el usuario ha marcado la casilla

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false, // No se puede cerrar pulsando fuera, hay que decidir
    builder: (dialogContext) {
      final colors = AppColors.of(dialogContext);
      return StatefulBuilder(
        builder: (innerContext, setStateDialog) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.gavel, color: AppColors.primary, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Términos y Condiciones",
                    style: TextStyle(fontWeight: FontWeight.bold, color: colors.textPrimary),
                  ),
                ),
              ],
            ),
            contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            content: SizedBox(
              width: 500,
              // Se limita la altura para que el documento tenga su propio scroll y la casilla de aceptacion quede siempre visible
              height: MediaQuery.of(innerContext).size.height * 0.55,
              child: Column(
                children: [
                  Expanded(
                    child: FutureBuilder<String>(
                      future: loadTermsAndConditions(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) { // Mientras carga el documento
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError || snapshot.data == null) { // Si no se ha podido leer el documento
                          return Center(
                            child: Text(
                              "No se han podido cargar los términos y condiciones. Inténtalo de nuevo.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.danger),
                            ),
                          );
                        }
                        return Scrollbar(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(right: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: _markdownToWidgets(snapshot.data!, colors),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 16),
                  // Casilla de aceptacion, sin marcarla no se puede continuar
                  CheckboxListTile(
                    value: accepted,
                    onChanged: (value) => setStateDialog(() => accepted = value ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeColor: AppColors.primary,
                    title: Text(
                      "He leído y acepto los Términos y Condiciones y la Política de Privacidad, y declaro ser mayor de 18 años.",
                      style: TextStyle(fontSize: 13, color: colors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              dialogButton(dialogContext, isAccept: false, label: "Cancelar", onPressed: () => Navigator.pop(dialogContext, false)),
              dialogButton(
                dialogContext,
                isAccept: true,
                label: "Aceptar",
                color: AppColors.primary,
                // Si no se ha marcado la casilla, el boton queda deshabilitado
                onPressed: accepted ? () => Navigator.pop(dialogContext, true) : null,
              ),
            ],
          );
        },
      );
    },
  );

  return result ?? false;
}

// Modal de espera, para las operaciones que tardan y no deben dejar tocar la pantalla mientras tanto (por ejemplo iniciar sesion al terminar el registro).
void showLoadingModal(BuildContext context, {String message = "Cargando..."}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return PopScope(
        canPop: false, // El boton de atras no cierra la espera
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  message,
                  style: TextStyle(
                    color: AppColors.of(dialogContext).textSecondary,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

// Cierra el modal de espera abierto con showLoadingModal
void closeLoadingModal(BuildContext context) {
  Navigator.of(context, rootNavigator: true).pop();
}

// Funcion para mostrar una ventana modal para mostrar un mensaje, permite distinguir si es error o no, eso cambia el color del texto y el icono
void showModal(BuildContext context, String message, {String title = "Error", AlertType type = AlertType.error, bool backPage = false, bool? returnValue, bool barrierDismissible = true, VoidCallback? onAccepted}) {
  showDialog(
    context: context,
    barrierDismissible: barrierDismissible, // Para evitar cerrar la modal al pulsar fuera, por defecto se puede
    builder: (dialogContext) {
      final colors = AppColors.of(dialogContext);
      // Color de acento segun el tipo de alerta (icono, titulo y boton)
      final Color accent = type == AlertType.error ? colors.danger :
                           type == AlertType.success ? AppColors.success :
                           type == AlertType.warning ? AppColors.warning :
                           AppColors.info;
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon( // Si hay error, se muestra un icono y si es correcto otro
              type == AlertType.error ? Icons.error_outline :
              type == AlertType.success ? Icons.check_circle_outline :
              type == AlertType.warning ? Icons.warning_amber_outlined :
              Icons.info_outline,
              color: accent,
              size: 24,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message, // Se añade el texto que se desea
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 15,
          ),
        ),
        actions: [
          dialogButton(
            dialogContext,
            isAccept: true,
            label: "Aceptar",
            color: accent,
            onPressed: () {
              Navigator.pop(dialogContext); // Cierra el modal
              if (onAccepted != null) { // Si se especifica una funcion, se ejecuta al aceptar, se usa para regresar al inicio 
                // o a alguna pantalla especifica
                onAccepted();
              } 
              else if (backPage) { // Si se especifica, se vuelve a la pantalla anterior, si no solo cierra la modal
                Navigator.pop(context, returnValue);
              }
            },
          ),
        ],
      );
    },
  );
}


