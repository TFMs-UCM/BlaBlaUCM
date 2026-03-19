import 'package:flutter/material.dart';
import 'package:blablaucm/models/enums.dart';

/// Muestra un modal con las valoraciones detalladas y la media.
Future<void> showRatingsDialog(BuildContext context, List<double> ratings, {String? title}) async {
  double avg = ratings.isNotEmpty ? ratings.reduce((a, b) => a + b) / ratings.length : 0.0;

  await showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: title != null ? Text(title) : null,
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // MEDIA NUMÉRICA
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
              const SizedBox(height: 8),
              // ESTRELLAS DE LA MEDIA
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
              for (int i = 0; i < RatingsTypes.values.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          RatingsTypes.values[i].label,
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                      buildStars(ratings.length > i ? ratings[i].toDouble() : 0.0, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        ratings.length > i ? ratings[i].toDouble().toStringAsFixed(1) : '-',
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cerrar"),
          ),
        ],
      );
    },
  );
}

Widget buildStars(double rating, {double size = 22}) {
  List<Widget> stars = [];
  for (int i = 1; i <= 5; i++) {
    IconData icon;
    if (rating >= i) {
      icon = Icons.star;
    } else if (rating >= i - 0.5) {
      icon = Icons.star_half;
    } else {
      icon = Icons.star_border;
    }
    stars.add(Icon(icon, color: Colors.amber, size: size));
  }
  return Row(children: stars);
}
