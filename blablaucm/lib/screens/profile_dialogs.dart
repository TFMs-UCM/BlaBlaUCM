import 'package:flutter/material.dart';
import 'package:blablaucm/models/user_model.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/providers/storage_provider.dart';
import 'package:blablaucm/screens/helper.dart';
import 'package:blablaucm/screens/custom_form_fields.dart';

// Clase que contiene los Widgets para los distintos elementos del perfil

class ProfileDialogs {
  static final ApiService api = ApiService();
  static final SecureStorageService storage = SecureStorageService();

  // Widget para editar los datos personales (nombre y apellidos)
  static void showPersonalDataDialog(BuildContext context, UserModel user, VoidCallback onSuccess) {
    final nameCtrl = TextEditingController(text: user.name);
    final surname1Ctrl = TextEditingController(text: user.surname1);
    final surname2Ctrl = TextEditingController(text: user.surname2 ?? '');

    String? nameError;
    String? surname1Error;
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (innerContext, setStateDialog) => AlertDialog(
          title: const Text("Editar datos personales"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [ // Un campo de texto para cada uno de los datos
              TextField(
                controller: nameCtrl,
                maxLength: 50,
                decoration: InputDecoration(labelText: "Nombre", border: const OutlineInputBorder(), errorText: nameError, errorMaxLines: 3),
                onChanged: (_) { if (nameError != null) setStateDialog(() => nameError = null); },
                enabled: !isLoading,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: surname1Ctrl,
                maxLength: 50,
                decoration: InputDecoration(labelText: "Primer Apellido", border: const OutlineInputBorder(), errorText: surname1Error, errorMaxLines: 3),
                onChanged: (_) { if (surname1Error != null) setStateDialog(() => surname1Error = null); },
                enabled: !isLoading,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: surname2Ctrl,
                maxLength: 50,
                decoration: const InputDecoration(labelText: "Segundo Apellido (Opcional)", border: OutlineInputBorder()),
                enabled: !isLoading,
              ),
            ],
          ),
          actions: [ // Si se pulsa cancelar se cierra la modal, si se pulsa guardar se validan y se envian a la api los datos
            dialogButton(innerContext, isAccept: false, label: "Cancelar", onPressed: isLoading ? null : () => Navigator.pop(innerContext)),
            dialogButton(
              innerContext,
              isAccept: true,
              label: "Guardar",
              isLoading: isLoading,
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final surname1 = surname1Ctrl.text.trim();
                final surname2 = surname2Ctrl.text.trim(); // el segundo apellido es opcional

                if (name.isEmpty || surname1.isEmpty) { // Se validan los campos
                  setStateDialog(() {
                    nameError = name.isEmpty ? "Este campo no puede estar vacío" : null;
                    surname1Error = surname1.isEmpty ? "Este campo no puede estar vacío" : null;
                  });
                  return;
                }

                // Se muestra una modal de confirmacion para guardar los datos
                final bool confirm = await showConfirmationModal(
                  context,
                  title: "Confirmar cambios",
                  message: "¿Estás seguro de que deseas actualizar tu informacion personal?",
                );

                if (!confirm) return; // Si el usuario no confirma, se sale

                setStateDialog(() => isLoading = true);
                // Se construye el endpoint y se hace la peticion a la api
                final endpoint = "${dotenv.env['USER_ENDPOINT'] ?? '/users/'}${await storage.getElement('user_id')}/";
                final response = await api.requestToApi(
                  endpoint, requireAuthentication: true,
                  body: {"name": name, "surname1": surname1, "surname2": surname2},
                  op: ApiOptions.patch,
                );

                if (!innerContext.mounted) return;

                if (response != null && response['error'] == null) { // Si no hay fallos, se actualiza el nombre y los apellidos
                  user.name = name; user.surname1 = surname1; user.surname2 = surname2;
                  onSuccess();

                  Navigator.pop(innerContext);
                  showModal(context, "Tus datos personales se han actualizado correctamente.", title: "Éxito", type: AlertType.success);
                }
                else { // Si hay un error, se muestra un mensaje
                  setStateDialog(() {
                    isLoading = false;
                    nameError = "Error en el servidor al actualizar los datos";
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // Widget para editar el nombre de usuario
  static void showUsernameDialog(BuildContext context, UserModel user, VoidCallback onSuccess) {
    final controller = TextEditingController(text: user.username);
    String? errorText;
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (innerContext, setStateDialog) => AlertDialog(
          title: const Text("Editar nombre de usuario"),
          content: TextField(
            controller: controller,
            enabled: !isLoading,
            maxLength: 20,
            decoration: InputDecoration(labelText: "Nuevo nombre de usuario", border: const OutlineInputBorder(), errorText: errorText, errorMaxLines: 3),
            onChanged: (_) { if (errorText != null) setStateDialog(() => errorText = null); },
          ),
          actions: [
            dialogButton(innerContext, isAccept: false, label: "Cancelar", onPressed: isLoading ? null : () => Navigator.pop(innerContext)),
            dialogButton(
              innerContext,
              isAccept: true,
              label: "Guardar",
              isLoading: isLoading,
              onPressed: () async {
                final username = controller.text.trim();
                // No se puede cambiar a uno vacio ni al mismo que el actual
                if (username.isEmpty) { setStateDialog(() => errorText = "No puede estar vacío"); return; }
                if (username == user.username) { setStateDialog(() => errorText = "Debe ser diferente al nombre de usuario actual"); return; }

                // Se muestra una modal de confirmacion para confirmar la accion de modificacion
                final bool confirm = await showConfirmationModal(
                  context,
                  title: "Confirmar cambios",
                  message: "¿Estás seguro de que deseas actualizar nombre de usuario?",
                );

                if (!confirm) return; // Si no se confirma, se sale de la modal

                setStateDialog(() => isLoading = true);

                // Se construye el endpoint y se hace la peticion a la api
                final endpoint = "${dotenv.env['USER_ENDPOINT'] ?? '/users/'}${await storage.getElement('user_id')}/";
                final response = await api.requestToApi(endpoint, requireAuthentication: true, body: {"username": username}, op: ApiOptions.patch);

                if (!innerContext.mounted) return;

                // Si ese nombre de usuario ya existe, se muestra un mensaje de error
                if (response != null && response['code'].toString() == ErrorCode.usernameAlreadyExists.toString()) {
                  setStateDialog(() { errorText = response["message"]; isLoading = false; });
                }
                // Se comprueba que el username que devuelva la api sea el mismo que el introducido
                else if (response != null && response['username']?.toLowerCase() == username.toLowerCase()) {
                  user.username = username;
                  onSuccess();

                  Navigator.pop(innerContext);
                  showModal(context, "Tu nombre de usuario se ha actualizado correctamente.", title: "Éxito", type: AlertType.success);
                }
                else { // Si hay algun error, se muestra el mensaje de error
                  setStateDialog(() {
                    isLoading = false;
                    errorText = response?['error']?['message'] ?? "Error al modificar el nombre de usuario";
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // Widget para editar el rol de usuario
  static void showEditRoleDialog(BuildContext context, UserModel user, UsersType currentRole, VoidCallback onSuccess) {
    UsersType selectedRole = currentRole;
    String? errorText;
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (innerContext, setStateDialog) => AlertDialog(
          title: const Text("Editar rol de usuario"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              buildDropdownRow<UsersType>( // Un menu desplegable para seleccionar el rol
                label: "Selecciona el nuevo rol:",
                currentValue: selectedRole,
                items: UsersType.values.where((u) => u != UsersType.all).toList(),
                labelGetter: (UsersType role) => role.label,
                editMode: true,
                errorText: errorText,
                tooltipText: "Al cambiar el rol, se notificara a los usuarios que han solicitado viajes contigo sobre el cambio.",
                onChanged: isLoading ? (_) {} : (UsersType? newValue) {
                  if (newValue != null) {
                    setStateDialog(() {
                      selectedRole = newValue;
                      if (errorText != null) errorText = null;
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            dialogButton(innerContext, isAccept: false, label: "Cancelar", onPressed: isLoading ? null : () => Navigator.pop(innerContext)),
            dialogButton(
              innerContext,
              isAccept: true,
              label: "Guardar",
              isLoading: isLoading,
              onPressed: () async {
                if (selectedRole == currentRole) { // El nuevo rol no puede ser el mismo que el actual
                  setStateDialog(() => errorText = "Debe ser diferente al rol actual");
                  return;
                }

                // Se muestra una ventana modal para que el usuario confirme la modificacion
                final bool confirm = await showConfirmationModal(
                  context,
                  title: "Confirmar cambios",
                  message: "¿Estás seguro de que deseas cambiar el rol de este usuario a ${selectedRole.label}?",
                );

                if (!confirm) return; // Si el usuario no confirma, se sale de la modal

                setStateDialog(() => isLoading = true);

                // Se construye el endpoint y se hace la peticion a la api
                final endpoint = "${dotenv.env['USER_ENDPOINT'] ?? '/users/'}${await storage.getElement('user_id')}/";
                final response = await api.requestToApi(
                  endpoint,
                  requireAuthentication: true,
                  body: {"user_type": selectedRole.name},
                  op: ApiOptions.patch,
                );

                if (!innerContext.mounted) return;

                if (response != null && response['error'] == null) { // Si no hay errores, se actualiza el rol del usuario
                  user.role = selectedRole;
                  onSuccess();

                  Navigator.pop(innerContext);
                  showModal(context, "El rol se ha actualizado correctamente.", title: "Éxito", type: AlertType.success);
                }
                else {
                  setStateDialog(() {
                    isLoading = false;
                    errorText = response?['error']?['message'] ?? "Error al modificar el rol";
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // Widget para cambiar la contraseña del usuario
  static void showChangePasswordDialog(BuildContext context) {
    final currentPasswordCtrl = TextEditingController();
    final newPasswordCtrl = TextEditingController();
    final confirmPasswordCtrl = TextEditingController();

    bool isLoading = false;
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

    String? currentPasswordError;
    String? newPasswordError;
    String? confirmPasswordError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (innerContext, setStateDialog) => AlertDialog(
          title: const Text("Cambiar contraseña"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                passwordField(
                  "Contraseña actual",
                  currentPasswordCtrl,
                  obscureCurrent,
                  () => setStateDialog(() => obscureCurrent = !obscureCurrent),
                  errorText: currentPasswordError,
                  labelText: "Contraseña actual",
                  errorMaxLines: 3,
                ),
                passwordField(
                  "Nueva contraseña",
                  newPasswordCtrl,
                  obscureNew,
                  () => setStateDialog(() => obscureNew = !obscureNew),
                  errorText: newPasswordError,
                  labelText: "Nueva contraseña",
                  errorMaxLines: 3,
                ),
                passwordField(
                  "Repetir nueva contraseña",
                  confirmPasswordCtrl,
                  obscureConfirm,
                  () => setStateDialog(() => obscureConfirm = !obscureConfirm),
                  errorText: confirmPasswordError,
                  labelText: "Repetir contraseña",
                  errorMaxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            dialogButton(innerContext, isAccept: false, label: "Cancelar", onPressed: isLoading ? null : () => Navigator.pop(innerContext)),
            dialogButton(
              innerContext,
              isAccept: true,
              label: "Guardar",
              isLoading: isLoading,
              onPressed: () async {
                final current = currentPasswordCtrl.text;
                final newPass = newPasswordCtrl.text;
                final confirm = confirmPasswordCtrl.text;

                setStateDialog(() {
                  currentPasswordError = null;
                  newPasswordError = null;
                  confirmPasswordError = null;
                });

                // Se compreuban los campos
                bool hasError = false;
                if (current.isEmpty) {
                  setStateDialog(() => currentPasswordError = "Introduce tu contraseña actual");
                  hasError = true;
                }
                if (newPass.isEmpty) {
                  setStateDialog(() => newPasswordError = "Introduce la nueva contraseña");
                  hasError = true;
                }
                else if (newPass.length < 6) {
                  setStateDialog(() => newPasswordError = "La contraseña debe tener al menos 6 caracteres");
                  hasError = true;
                }
                if (newPass != confirm) {
                  setStateDialog(() {
                    newPasswordError = "Las contraseñas no coinciden";
                    confirmPasswordError = "Las contraseñas no coinciden";
                  });
                  hasError = true;
                }
                if (newPass == current) {
                  setStateDialog(() {
                    newPasswordError = "La nueva contraseña no puede ser igual a la actual";
                    confirmPasswordError = "La nueva contraseña no puede ser igual a la actual";
                  });
                  hasError = true;
                }

                if (hasError) return;

                final bool confirmed = await showConfirmationModal(
                  context,
                  title: "Cambiar contraseña",
                  message: "¿Estás seguro de que deseas cambiar tu contraseña?",
                );
                if (!confirmed) return;

                setStateDialog(() => isLoading = true);

                final endpoint = "${dotenv.env['USER_ENDPOINT'] ?? '/users/'}${await storage.getElement('user_id')}${dotenv.env['CHANGE_PASSWORD_ENDPOINT'] ?? '/change_password/'}";
                final response = await api.requestToApi(
                  endpoint,
                  requireAuthentication: true,
                  op: ApiOptions.post,
                  body: {
                    'current_password': current,
                    'new_password': newPass,
                  },
                );

                if (!innerContext.mounted) return;

                if (response != null && response['status']?.toLowerCase() == 'ok') {
                  Navigator.pop(innerContext);
                  showModal(context, "Tu contraseña se ha cambiado correctamente.", title: "Éxito", type: AlertType.success);
                }
                else {
                  final rawCode = response?['error_code'];
                  final errorCode = rawCode != null ? ErrorCode.fromCode(int.tryParse(rawCode.toString()) ?? -1) : ErrorCode.unknownError;
                  setStateDialog(() {
                    isLoading = false;
                    if (errorCode == ErrorCode.invalidCredentials) {
                      currentPasswordError = "La contraseña no es correcta";
                    }
                    else {
                      currentPasswordError = response?['error']?['message'] ?? "Error al cambiar la contraseña";
                    }
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // Widget para editar las preferencias del conductor
  static void showPreferencesDialog(BuildContext context, UserModel user, VoidCallback onSuccess) {
    List<DriverPreferences> tempPreferences = List.from(user.preferences ?? []);
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (innerContext, setStateDialog) => AlertDialog(
          title: const Text("Preferencias del conductor"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: DriverPreferences.values.map((pref) { // Se crean los checkboxes para cada preferencia
                return CheckboxListTile(
                  title: Text(pref.label),
                  value: tempPreferences.contains(pref),
                  enabled: !isLoading,
                  onChanged: (val) => setStateDialog(() { val == true ? tempPreferences.add(pref) : tempPreferences.remove(pref); }),
                );
              }).toList(),
            ),
          ),
          actions: [
            dialogButton(innerContext, isAccept: false, label: "Cancelar", onPressed: isLoading ? null : () => Navigator.pop(innerContext)),
            dialogButton(
              innerContext,
              isAccept: true,
              label: "Guardar",
              isLoading: isLoading,
              onPressed: () async {
                // Se crea el endpoint
                String endpoint = "${dotenv.env['USER_ENDPOINT'] ?? '/users/'}${await storage.getElement('user_id')}${dotenv.env['UPDATE_PREFERENCES_ENDPOINT'] ?? '/update-preferences/'}";
                final prefsData = tempPreferences.map((e) => e.name).toList();

                if (!innerContext.mounted) return;

                // Se muestra una modal para confirmar la modificacion
                final bool confirm = await showConfirmationModal(
                  innerContext,
                  title: "Confirmar cambios",
                  message: "¿Estás seguro de que deseas actualizar tus preferencias?",
                );

                if (!confirm) return; // Si no se confirma, se sale de la modal

                setStateDialog(() => isLoading = true);

                // Se realiza la peticion a la api para actualizar las preferencias
                final response = await api.requestToApi(endpoint, requireAuthentication: true, body: {"preferences": prefsData}, op: ApiOptions.patch);

                if (!innerContext.mounted) return;

                if (response != null && response['error'] == null) { // Si no hay errores, se actualizan las preferencias del usuario
                  user.preferences = tempPreferences;
                  onSuccess();

                  Navigator.pop(innerContext);
                  showModal(context, "Tus preferencias de viaje se han guardado correctamente.", title: "Éxito", type: AlertType.success);
                }
                else { // Si hay error, se muestra un mensaje de error
                  setStateDialog(() => isLoading = false);
                  showModal(context, "Error al actualizar las preferencias.");
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
