import 'package:flutter/material.dart';
import 'package:blablaucm/models/user_model.dart';
import 'package:blablaucm/screens/vehicles.dart';
import 'package:blablaucm/screens/helper.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/screens/profile_image_modal.dart';
import 'package:blablaucm/models/picked_image.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/screens/profile_dialogs.dart';
import 'package:blablaucm/screens/profile_email_flow.dart';
import 'package:blablaucm/providers/storage_provider.dart';
import 'package:blablaucm/screens/login_screen.dart';

// Pantalla de pertfil de usuario

class Profile extends StatefulWidget {
  final UserModel user;
  const Profile({super.key, required this.user});

  @override
  State<Profile> createState() => _ProfileState();
}

class _ProfileState extends State<Profile> {
  final ApiService api = ApiService();
  final SecureStorageService storage = SecureStorageService();
  bool _isToggling2FA = false;

  // Funcion para refrescar la UI
  void _refreshUI() {
    setState(() {});
  }

  // Funcion para activar o desactivar el 2FA
  Future<void> _toggle2FA(bool value) async {
    if (_isToggling2FA) return;

    final bool confirm = await showConfirmationModal(
      context,
      title: value ? "Activar verificación en dos pasos" : "Desactivar verificación en dos pasos",
      message: value
          ? "¿Estás seguro de que deseas activar la verificación en dos pasos? Se te pedirá un código cada vez que inicies sesión."
          : "¿Estás seguro de que deseas desactivar la verificación en dos pasos? Hacer esto reducirá la seguridad de tu cuenta.",
    );
    if (!confirm) return;

    setState(() => _isToggling2FA = true);

    final endpoint = "${dotenv.env['USER_ENDPOINT'] ?? '/users/'}${widget.user.id}/";
    final response = await api.requestToApi(
      endpoint,
      requireAuthentication: true,
      op: ApiOptions.patch,
      body: {'has_2FA': value},
    );

    if (!mounted) return;

    if (response != null && response['error'] == null) {
      setState(() {
        widget.user.has2FA = value;
        _isToggling2FA = false;
      });
    } 
    else {
      setState(() => _isToggling2FA = false);
      showModal(context, "Error al actualizar la verificación en dos pasos. Inténtalo de nuevo.");
    }
  }

  // Funcion para abrir la modal de edicion de foto de perfil
  void _openProfileImageModal(BuildContext context) {
    ProfileImageModal.show(
      context,
      currentImage: widget.user.profilePicture?.image,
      onSave: (PickedImage? image) async {
        // Se muestra una modal para confirmar los cambios
        final bool confirm = await showConfirmationModal(
          context,
          title: "Confirmar cambios",
          message: image != null 
              ? "¿Estás seguro de que deseas actualizar tu foto de perfil?" 
              : "¿Estás seguro de que deseas eliminar tu foto de perfil actual?",
        );

        if (!confirm) return; // Si el usuario cancela, no se hace nada

        try {
          if (image != null) { // Se sube una nueva imagen
            final pictureName = await api.uploadProfileImage(widget.user.id, file: image.file, bytes: image.bytes);
            if (pictureName != null) { // se actualiza la imagen de perfil
              final profile = await api.getProfilePicture(pictureName);
              setState(() => widget.user.profilePicture = profile);
            }
          } 
          else { // Se elimina la imagen actual
            final endpoint = "${dotenv.env['USER_ENDPOINT'] ?? '/users/'}${widget.user.id}/delete-profile_picture/";
            await api.requestToApi(endpoint, requireAuthentication: true, op: ApiOptions.delete);
            setState(() => widget.user.profilePicture = null);
          }
          
          if (!context.mounted) return;
          // Si no hay ningun error, se actualiza la foto de perfil
          showModal(context, "Imagen de perfil actualizada correctamente", title: "Éxito", type: AlertType.success, backPage: true);
          
        } 
        catch (e) { // En caso de que haya algun error, se muestra un mensaje de error
          if (!context.mounted) return;
          showModal(context, "Ha ocurrido un error al actualizar la imagen de perfil. Por favor, inténtalo de nuevo.");
        }
      },
    );
  }

  // Funcion para cerrar sesion
  void _handleLogout(BuildContext context) async {
    
    // Se muestra una ventana de confirmacion del cierre de sesion
    final bool confirm = await showConfirmationModal(
      context,
      title: "Cerrar sesión",
      message: "¿Estás seguro de que deseas cerrar sesión? Tendrás que volver a introducir tus credenciales para acceder.",
      confirmText: "Cerrar sesión",
      confirmColor: Colors.red, // Botón rojo porque es una acción destructiva
    );

    // Si el usuario cancela, no se hace nada
    if (!confirm) return;

    // Se borran los datos del storage
    await storage.deleteAll();
    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil( // Se vuelve a la pantalla de login
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  // Funcion para crear la pantalla de perfil
  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    user.preferences ??= [];

    // Se construye el nombre completo del usuario juntando nombre y apellidos
    final fullName = [user.name, user.surname1, user.surname2].where((e) => e != null && e.trim().isNotEmpty).join(" ");

    return Scaffold(
      appBar: AppBar(title: const Text("Perfil")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(36),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                Card( // Se añaden los campos que se muestran en el perfil
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        GestureDetector( // Foto de perfil
                          onTap: () => _openProfileImageModal(context),
                          child: CircleAvatar(
                            radius: 50,
                            backgroundImage: user.profilePicture?.image,
                            child: user.profilePicture == null ? const Icon(Icons.person, size: 50) : null,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Datos personales
                        ListTile(
                          title: const Text("Datos personales"),
                          subtitle: Text(fullName.isEmpty ? "No especificado" : fullName),
                          trailing: const Icon(Icons.edit),
                          onTap: () => ProfileDialogs.showPersonalDataDialog(context, user, _refreshUI),
                        ),

                        // Nombre de usuario
                        ListTile(
                          title: const Text("Nombre de usuario"),
                          subtitle: Text(user.username),
                          trailing: const Icon(Icons.edit),
                          onTap: () => ProfileDialogs.showUsernameDialog(context, user, _refreshUI),
                        ),

                        // Email
                        ListTile(
                          title: const Text("Email"),
                          subtitle: Text(user.email),
                          trailing: const Icon(Icons.edit),
                          onTap: () => ProfileEmailFlow.start(context, user, _refreshUI),
                        ),

                        // Cambiar contraseña
                        ListTile(
                          title: const Text("Cambiar contraseña"),
                          trailing: const Icon(Icons.edit),
                          onTap: () => ProfileDialogs.showChangePasswordDialog(context),
                        ),

                        const Divider(height: 30),

                        // Verificacion en dos pasos
                        SwitchListTile(
                          title: const Text("Verificación en dos pasos"),
                          subtitle: Text(user.has2FA == true ? "Activada" : "Desactivada"),
                          value: user.has2FA ?? false,
                          activeThumbColor: AppButtonStyles.primaryColor,
                          onChanged: _isToggling2FA ? null : (value) => _toggle2FA(value),
                        ),

                        const Divider(height: 30),

                        // Rol del usuario
                        ListTile(
                          title: const Text("Rol de usuario"),
                          subtitle: Text(user.role.label),
                          trailing: const Icon(Icons.edit),
                          onTap: () => ProfileDialogs.showEditRoleDialog(context,user, user.role, _refreshUI),
                        ),

                        // preferencias del usuario
                        ListTile(
                          title: const Text("Preferencias"),
                          subtitle: Text(user.preferences!.isEmpty ? "Ninguna seleccionada" : "${user.preferences!.length} seleccionadas"),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () => ProfileDialogs.showPreferencesDialog(context, user, _refreshUI),
                        ),

                        const Divider(height: 30),

                        // Lista de vehiculos
                        ListTile(
                          title: const Text("Vehículos"),
                          trailing: const Icon(Icons.directions_car),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VehiclesScreen())),
                        ),

                        // Valoraciones del usuario
                        ListTile(
                          title: const Text("Valoraciones"),
                          trailing: const Icon(Icons.star),
                          onTap: () => showRatingsDialog(context, user.ratings ?? [], numRatings: user.numRatings), 
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Boton de cerrar sesion
                const SizedBox(height: 24), 
                SizedBox(
                  width: double.infinity, 
                  height: 50,
                  child: ElevatedButton.icon(
                    style: AppButtonStyles.danger.copyWith(
                      minimumSize: const WidgetStatePropertyAll(Size(double.infinity, 50)),
                    ),
                    icon: const Icon(Icons.exit_to_app),
                    label: const Text("Cerrar Sesión"),
                    onPressed: () => _handleLogout(context),
                  ),
                ),
                const SizedBox(height: 20), // Margen inferior
              ],
            ),
          ),
        ),
      ),
    );
  }
}