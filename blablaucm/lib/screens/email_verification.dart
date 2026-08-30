import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/models/api_error.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/theme/app_colors.dart';

// Clase para el registro, devuelve un error si lo hubo, y un booleano indicando si la sesion se ha iniciado (la api devuelve la sesion al validar la cuenta)
class RegistrationVerification {
  final ApiError? error;
  final bool sessionStarted;

  const RegistrationVerification({this.error, this.sessionStarted = false});
}

// Clase para la verificacion mediante Email
class EmailVerification {
  static final ApiService _api = ApiService();

  // Funcion para solicitar a la api el codigo de verificacion
  static Future<ApiError?> sendVerificationEmail({required String username, String? email}) async {
    // Se construye en endpoint
    final endpoint = dotenv.env['VERIFICATION_EMAIL_ENDPOINT'] ?? '/users/verify_email/';

    final Map<String, String> body = {'username': username};

    // Si se añade el email, se añade al body
    if (email != null) {
      body['email'] = email;
    }

    // Se realiza la peticion a la api, si se manda un email distinto al de la cuenta (cambio de correo desde el perfil), la api exige que el que lo pide este autenticado y sea el dueño
    final response = await _api.requestToApi(
      endpoint,
      requireAuthentication: email != null,
      body:body,
      op: ApiOptions.post
    );

    if (response == null) return ApiError.connection;
    return ApiError.from(response);
  }

  // Funcion para verificar el codigo
  static Future<ApiError?> verifyCode({required String username, required String code, String? email, String? password, bool validate = false}) async {
    final response = await _postVerifyCode(
      username: username,
      code: code,
      email: email,
      password: password,
      validate: validate,
    );
    return _errorOf(response);
  }

  // Ultimo paso del registro con usuario y contraseña, valida la cuenta y deja al usuario dentro de la app
  // Al validarse, la api devuelve la sesion ya iniciada (los mismos tokens que el login)
  static Future<RegistrationVerification> verifyRegistration({required String username, required String code}) async {
    final response = await _postVerifyCode(username: username, code: code, validate: true);

    final error = _errorOf(response);
    if (error != null) return RegistrationVerification(error: error);

    final started = await _api.saveSession(response);
    return RegistrationVerification(sessionStarted: started);
  }

  // Peticion al endpoint de canje del codigo. Devuelve el cuerpo tal cual, que es lo que necesita el registro para quedarse con la sesion
  static Future<Map<String, dynamic>?> _postVerifyCode({required String username, required String code, String? email, String? password, bool validate = false}) async {
    final endpoint = dotenv.env['VERIFY_CODE_ENDPOINT'] ?? '/users/verify_code/';
    // Se añaden los paramentros al body
    final Map<String, dynamic> body = {
      'username': username,
      'token': code,
    };

    // Si trae los parametros opcionales, se añaden
    if (email != null) {
      body['email'] = email;
    }
    if (password != null) {
      body['password'] = password;
    }
    if (validate) {
      body['validate'] = true;
    }

    // Se realiza la peticion a la api, cambiar el correo de la cuenta exige estar autenticado como su dueño, igual que al pedir el codigo
    return _api.requestToApi(
      endpoint,
      body: body,
      requireAuthentication: email != null,
      op: ApiOptions.post,
    );
  }

  // Traduce la respuesta del canje del codigo a error, o null si fue bien
  static ApiError? _errorOf(Map<String, dynamic>? response) {
    if (response == null) return ApiError.connection;

    final error = ApiError.from(response);
    if (error != null) return error;

    if (response['status']?.toString().toLowerCase() == 'ok') return null;
    return ApiError.connection;
  }

  // Traduce un error del canje del codigo al mensaje que ve el usuario
  static String messageFor(ApiError error) {
    switch (error.code) {
      case ErrorCode.incorrectToken:
        return "Código incorrecto";
      case ErrorCode.tokenExpired:
        return "El código ha caducado. Pide uno nuevo.";
      case ErrorCode.emailAlreadyExists:
        return "Ese correo ya está en uso por otra cuenta.";
      case ErrorCode.tooManyRequests:
        return "Demasiados intentos. Espera unos minutos y vuelve a probar.";
      case ErrorCode.userDontExist:
        return "No existe ninguna cuenta con ese usuario.";
      case ErrorCode.insufficientCredentials:
        return "No tienes permiso para hacer este cambio.";
      case ErrorCode.emailError:
        return "No se ha podido enviar el correo. Inténtalo de nuevo.";
      default:
        return error.message;
    }
  }

  // Modal para introduicir el codigo de verificacion de 6 digitos
  static Future<void> showVerificationDialog({required BuildContext context, String? email, required Future<ApiError?> Function() onSendCode,
      required Future<ApiError?> Function(String code) onVerifyCode, required VoidCallback onSuccess, String? customMessage, bool skipInitialSend = false}) {
    List<TextEditingController> controllers = List.generate(6, (_) => TextEditingController());
    List<FocusNode> focusNodes = List.generate(6, (_) => FocusNode()); // Se crea un Focus node para cada uno de los caracteres
    bool isLoading = false;
    bool isSending = !skipInitialSend;
    bool hasSent = skipInitialSend;
    String? errorText;

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (innerContext, setStateDialog) {
            
            if (!hasSent) { // Se envia el codigo al abrir la modal
              hasSent = true;
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                final error = await onSendCode();
                if (!innerContext.mounted) return;
                setStateDialog(() {
                  isSending = false;
                  errorText = error == null ? null : messageFor(error);
                });
                focusNodes[0].requestFocus();
              });
            }

            // Funcion para reenviar el codigo
            void resendCode() async {
              setStateDialog(() {
                isSending = true;
                errorText = null;
              });
              // Se limpian los campos
              for (var c in controllers) { c.clear(); }

              final error = await onSendCode();

              if (!innerContext.mounted) return;
              setStateDialog(() {
                isSending = false;
                errorText = error == null ? null : messageFor(error);
              });
              focusNodes[0].requestFocus();
            }

            // Funcion que se ejecuta al rellenar los 6 digitos
            void onCodeComplete() async {
              final code = controllers.map((c) => c.text).join();
              if (code.length != 6) return; // Se comprueba que los 6 digitos esten rellenos

              setStateDialog(() { isLoading = true; errorText = null; });

              // Se verifica si el codigo es correcto
              final error = await onVerifyCode(code);

              if (!innerContext.mounted) return;
              setStateDialog(() => isLoading = false);

              if (error == null) { // Si el codigo es correcto, se cierra la modal y se ejecuta la funcion de exito
                Navigator.of(dialogContext).pop();
                onSuccess();
              }
              else { // Si no, se muestra el motivo concreto
                setStateDialog(() => errorText = messageFor(error));
                for (var c in controllers) { 
                  c.clear(); // Se limpian los campos
                } 
                focusNodes[0].requestFocus();
              }
            }

            final displayMessage = customMessage ?? (email != null ? "Código enviado a:\n$email" : "Código enviado");

            return AlertDialog(
              title: const Text("Verificación"),
              contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 10), 
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text( // Mientras se envia el codigo, se muestra el mensaje de enviando, y despues se informa al usuario que se ha enviado
                    isSending ? "Enviando código..." : displayMessage, 
                    textAlign: TextAlign.center
                  ),
                  
                  if (!isSending) ...[ // Si no se esta enviando un codigo, se muestra la opcion de reenviar
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: isLoading ? null : resendCode,
                      child: const Text(
                        "Reenviar código",
                        style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  
                  // Se crea un "cuadrado" para cada uno de los caracteres del codigo
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(6, (index) {
                      return Flexible( 
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2.0),
                          child: TextField(
                            controller: controllers[index],
                            focusNode: focusNodes[index],
                            enabled: !isSending && !isLoading,
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.of(innerContext).textPrimary),
                            textAlign: TextAlign.center,
                            maxLength: 1, // Solo se permite un unico caracter por campo
                            keyboardType: TextInputType.text,
                            decoration: const InputDecoration(
                              counterText: "",
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(vertical: 12)
                            ),
                            onChanged: (value) {
                              if (value.isNotEmpty) {
                                String code = controllers.map((c) => c.text).join();
                                if (code.length == 6){ // En cuanto esten rellenos los 6, se lanza la verificacion
                                  focusNodes[index].unfocus(); 
                                  onCodeComplete();
                                }
                                if (index < 5) { // Se va pasando al siguiente campo automaticamente
                                  focusNodes[index + 1].requestFocus();
                                } 
                              } 
                              else if (index > 0) {
                                focusNodes[index - 1].requestFocus();
                              }
                            },
                          ),
                        ),
                      );
                    }),
                  ),
                  // Si hay un error, se muestra
                  if (errorText != null) ...[
                    const SizedBox(height: 12), 
                    Text(errorText!, style: const TextStyle(color: Colors.red))
                  ],
                ],
              ),
              actions: [ // Si se pulsa cancelar, se cierra la modal
                TextButton(
                  onPressed: isLoading || isSending ? null : () => Navigator.pop(dialogContext), 
                  child: const Text("Cancelar")
                ),
                if (isLoading) // Si se esta cargando, se muestra un spinner de carga
                  const Padding(
                    padding: EdgeInsets.only(right: 16), 
                    child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  ),
              ],
            );
          },
        );
      },
    );
  }
}