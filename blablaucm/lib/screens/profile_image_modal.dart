import 'package:flutter/material.dart';
import 'package:blablaucm/models/picked_image.dart';
import 'package:blablaucm/services/image_picker_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:blablaucm/screens/helper.dart';

// Clase para gestionar la imagen de perfil del usuario, permitiendo que suba o elimine su foto

class ProfileImageModal {

  // Funcion para mostrar la modal de la imagen de perfil, recibe la imagen actual
  static void show(BuildContext context, { required ImageProvider? currentImage, required Function(PickedImage?) onSave, PickedImage? initialImage}) {
    final picker = ImagePickerService();
    PickedImage? selectedImage = initialImage;
    bool changed = initialImage != null; // Con la foto ya puesta se puede guardar
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

                  SizedBox(
                    width: 140,
                    child: dialogButton(context, isAccept: true, icon: Icons.camera_alt, label: "Cámara",
                    onPressed: () async {
                      try {
                        final img = await picker.pickUpImage(ImageSource.camera);
                        if (img != null) {
                          setState(() {
                            selectedImage = img;
                            isDeleted = false;
                            changed = true;
                          });
                        }
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(e.toString().replaceAll('Exception: ', '')),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                  ),
                  ),

                  const SizedBox(height: 8),

                  SizedBox(
                    width: 140,
                    child: dialogButton(context, isAccept: true, icon: Icons.photo, label: "Galería",
                    onPressed: () async {
                      try {
                        final img = await picker.pickUpImage(ImageSource.gallery);
                        if (img != null) {
                          setState(() {
                            selectedImage = img;
                            isDeleted = false;
                            changed = true;
                          });
                        }
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(e.toString().replaceAll('Exception: ', '')),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                  ),
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: 140,
                    child: ElevatedButton.icon( // Boton para eliminar la foto que tiene
                      style: AppButtonStyles.danger,
                      icon: const Icon(Icons.delete),
                      label: const Text("Eliminar"),
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
                  ),

                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      dialogButton(context, isAccept: false, label: "Cancelar", onPressed: () => Navigator.pop(context)),
                      // Si la foto fue eliminada, se pasa null a la api para que la borre, sino se le pasa la nueva foto
                      dialogButton(context, isAccept: true, label: "Guardar",
                        onPressed: changed
                            ? () async {
                                final PickedImage? result = isDeleted ? null : selectedImage;
                                // Se le pide la confirmacion al usuario
                                final bool confirm = await showConfirmationModal(
                                  context,
                                  title: "Confirmar cambios",
                                  message: result != null
                                      ? "¿Estás seguro de que deseas actualizar tu foto de perfil?"
                                      : "¿Estás seguro de que deseas eliminar tu foto de perfil actual?",
                                );

                                if (!confirm || !context.mounted){
                                  return;
                                }
                                Navigator.pop(context);
                                onSave(result);
                              }
                            : null,
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