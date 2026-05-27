import 'dart:io';
import 'dart:typed_data';

// Clase que representa una imagen
class PickedImage {
  final File? file;
  final Uint8List? bytes;

  PickedImage({this.file, this.bytes});
}