import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/screens/helper.dart';
import 'package:blablaucm/screens/custom_form_fields.dart';
import 'package:blablaucm/screens/email_verification.dart';
import 'package:blablaucm/models/enums.dart';

// Pantalla de recuperacion de contraseña

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final ApiService _api = ApiService();

  final _identifierCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  int _step = 1;

  String? _identifierError;
  String? _codeError;
  String? _passwordError;
  String? _confirmPasswordError;

  String _username = '';

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  // Envia el codigo al email del usuario
  Future<void> _sendCode() async {
    final identifier = _identifierCtrl.text.trim();
    if (identifier.isEmpty) {
      setState(() => _identifierError = "Este campo no puede estar vacío");
      return;
    }

    setState(() {
      _isLoading = true;
      _identifierError = null;
    });

    try {
      await EmailVerification.sendVerificationEmail(username: identifier);
      if (!mounted) return;
      setState(() {
        _username = identifier;
        _step = 2;
        _isLoading = false;
      });
    } 
    catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _identifierError = "No se pudo enviar el código. Comprueba que el usuario o email es correcto.";
      });
    }
  }

  // Se reenvia el codigo
  Future<void> _resendCode() async {
    setState(() {
      _isLoading = true;
      _codeError = null;
    });
    _codeCtrl.clear();
    try {
      await EmailVerification.sendVerificationEmail(username: _username);
    } 
    finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Se verifica el codigo y cambia la contraseña
  Future<void> _confirmChange() async {
    final code = _codeCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirmPassword = _confirmPasswordCtrl.text;

    setState(() {
      _codeError = null;
      _passwordError = null;
      _confirmPasswordError = null;
    });

    // Antes de hacer la llamada a la api, se validan los campos
    bool hasError = false;
    if (code.length < 6) {
      setState(() => _codeError = "El código debe tener 6 caracteres");
      hasError = true;
    }
    if (password.isEmpty) {
      setState(() => _passwordError = "La contraseña no puede estar vacía");
      hasError = true;
    } 
    else if (password.length < 6) {
      setState(() => _passwordError = "La contraseña debe tener al menos 6 caracteres");
      hasError = true;
    }
    if (password != confirmPassword) {
      setState(() {
        _passwordError = "Las contraseñas no coinciden";
        _confirmPasswordError = "Las contraseñas no coinciden";
      });
      hasError = true;
    }
    if (hasError) return;

    setState(() => _isLoading = true);

    final endpoint = dotenv.env['VERIFY_CODE_ENDPOINT'] ?? '/users/verify_code/';
    final response = await _api.requestToApi(
      endpoint,
      requireAuthentication: false,
      op: ApiOptions.post,
      body: {
        'username': _username,
        'token': code,
        'password': password,
      },
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (response != null && response['status']?.toLowerCase() == 'ok') {
      showModal(
        context,
        'Tu contraseña se ha actualizado correctamente. Ya puedes iniciar sesión.',
        title: 'Éxito',
        type: AlertType.success,
        backPage: true,
      );
    } 
    else {
      final rawCode = response?['error_code'];
      final errorCode = rawCode != null ? ErrorCode.fromCode(int.tryParse(rawCode.toString()) ?? -1) : ErrorCode.unknownError;

      setState(() {
        if (errorCode == ErrorCode.tokenExpired) {
          _codeError = "El código ha expirado. Solicita uno nuevo.";
        } 
        else if (errorCode == ErrorCode.incorrectToken) {
          _codeError = "Código incorrecto. Inténtalo de nuevo.";
        } 
        else {
          _codeError = "Error al cambiar la contraseña. Inténtalo de nuevo.";
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Recuperar contraseña"),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: _step == 1 ? _buildStep1() : _buildStep2(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Se crea el paso 1, que es introducir el email o nombre de usuario y enviar el codigo
  Widget _buildStep1() {
    return Column(
      children: [
        const Icon(Icons.lock_reset, size: 70, color: AppButtonStyles.primaryColor),
        const SizedBox(height: 16),
        const Text(
          "Introduce tu email o nombre de usuario y te enviaremos un código para restablecer tu contraseña.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.black54),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _identifierCtrl,
          enabled: !_isLoading,
          maxLength: 60,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: "Email o nombre de usuario",
            border: const OutlineInputBorder(),
            errorText: _identifierError,
            errorMaxLines: 3,
            counterText: "",
          ),
          onChanged: (_) {
            if (_identifierError != null) setState(() => _identifierError = null);
          },
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _sendCode,
            style: AppButtonStyles.primary,
            child: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text("Continuar"),
          ),
        ),
      ],
    );
  }

  // Se crea el paso 2, que es verificar el código y cambiar la contraseña
  Widget _buildStep2() {
    return Column(
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 70, color: AppButtonStyles.primaryColor),
        const SizedBox(height: 16),
        Text(
          "Hemos enviado un código a tu email. Introdúcelo junto con tu nueva contraseña.",
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _isLoading ? null : _resendCode,
          child: const Text(
            "Reenviar código",
            style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 24),
        // Campo del codigo
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Código de verificación",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _codeCtrl,
                enabled: !_isLoading,
                maxLength: 6,
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  errorText: _codeError,
                  errorMaxLines: 3,
                  counterText: "",
                ),
                onChanged: (_) {
                  if (_codeError != null) setState(() => _codeError = null);
                },
              ),
            ],
          ),
        ),
        // Campo de nueva contraseña
        passwordField(
          "Nueva contraseña",
          _passwordCtrl,
          _obscurePassword,
          () => setState(() => _obscurePassword = !_obscurePassword),
          errorText: _passwordError,
        ),
        // Campo de confirmacion de contraseña
        passwordField(
          "Repetir contraseña",
          _confirmPasswordCtrl,
          _obscureConfirmPassword,
          () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
          errorText: _confirmPasswordError,
          labelText: "Repetir contraseña",
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _confirmChange,
            style: AppButtonStyles.primary,
            child: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text("Confirmar"),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : () => setState(() {
              _step = 1;
              _codeCtrl.clear();
              _passwordCtrl.clear();
              _confirmPasswordCtrl.clear();
              _codeError = null;
              _passwordError = null;
              _confirmPasswordError = null;
            }),
            style: AppButtonStyles.secondary,
            child: const Text("Volver"),
          ),
        ),
      ],
    );
  }
}
