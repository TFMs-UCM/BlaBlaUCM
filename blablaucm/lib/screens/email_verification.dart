import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/models/enums.dart';

// Clase para unificar la logica de la verificacion del 2FA

class EmailVerification {
  static final ApiService _api = ApiService();

  // Funcion para solicitar a la api el codigo de verificacion
  static Future<void> sendVerificationEmail({required String username, String? email}) async {
    // Se construye en endpoint
    final endpoint = dotenv.env['VERIFICATION_EMAIL_ENDPOINT'] ?? '/users/verify_email/';

    final Map<String, String> body = {'username': username};

    // Si se añade el email, se añade al body
    if (email != null) {
      body['email'] = email;
    }

    // Se realiza la peticion a la api
    await _api.requestToApi(
      endpoint, 
      requireAuthentication: false, 
      body:body,
      op: ApiOptions.post
    );
  }

  // Funcion para verificar el codigo
  static Future<bool> verifyCode({required String username, required String code, String? email, String? password, bool validate = false}) async {
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

    // Se realiza la peticion a la api
    final response = await _api.requestToApi(
      endpoint,
      body: body,
      requireAuthentication: false,
      op: ApiOptions.post,
    );
    
    return response != null && response['status']?.toLowerCase() == 'ok';
  }

  // Modal para introduicir el codigo de verificacion de 6 digitos
  static void showVerificationDialog({required BuildContext context, String? email, required Future<void> Function() onSendCode,
      required Future<bool> Function(String code) onVerifyCode, required VoidCallback onSuccess, String? customMessage, bool skipInitialSend = false}) {
    List<TextEditingController> controllers = List.generate(6, (_) => TextEditingController());
    List<FocusNode> focusNodes = List.generate(6, (_) => FocusNode()); // Se crea un Focus node para cada uno de los caracteres
    bool isLoading = false;
    bool isSending = !skipInitialSend;
    bool hasSent = skipInitialSend;
    String? errorText;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (innerContext, setStateDialog) {
            
            if (!hasSent) { // Se envia el codigo al abrir la modal
              hasSent = true;
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                await onSendCode();
                if (!innerContext.mounted) return;
                setStateDialog(() => isSending = false);
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
              
              await onSendCode();
              
              if (!innerContext.mounted) return;
              setStateDialog(() => isSending = false);
              focusNodes[0].requestFocus();
            }

            // Funcion que se ejecuta al rellenar los 6 digitos
            void onCodeComplete() async {
              final code = controllers.map((c) => c.text).join();
              if (code.length != 6) return; // Se comprueba que los 6 digitos esten rellenos

              setStateDialog(() { isLoading = true; errorText = null; });
              
              // Se verifica si el codigo es correcto
              final isSuccess = await onVerifyCode(code);
              
              if (!innerContext.mounted) return;
              setStateDialog(() => isLoading = false);
              
              if (isSuccess) { // Si el codigo es correcto, se cierra la modal y se ejecuta la funcion de exito
                Navigator.of(dialogContext).pop(); 
                onSuccess(); 
              } 
              else { // Si el codigo es incorrecto, se muestra un mensaje de error
                setStateDialog(() => errorText = "Código incorrecto");
                for (var c in controllers) { c.clear(); } // Se limpian los campos
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
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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