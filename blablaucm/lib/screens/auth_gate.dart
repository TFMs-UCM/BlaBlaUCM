import 'package:flutter/material.dart';
import 'package:blablaucm/providers/storage_provider.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/screens/login_screen.dart';
import 'package:blablaucm/screens/home.dart';

// Pantalla inicial para permitir que el usuario pueda entrar en la app sin ingresar sus credenciales si ya inicio sesion
// De esta forma se evita que el usuario se logee cada vez que abra la app
// Si la sesion no es valida, se redirige al login para que se vuelva a logear

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final SecureStorageService _storage = SecureStorageService();
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    // Checkea el estado de la sesion al iniciar la pantalla
    _checkSession();
  }

  // Comprueba si hay un refresh token guardado y si sigue siendo valido
  Future<void> _checkSession() async {
    final refreshToken = await _storage.getElement('refresh_token');

    bool isLoggedIn = false;
    // Si hay un refresh token, se intenta solicitar un nuevo access token
    if (refreshToken != null && refreshToken.isNotEmpty) {
      isLoggedIn = await _apiService.requestNewToken();
    }

    // Si no se ha podido iniciar sesion, se limpian los tokens caducados o invalidos
    if (!isLoggedIn) {
      await _storage.deleteAll(); // Se limpian tokens caducados o invalidos
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute( // Si esta logeado, se va a Home, si no se va a la pantalla de login
        builder: (_) => isLoggedIn ? const HomePage() : const LoginScreen(),
      ),
    );
  }

  // Funcion para construir la pantalla
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
