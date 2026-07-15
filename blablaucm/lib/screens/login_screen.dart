import 'package:flutter/material.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/services/google_auth_service.dart';
import 'package:blablaucm/screens/home.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/screens/register_user_screen.dart';
import 'package:blablaucm/screens/google_register_screen.dart';
import 'package:blablaucm/screens/forgot_password_screen.dart';
import 'package:blablaucm/screens/custom_form_fields.dart';
import 'package:blablaucm/screens/email_verification.dart';
import 'package:blablaucm/screens/helper.dart';

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
  bool _isGoogleLoading = false;
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
                style: AppButtonStyles.primary,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Entrar'),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon( // Opcion para iniciar sesion con Google
                onPressed: _isGoogleLoading ? null : _loginWithGoogle,
                style: AppButtonStyles.secondary,
                icon: _isGoogleLoading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.login, color: Colors.red),
                label: const Text('Entrar con Google'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon( // Opcion para registrarse con Google
                onPressed: _isGoogleLoading ? null : _registerWithGoogle,
                style: AppButtonStyles.secondary,
                icon: const Icon(Icons.person_add, color: Colors.red),
                label: const Text('Registrarse con Google'),
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
              const SizedBox(height: 12),
              GestureDetector( // Si se pulsa sobre el texto olvidé mi contraseña, se abre esa pantalla
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ForgotPasswordScreen(),
                    ),
                  );
                },
                child: const Text(
                  'He olvidado mi contraseña',
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
          _show2FADialog(_emailController.text.trim(), _passwordController.text.trim()); // Se muestra la modal de 2FA
        } 
        else if (data['user'] != null) { // EL backend ha devuelto los datos del usuario, por lo que se entra en la app
          if (!mounted) return;
          Navigator.pushReplacement( // S epasa a la pantalla de inicio
            context,
            MaterialPageRoute(
              builder: (_) => const HomePage(),
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

  // Funcion para iniciar sesion con Google
  Future<void> _loginWithGoogle() async {
    setState(() { _isGoogleLoading = true; _errorMessage = null; });
    try {
      // Se intenta iniciar sesion con Google
      final googleResult = await GoogleAuthService.signIn();
      if (googleResult == null) return; // El usuario cancelo

      final data = await _apiService.loginWithGoogle(googleResult.idToken);

      if (!mounted) return;

      final code = data?['statusCode'] as int?;
      if (code == 200) { // Se ha podido obtener el usuario, por lo que se lleva al usuario a la pantalla de Home
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
        return;
      }
      if (code == 404) { // No tiene cuenta con ese email, por lo que se le avisa
        setState(() => _errorMessage = 'No tienes cuenta con este email de Google. Usa "Registrarse con Google".');
        return;
      }
      setState(() => _errorMessage = data?['error'] as String? ?? 'Error al iniciar sesión con Google');
    } 
    catch (_) { // Si hay una excepcion, se muestra un error de conexion
      if (mounted) setState(() => _errorMessage = 'Error de conexión');
    } 
    finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  // Funcion para realizar el registro del usuario en la app usando Google
  Future<void> _registerWithGoogle() async {
    setState(() { _isGoogleLoading = true; _errorMessage = null; });
    try {
      final googleResult = await GoogleAuthService.signIn();
      if (googleResult == null) return; // El usuario cancelo

      if (!mounted) return;
      Navigator.push( // Se le redigire a la pagina para que se registre con Google
        context,
        MaterialPageRoute(
          builder: (_) => GoogleRegisterScreen(
            idToken: googleResult.idToken,
            email: googleResult.email,
            name: googleResult.name,
          ),
        ),
      );
    } 
    catch (_) { // Si hay una excepcion, se muestra un error de conexion
      if (mounted){
        setState(() => _errorMessage = 'Error de conexión');
      }
    } 
    finally {
      if (mounted){
        setState(() => _isGoogleLoading = false);
      }
    }
  }

  // Funcion para mostrar la modal del 2FA
  void _show2FADialog(String username, String password) {
    EmailVerification.showVerificationDialog(
      context: context,
      customMessage: "Para iniciar sesión, introduce el código que hemos enviado a tu email",
      skipInitialSend: true, // El backend ya envió el email durante el primer intento de login
      onSendCode: () async {
        // Al reenviar hace un nuevo login sin code para que el backend genere y envíe otro código
        await _apiService.login(username, password);
      },
      onVerifyCode: (code) async {
        // Se hace el login con el code para verificar el 2FA y obtener los tokens JWT
        final data = await _apiService.login(username, password, code: code);
        return data != null && data['user'] != null;
      },
      // Si la verificacion es correcta, se muestra al usuario un mensaje de exito
      onSuccess: () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const HomePage(),
          ),
        );
      },
    );
  }
}