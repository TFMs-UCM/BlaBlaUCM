import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:blablaucm/models/picked_image.dart';

// Servicio para manejar la seleccion de imagenes desde la galeria o la camara

class ImagePickerService {
  final ImagePicker _picker = ImagePicker();

  // Tamaño maximo permitido para una imagen de perfil (2MB)
  static const int maxImageBytes = 2097152;

  // Permite seleccionar una imagen desde la camara o desde la galeria, dependiendo del source que se le pase
  Future<PickedImage?> pickUpImage(ImageSource source) async {
    // Se obtiene la imagen dependiendo del source, si el usuario cancela se devuelve null
    final XFile? image = await _picker.pickImage(source: source, imageQuality: 70, maxWidth: 1024, maxHeight: 1024);

    if (image == null) return null; // Si no hay imegen, se devuelve null

    return _toPickedImage(image);
  }

  // Recupera la foto que se perdio si Android destruyo la MainActivity mientras la camara estaba abierta.
  
  // La solucion a este error se adapto de la ofrecida en la de la pagina oficial de image_picker: https://pub.dev/packages/image_picker

  Future<PickedImage?> recoverLostImage() async {
    if (kIsWeb || !Platform.isAndroid) return null;

    final LostDataResponse response = await _picker.retrieveLostData();

    if (response.isEmpty) return null; // No se perdio nada

    // Si no hay fichero es que el plugin fallo al recuperarlo
    final XFile? image = response.file;
    if (image == null) {
      if (response.exception != null) {
        throw Exception('No se ha podido recuperar la última foto realizada.');
      }
      return null;
    }

    return _toPickedImage(image);
  }

  // Comprueba el tamaño de la imagen y la convierte al formato que usa la app
  Future<PickedImage> _toPickedImage(XFile image) async {
    final int fileLength = await image.length();

    if (fileLength > maxImageBytes) {
      // Si la imagen es mayor que 2MB se lanza excepcion
      throw Exception('La imagen es demasiado pesada. El tamaño máximo permitido es 2MB.');
    }

    if (kIsWeb) { // Si esta en la web, se lee como bytes
      final bytes = await image.readAsBytes();
      return PickedImage(bytes: bytes);
    }
    else { // Si esta en un movil, se lee como archivo
      return PickedImage(file: File(image.path));
    }
  }
}
