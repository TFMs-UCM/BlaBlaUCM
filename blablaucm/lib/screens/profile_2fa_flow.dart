import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/models/api_error.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/models/user_model.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/screens/custom_form_fields.dart';
import 'package:blablaucm/screens/email_verification.dart';
import 'package:blablaucm/screens/helper.dart';

// Clase que contiene el flujo para activar y desactivar la verificacion en dos pasos
// Primero se pide confirmacion, despues se acredita la identidad y al final se avisa de que el cambio se ha hecho.
// Si solo tiene cuenta con Google, se acredita con un codigo al correo, si tiene contraseña, se acredita con la contraseña actual

class Profile2FAFlow {
  static final ApiService api = ApiService();

  //Inicia el flujo, enable es el estado al que se quiere llegar.
  static void start(BuildContext context, UserModel user, bool enable,{required VoidCallback onSuccess, required VoidCallback onFinished}) {
    _confirm(context, user, enable, onSuccess: onSuccess, onFinished: onFinished);
  }

  // Paso 1: confirmacion
  static Future<void> _confirm(BuildContext context, UserModel user, bool enable,
      {required VoidCallback onSuccess, required VoidCallback onFinished}) async {
    final bool confirmed = await showConfirmationModal(
      context,
      title: enable ? "Activar verificación en dos pasos" : "Desactivar verificación en dos pasos",
      message: enable
          ? "¿Estás seguro de que deseas activar la verificación en dos pasos? Se te pedirá un código cada vez que inicies sesión."
          : "¿Estás seguro de que deseas desactivar la verificación en dos pasos? Hacer esto reducirá la seguridad de tu cuenta.",
    );

    if (!confirmed || !context.mounted) {
      onFinished();
      return;
    }

    // Se pasa al paso 2, para acreditar la identidad
    await _askForCredential(context, user, enable, onSuccess: onSuccess, onFinished: onFinished);
  }

  // Paso 2: se pregunta a la api como hay que acreditarse y se pide
  static Future<void> _askForCredential(BuildContext context, UserModel user, bool enable, {required VoidCallback onSuccess, required VoidCallback onFinished}) async {
    final method = await _challenge(user);

    if (!context.mounted) return;

    if (method is ApiError) { // Hay un error, no se puede seguir con el flujo
      onFinished();
      showModal(context, EmailVerification.messageFor(method));
      return;
    }

    if (method == 'email') { // Se pide el codigo que se ha enviado al correo
      _askForCode(context, user, enable, onSuccess: onSuccess, onFinished: onFinished);
    }
    else { // Se pide la contraseña actual
      _askForPassword(context, user, enable, onSuccess: onSuccess, onFinished: onFinished);
    }
  }

  // Funcion que devuelve el metodo ("password" / "email") o el error
  static Future<Object> _challenge(UserModel user) async {
    final endpoint = "${dotenv.env['USER_ENDPOINT'] ?? '/users/'}${user.id}${dotenv.env['TWO_FACTOR_CHALLENGE_ENDPOINT'] ?? '/two_factor/challenge/'}";

    final response = await api.requestToApi(
      endpoint,
      requireAuthentication: true,
      op: ApiOptions.post,
    );

    if (response == null) return ApiError.connection;

    final error = ApiError.from(response);
    if (error != null) return error;

    final method = response['method'];
    if (method is String) return method;

    return ApiError.connection;
  }

  // Paso 2a: cuenta con contraseña, por lo que se le pide esta para verificar su autenticidad
  static void _askForPassword(BuildContext context, UserModel user, bool enable, {required VoidCallback onSuccess, required VoidCallback onFinished}) {
    final passwordCtrl = TextEditingController();
    bool obscure = true;
    bool isLoading = false;
    bool changed = false;
    String? errorText;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (innerContext, setStateDialog) => AlertDialog(
          title: Text(enable ? "Activar verificación en dos pasos" : "Desactivar verificación en dos pasos"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Introduce tu contraseña actual para confirmar el cambio.",
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                passwordField( // Campo para introducir la contraseña
                  "Contraseña actual",
                  passwordCtrl,
                  obscure,
                  () => setStateDialog(() => obscure = !obscure),
                  errorText: errorText,
                  labelText: "Contraseña actual",
                  errorMaxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            dialogButton(
              innerContext,
              isAccept: false,
              label: "Cancelar",
              onPressed: isLoading ? null : () => Navigator.pop(innerContext),
            ),
            dialogButton(
              innerContext,
              isAccept: true,
              label: "Confirmar",
              isLoading: isLoading,
              onPressed: () async {
                final password = passwordCtrl.text;
                if (password.isEmpty) {
                  setStateDialog(() => errorText = "Introduce tu contraseña actual");
                  return;
                }

                setStateDialog(() { isLoading = true; errorText = null; });

                final error = await _setSecondFactor(user, enable, password: password);

                if (!innerContext.mounted){
                  return;
                }
                if (error == null) {
                  changed = true;
                  Navigator.pop(innerContext);
                  _done(context, enable, onSuccess: onSuccess, onFinished: onFinished);
                }
                else {
                  setStateDialog(() {
                    isLoading = false;
                    errorText = error.code == ErrorCode.invalidCredentials ? "La contraseña no es correcta" : EmailVerification.messageFor(error);
                  });
                }
              },
            ),
          ],
        ),
      ),
    ).then((_) {
      if (!changed){
        onFinished();
      }
    });
  }

  // Paso 2b: no tiene contraseña, por lo que se acredita con el codigo del correo
  static void _askForCode(BuildContext context, UserModel user, bool enable, {required VoidCallback onSuccess, required VoidCallback onFinished}) {
    bool changed = false;

    EmailVerification.showVerificationDialog(
      context: context,
      email: user.email,
      customMessage: "Para confirmar el cambio, introduce el código que hemos enviado a:\n${user.email}",
      skipInitialSend: true,
      onSendCode: () async {
        final method = await _challenge(user);
        return method is ApiError ? method : null;
      },
      onVerifyCode: (code) => _setSecondFactor(user, enable, code: code),
      onSuccess: () {
        changed = true;
        _done(context, enable, onSuccess: onSuccess, onFinished: onFinished);
      },
    ).then((_) {
      if (!changed){
        onFinished();
      }
    });
  }

  // Funcion para mandar el cambio a la api, devuelve null si se ha hecho
  static Future<ApiError?> _setSecondFactor(UserModel user, bool enable, {String? password, String? code}) async {
    final endpoint = "${dotenv.env['USER_ENDPOINT'] ?? '/users/'}${user.id}${dotenv.env['TWO_FACTOR_ENDPOINT'] ?? '/two_factor/'}";

    final Map<String, dynamic> body = {'enabled': enable};
    if (password != null){
      body['password'] = password;
    }
    if (code != null){
      body['code'] = code;
    } 

    final response = await api.requestToApi(
      endpoint,
      requireAuthentication: true,
      op: ApiOptions.post,
      body: body,
    );

    if (response == null) return ApiError.connection;

    final error = ApiError.from(response);
    if (error != null) return error;

    // Se exige la confirmacion de la api
    if (response['status']?.toString().toLowerCase() == 'ok') {
      // El servidor manda un par de tokens nuevos para que este dispositivo no se quede fuera, por lo que se guardan antes de seguir
      await api.saveSession(response);
      return null;
    }

    return ApiError.connection;
  }

  // Paso 3: aviso de que el cambio se ha hecho
  static void _done(BuildContext context, bool enable, {required VoidCallback onSuccess, required VoidCallback onFinished}) {
    onSuccess();
    onFinished();

    if (!context.mounted) return;

    showModal(
      context,
      enable
          ? "La verificación en dos pasos está activada. Te pediremos un código cada vez que inicies sesión."
          : "La verificación en dos pasos está desactivada.",
      title: "Éxito",
      type: AlertType.success,
    );
  }
}
