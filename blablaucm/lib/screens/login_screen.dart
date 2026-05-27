import 'package:flutter/material.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/screens/home.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/screens/register_user_screen.dart';
import 'package:blablaucm/screens/custom_form_fields.dart';

// Pantalla de inicio de sesion de la aplicacion

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  // Funcion para construir la pantalla
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              const Text(
                'Iniciar sesión',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32), // Se añaden campos de texto para que el usuario introduzca el usuario y contraseña
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email o usuario',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              // campo de contraseña para poder ocultar la contraseña
              passwordField('', _passwordController, _obscurePassword, () => setState(() => _obscurePassword = !_obscurePassword)),
              const SizedBox(height: 24),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              ElevatedButton( // Boton para iniciar sesion
                onPressed: _isLoading ? null : () => _performLogin(),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Entrar'),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {}, // TODO Implementar el login con google
                icon: const Icon(Icons.login, color: Colors.red),
                label: const Text('Entrar con Google'),
              ),
              const SizedBox(height: 24),
              GestureDetector( // Si se pulsa sobre el texto crear una cuenta, se abre esa pantalla
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RegisterUserScreen(
                        onSave: (userData) {
                          if (userData['email'] != null) {
                            setState(() {
                              _emailController.text = userData['email'];
                            });
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Usuario registrado correctamente"),
                              backgroundColor: Colors.green,
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
                child: const Text(
                  'Crear una cuenta',
                  style: TextStyle(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // Funcion para hacer login, llama a la api con lo datos 
  Future<void> _performLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (dotenv.env.isEmpty) {
        await dotenv.load();
      }
      
      // Se comprueba que los campos no esten vacios
      if (_emailController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
        setState(() {
          _errorMessage = 'Por favor, completa todos los campos';
          _isLoading = false;
        });
        return;
      }

      // Se llama a la api con los datos
      final data = await _apiService.login(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );

      if (data != null) { // El backend ha enviado una respuesta
        if (data['error'] != null) { // Si hay un error, se muestra 
          setState(() {
            _errorMessage = data['error']['message'] ?? 'Error al iniciar sesión';
          });
        } 
        else if (data['requires_2fa'] == true) { // El backend indica que necesita el 2FA para poder acceder
          _show2FADialog(); // Se muestra la modal de 2FA
        } 
        else if (data['user'] != null) { // EL backend ha devuelto los datos del usuario, por lo que se entra en la app
          if (!mounted) return;
          Navigator.pushReplacement( // S epasa a la pantalla de inicio
            context,
            MaterialPageRoute(
              builder: (_) => const HomePage(title: 'BlablaUCM'),
            ),
          );
        }
      } 
      else { // Si hay un error en las credenciales, se muestra
        setState(() {
          _errorMessage = 'Credenciales incorrectas';
        });
      }
    } 
    catch (e) { // Si hay un error en la conexion, se muestra al usuario
      setState(() {
        _errorMessage = 'Error de conexión';
      });
    } 
    finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Funcion para mostrar la modal del 2FA
  void _show2FADialog() {
    List<TextEditingController> controllers = List.generate(6, (_) => TextEditingController());
    List<FocusNode> focusNodes = List.generate(6, (_) => FocusNode()); // Se crean 6 focus nodes ya que hay 6 carcteres en el codigo que se usa
    bool isLoadingDialog = false;
    bool isSending = false;
    String? errorText;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            
            // Funcion para reenviar el codigo
            void resendCode() async {
              setStateDialog(() {
                isSending = true;
                errorText = null;
              });
              for (var c in controllers) { c.clear(); } // Se ponen todas las casillas vacias
              
              // Se vuelve a llamar a la api para que genere un nuevo codigo
              await _apiService.login(
                _emailController.text.trim(),
                _passwordController.text.trim(),
              );
              
              if (!context.mounted) return;
              setStateDialog(() => isSending = false);
              // Se pone el foco en el primer campo
              focusNodes[0].requestFocus();
            }

            // Cuando se rellena el ultimo cuadro, se llama a la api automaticamnete
            void onCodeComplete() async {
              final code = controllers.map((c) => c.text).join();
              if (code.length != 6) return;
              
              setStateDialog(() { isLoadingDialog = true; errorText = null; });
              
              // Se llama a la api con el codigo introducido
              final data = await _apiService.login(
                _emailController.text.trim(),
                _passwordController.text.trim(),
                code: code,
              );
              
              if (!context.mounted) return;
              setStateDialog(() => isLoadingDialog = false);
              
              if (data != null) {
                if (data['user'] != null) { // Si se reciben los datos del usuario, se ha verificado correctamente
                  // Éxito total
                  Navigator.of(context).pop();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const HomePage(title: 'Flutter Demo Home Page'),
                    ),
                  );
                } 
                else if (data['error'] != null) {
                  // Su hay un error, se muestra el mensaje y se borran los campos introducidos
                  setStateDialog(() => errorText = data['error']['message'] ?? "Código incorrecto");
                  for (var c in controllers) {c.clear();}
                  focusNodes[0].requestFocus();
                } 
                else { // Si la api no devuelve ni error ni los datos
                  setStateDialog(() => errorText = "Respuesta inesperada");
                }
              } 
              else { // Si no devuelve nada, se muestra un error de conexion
                setStateDialog(() => errorText = "Error de conexión");
              }
            }

            return AlertDialog(
              title: const Text("Verificación en 2 pasos"),
              contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isSending ? "Reenviando código..." : "Hemos enviado un código a tu cuenta.",
                    textAlign: TextAlign.center,
                  ),
                  if (!isSending) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: isLoadingDialog ? null : resendCode,
                      child: const Text(
                        "Reenviar código",
                        style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row( // Se crea una "caja" por cada uno de los caracteres del codigo para que el usuario los introduzca
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(6, (index) {
                      return Flexible(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2.0),
                          child: TextField(
                            controller: controllers[index],
                            focusNode: focusNodes[index],
                            enabled: !isSending && !isLoadingDialog,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                            maxLength: 1,
                            keyboardType: TextInputType.text,
                            decoration: const InputDecoration(
                              counterText: "",
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(vertical: 12),
                            ),
                            onChanged: (value) {
                              if (value.isNotEmpty) {
                                if (index < 5) {
                                  focusNodes[index + 1].requestFocus();
                                } 
                                else {
                                  focusNodes[index].unfocus();
                                  onCodeComplete();
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
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(errorText!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
              actions: [ // Si pulsa el boton cancelar, se cierra la modal
                TextButton(
                  onPressed: isLoadingDialog || isSending ? null : () => Navigator.pop(context),
                  child: const Text("Cancelar"),
                ),
                if (isLoadingDialog)
                  const Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: SizedBox(
                        height: 16, 
                        width: 16, 
                        child: CircularProgressIndicator(strokeWidth: 2)
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}