import 'package:flutter/material.dart';
import 'package:blablaucm/models/user_model.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/screens/email_verification.dart';
import 'package:blablaucm/screens/helper.dart';

// Flujo para cambiar el email del perfil
// Primero se pide el nuevo email y se pide confirmacion
// Despues se envia al email un codigo de verificacion
// El usuario debe introducir el codigo para confirmar el cambio

class ProfileEmailFlow {
  static final ApiService api = ApiService();

  static void start(BuildContext context, UserModel user, VoidCallback onSuccess) {
    _editEmail(context, user, onSuccess);
  }

  // Se comprueba que el formato del email es correcto
  static bool _isValidEmail(String email) {
    final regex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    return regex.hasMatch(email);
  }

  // Widget para introducir el nuevo email
  static void _editEmail(BuildContext context, UserModel user, VoidCallback onSuccess, {String? initialError, String? initialEmail}) {
    final controller = TextEditingController(text: initialEmail ?? user.email);
    String? errorText = initialError;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Editar email"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    maxLength: 60, // Maximo 60 caracteres para el email
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: "Nuevo email",
                      border: const OutlineInputBorder(),
                      errorText: errorText, // Muestra los errores si los hay
                    ),
                    onChanged: (_) {
                      if (errorText != null) setStateDialog(() => errorText = null);
                    },
                  ),
                ],
              ),
              actions: [
                dialogButton(context, isAccept: false, label: "Cancelar", onPressed: () => Navigator.pop(context)),
                dialogButton(
                  context,
                  isAccept: true,
                  label: "Continuar",
                  onPressed: () { // Al pulsar en continuar, se valida el email
                    final email = controller.text.trim();
                    if (!_isValidEmail(email)) {
                      setStateDialog(() => errorText = "Email no válido");
                      return;
                    }
                    Navigator.pop(context);
                    _confirmEmailChange(context, user, email, onSuccess);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Funcion para confirmar el cambio
  static void _confirmEmailChange(BuildContext context, UserModel user, String newEmail, VoidCallback onSuccess) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool isChecking = false;

        return StatefulBuilder( // Se muestra una modal para confirmar el cambio
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Confirmar cambio"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("¿Seguro que quieres cambiar tu correo a:\n\n$newEmail?"),
                  if (isChecking)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 10),
                          Text("Verificando email..."),
                        ],
                      ),
                    ),
                ],
              ),
              actions: [
                dialogButton(context, isAccept: false, label: "No", onPressed: isChecking ? null : () => Navigator.pop(context)),
                dialogButton(
                  context,
                  isAccept: true,
                  label: "Sí",
                  isLoading: isChecking,
                  onPressed: () async {
                    setStateDialog(() => isChecking = true);
                    final exists = await _verifyExistingEmail(newEmail); // Se verifica si el email ya esta en uso
                    if (!context.mounted) return;
                    Navigator.pop(context);

                    if (exists) { // Si ya esta en uso, se muestra un mensaje de error
                      _editEmail(context, user, onSuccess, initialError: "El email ya está en uso", initialEmail: newEmail);
                    }
                    else { // Si no esta en uso, se pasa al widget para introducir el codigo de verificacion
                      _showVerificationCodeDialog(context, user, newEmail, onSuccess);
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Función para verificar si el email ya esta en uso, devuelve true unicamente si el backend devuelve que el email esta libre, en caso contrario se devuelve false
  static Future<bool> _verifyExistingEmail(String newEmail) async {
    // Se construye el endpoint
    final endpoint = dotenv.env['VERIFY_EXIST_EMAIL_ENDPOINT'] ?? '/users/exist_email/';
    // Se hace la petición a la api
    final response = await api.requestToApi(endpoint, queryParams: {'email': newEmail});
    return !(response != null && response['status']?.toLowerCase() == 'ok');
  }

  // Widget para introducir el codigo de verificacion
  static void _showVerificationCodeDialog(BuildContext context, UserModel user, String newEmail, VoidCallback onSuccess) {
    EmailVerification.showVerificationDialog(
      context: context,
      email: newEmail,
      onSendCode: () => EmailVerification.sendVerificationEmail(
        username: user.username,
        email: newEmail,
      ),
      onVerifyCode: (code) => EmailVerification.verifyCode(
        username: user.username,
        code: code,
        email: newEmail,
      ),
      onSuccess: () {
        user.email = newEmail;
        onSuccess();
      },
    );
  }
}
