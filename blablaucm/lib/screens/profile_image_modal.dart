import 'package:flutter/material.dart';
import 'package:blablaucm/models/picked_image.dart';
import 'package:blablaucm/services/image_picker_service.dart';
import 'package:image_picker/image_picker.dart';

// Clase para gestionar la imagen de perfil del usuario, permitiendo que suba o elimine su foto

class ProfileImageModal {

  // Funcion para mostrar la modal de la imagen de perfil, recibe la imagen actual
  static void show(BuildContext context, { required ImageProvider? currentImage, required Function(PickedImage?) onSave}) {
    final picker = ImagePickerService();
    PickedImage? selectedImage;
    bool changed = false;
    bool isDeleted = false; // Para saber si el usuario elimino la foto que tenia

    // Funcion para obtener la imagen
    ImageProvider? getImageProvider() {
      if (isDeleted) { // Si el usuario elimina la foto, se marca como null y se muestra el icono de persona
        return null;
      }
      // Se devuelve la imagen
      if (selectedImage?.bytes != null) {
        return MemoryImage(selectedImage!.bytes!);
      } 
      else if (selectedImage?.file != null) {
        return FileImage(selectedImage!.file!);
      } 
      else {
        return currentImage;
      }
    }

    // Modal para mostrar la imagen de perfil con las opciones de subir imagen y borrar
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            
            final bool hasImage = getImageProvider() != null;

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  CircleAvatar( // Se muestra la imagen o el icono de persona si no hay
                    radius: 60,
                    backgroundImage: getImageProvider(),
                    child: getImageProvider() == null ? const Icon(Icons.person, size: 60) : null,
                  ),

                  const SizedBox(height: 20),

                  ElevatedButton.icon( // Opcion para subir una imagen desde la camara
                    icon: const Icon(Icons.camera_alt),
                    label: const Text("Cámara"),
                    onPressed: () async {
                      final img = await picker.pickUpImage(ImageSource.camera); // Se obtiene la imagen de la camara
                      if (img != null) {
                        setState(() {
                          selectedImage = img;
                          isDeleted = false;
                          changed = true;
                        });
                      }
                    },
                  ),

                  ElevatedButton.icon( // Opcion para subir una imagen desde la galeria
                    icon: const Icon(Icons.photo),
                    label: const Text("Galería"),
                    onPressed: () async {
                      final img = await picker.pickUpImage(ImageSource.gallery); // Se abre la galeria para obtener una imagen
                      if (img != null) {
                        setState(() {
                          selectedImage = img;
                          isDeleted = false;
                          changed = true;
                        });
                      }
                    },
                  ),

                  TextButton.icon( // Boton para eliminar la foto que tiene
                    icon: Icon(
                      Icons.delete,
                      color: hasImage ? Colors.red : Colors.grey, 
                    ),
                    label: Text(
                      "Eliminar foto",
                      style: TextStyle(color: hasImage ? Colors.red : Colors.grey),
                    ),
                    onPressed: hasImage
                        ? () {
                            setState(() {
                              selectedImage = null;
                              isDeleted = true;
                              changed = true;
                            });
                          }
                        : null, // Si no hay foto, se desactiva el boton pasandole null (no se puede borrar si no hay)
                  ),

                  const SizedBox(height: 20),

                  Row( // Botones de cancelar y guardar los cambios
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Cancelar"),
                      ),
                      ElevatedButton(
                        // Si la foto fue eliminada, se pasa null a la api para que la borre, sino se le pasa la nueva foto
                        onPressed: changed ? () {onSave(isDeleted ? null : selectedImage);} : null,
                        child: const Text("Guardar"),
                      ),
                    ],
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }
}