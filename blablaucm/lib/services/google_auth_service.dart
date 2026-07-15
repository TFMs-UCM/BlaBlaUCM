import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';

// Servicio para manejar la autenticación con Google Sign-In.

class GoogleAuthService {
  static GoogleSignIn? _instance;

  // Getter para obtener la instancia de GoogleSignIn
  static GoogleSignIn get _signIn {
    _instance ??= GoogleSignIn(
      serverClientId: dotenv.env['GOOGLE_WEB_CLIENT_ID'],
      scopes: ['email', 'profile'],
    );
    return _instance!;
  }

  // Funcion para iniciar el flujo de Google Sign-In 
  static Future<GoogleSignInResult?> signIn() async {
    try {
      // Antes de iniciar sesion se cierra la que hay
      await _signIn.signOut();

      // Inicio del flujo de Google Sign-In
      final account = await _signIn.signIn();
      if (account == null) return null;

      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) return null;

      // Devuelve la informacion del usuario autenticado
      return GoogleSignInResult(
        idToken: idToken,
        email: account.email,
        name: account.displayName ?? '',
        photoUrl: account.photoUrl,
      );
    } 
    catch (_) {
      return null;
    }
  }

  static Future<void> signOut() async {
    await _signIn.signOut();
  }
}

class GoogleSignInResult {
  final String idToken;
  final String email;
  final String name;
  final String? photoUrl;

  const GoogleSignInResult({
    required this.idToken,
    required this.email,
    required this.name,
    this.photoUrl,
  });
}
