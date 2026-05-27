import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:blablaucm/models/picked_image.dart';

// Servicio para manejar la seleccion de imagenes desde la galeria o la camara

class ImagePickerService {
  final ImagePicker _picker = ImagePicker();

  // Permite seleccionar una imagen desde la camara o desde la galeria, dependiendo del source que se le pase
  Future<PickedImage?> pickUpImage(ImageSource source) async {
    // Se obtiene la imagen dependiendo del source, si el usuario cancela se devuelve null
    final XFile? image = await _picker.pickImage(source: source);

    if (image == null) return null; // Si no hay imegen, se devuelve null

    if (kIsWeb) { // Si esta en la web, se lee como bytes
      final bytes = await image.readAsBytes();
      return PickedImage(bytes: bytes);
    } 
    else { // Si esta en un movil, se lee como archivo
      return PickedImage(file: File(image.path));
    }
  }
}
