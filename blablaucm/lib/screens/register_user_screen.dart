import 'package:flutter/material.dart';
import 'package:blablaucm/models/api_error.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/screens/custom_form_fields.dart';
import 'package:blablaucm/screens/email_verification.dart';
import 'package:blablaucm/screens/helper.dart';
import 'package:blablaucm/screens/home.dart';
// Pantalla que muestra el formulario para el registro de un nuevo usuario

class RegisterUserScreen extends StatefulWidget {
  final Function(Map<String, dynamic>)? onSave;

  const RegisterUserScreen({
    super.key,
    this.onSave,
  });

  @override
  State<RegisterUserScreen> createState() => _RegisterUserScreenState();
}

class _RegisterUserScreenState extends State<RegisterUserScreen> {
  static final ApiService api = ApiService();
  final usernameCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final confirmPasswordCtrl = TextEditingController();
  final firstNameCtrl = TextEditingController();
  final lastName1Ctrl = TextEditingController();
  final lastName2Ctrl = TextEditingController();
  final emailCtrl = TextEditingController();

  UsersType? selectedRol;
  bool isSaving = false;
  // Variables para mostrar los errores
  String? _usernameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;
  
  // Variables para controlar la visibilidad de las contraseñas
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Indica si la api ha dejado la sesion iniciada al validar la cuenta
  bool _sessionStarted = false;

  // Funcion para mostar los errores como un mensaje en la parte de abajo de la pantalla
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  // Funcion para mostrar la ventana de verificacion
  void _showVerificationCodeDialog(String email, String username, String password) {
    EmailVerification.showVerificationDialog(
      context: context,
      email: email,
      customMessage: "Para terminar el proceso, introduce el código que hemos enviado a:\n$email",
      onSendCode: () => EmailVerification.sendVerificationEmail(username: username),
      // Se guarda si el usuario ha entrado en la app tras validar la cuenta
      onVerifyCode: (code) async {
        final result = await EmailVerification.verifyRegistration(
          username: username,
          code: code,
        );
        _sessionStarted = result.sessionStarted;
        return result.error;
      },
      // Si la verificacion es correcta, se muestra al usuario un mensaje de exito
      onSuccess: () async {
        if (_sessionStarted) {
          _showAccountCreated(loggedIn: true);
          return;
        }

        // Si el servidor no devuelve la sesion, se inicia con las credenciales creadas, mientras se inicia sesion
        // se muestra mensaje informando que se esta iniciando sesion
        showLoadingModal(context, message: 'Iniciando sesión...');

        Map<String, dynamic>? data;
        try {
          data = await api.login(username, password);
        }
        catch (_) {
          data = null;
        }

        if (!mounted) return;

        closeLoadingModal(context);
        _showAccountCreated(loggedIn: data != null && data['user'] != null);
      },
    );
  }

  // Funcion para mostrar el mensaje de cuentra creada, si hay sesion se entra en la app, si no, se vuelve a
  // la pantalla de inicio de sesion para que el usuario entre a mano
  void _showAccountCreated({required bool loggedIn}) {
    showModal(
      context,
      loggedIn
          ? 'Tu cuenta ha sido creada correctamente. ¡Bienvenido!'
          : 'Tu cuenta ha sido creada correctamente. Inicia sesión para continuar.',
      title: 'Éxito',
      type: AlertType.success,
      barrierDismissible: false,
      backPage: !loggedIn,
      onAccepted: loggedIn
          ? () => Navigator.pushAndRemoveUntil( // Se entra en la app y se limpian las pantallas de registro y login
                context,
                MaterialPageRoute(builder: (_) => const HomePage()),
                (_) => false,
              )
          : null,
    );
  }

  // Funcion para crear la cuenta del usuario
  Future<void> _createAccount() async {
    final username = usernameCtrl.text.trim();
    final firstName = firstNameCtrl.text.trim();
    final lastName1 = lastName1Ctrl.text.trim();
    final lastName2 = lastName2Ctrl.text.trim(); // Opcional
    final email = emailCtrl.text.trim();
    final password = passwordCtrl.text;
    final confirmPassword = confirmPasswordCtrl.text;

    setState(() {
      _usernameError = null;
      _emailError = null;
      _passwordError = null;
      _confirmPasswordError = null;
    });

    // Validaciones de los campos
    bool hasError = false;
    if (username.isEmpty) {
      setState(() { _usernameError = "El nombre de usuario es obligatorio."; });
      hasError = true;
    }
    if (firstName.isEmpty) {
      _showError("El nombre es obligatorio.");
      hasError = true;
    }
    if (lastName1.isEmpty) {
      _showError("El primer apellido es obligatorio.");
      hasError = true;
    }
    if (email.isEmpty) {
      setState(() { _emailError = "El correo electrónico es obligatorio."; });
      hasError = true;
    }
    if (!email.contains('@')) {
      setState(() { _emailError = "Introduce un correo electrónico válido."; });
      hasError = true;
    }
    if (password.isEmpty) {
      setState(() { _passwordError = "La contraseña es obligatoria."; });
      hasError = true;
    }
    if (selectedRol == null) {
      _showError("Debes seleccionar el colectivo al que perteneces.");
      hasError = true;
    }
    if(password.length < 6) { // Se pone un mininmo de caracteres por seguridad
      setState(() { _passwordError = "La contraseña debe tener al menos 6 caracteres."; });
      hasError = true;
    }
    if (password != confirmPassword) {
      setState(() {
        _passwordError = "Las contraseñas no coinciden.";
        _confirmPasswordError = "Las contraseñas no coinciden.";
      });
      hasError = true;
    }
    if (hasError) return; // Si hay cualqueir error no se crea la cuenta, se muestra el error

    // Mostrar modal de confirmación
    final bool confirmed = await showConfirmationModal(
      context,
      title: 'Confirmar registro',
      message: '¿Estás seguro de que quieres crear esta cuenta?',
      confirmText: 'Aceptar',
      cancelText: 'Cancelar',
    );

    if (!confirmed) return; // Si el usuario no confirma, se cancela el proceso

    if (!mounted) return;

    // Antes de crear la cuenta hay que aceptar los terminos y condiciones
    final bool termsAccepted = await showTermsAndConditionsModal(context);

    if (!termsAccepted) return; // Sin aceptar los terminos no se crea la cuenta

    setState(() => isSaving = true);

    // Se crea en endpoint y se rellenan los datos a enviar a a la api
    final endpoint = dotenv.env['REGISTER_ENDPOINT'] ?? '/register/';
    final body = {
      'username': username,
      'name': firstName,
      'surname1': lastName1,
      'surname2': lastName2,
      'email': email,
      'password': password,
      'password_confirm': confirmPassword,
      'user_type': selectedRol?.name,
    };

    try {
      // Se realiza la peticion a la api
      final response = await api.requestToApi(
        endpoint,
        requireAuthentication: false,
        op: ApiOptions.post,
        body: body,
      );

      setState(() => isSaving = false);

      if (response == null) { // Si no se recibe respuesta, se meustra un error de conexion
        _showError('Error de conexión o respuesta inesperada.');
        return;
      }

      final error = ApiError.from(response);
      if (error != null) { // Si la api devuelve un error, se muestra y no se crea la cuenta
        final message = error.message;

        setState(() { // Dependiendo del error, se muestra un mensaje u otro
          switch (error.code) {
            case ErrorCode.passwordMismatch:
              _showError(message);
              break;
            case ErrorCode.usernameAlreadyExists:
              _usernameError = message;
              break;
            case ErrorCode.emailAlreadyExists:
              _emailError = message;
              break;
            case ErrorCode.validationError:
            case ErrorCode.missingRequiredField:
              _usernameError = error.fieldMessage('username') ?? _usernameError;
              _emailError = error.fieldMessage('email') ?? _emailError;
              _passwordError = error.fieldMessage('password') ?? _passwordError;
              _confirmPasswordError = error.fieldMessage('password_confirm') ?? _confirmPasswordError;
              if (_usernameError == null && _emailError == null && _passwordError == null && _confirmPasswordError == null) {
                _showError(message);
              }
              break;
            default: // Si el codigo no esta recogido, se muestra solo el mensaje de error
              _showError(message);
          }
        });
        return;
      }
      
      // Si todo va bien, se procede a enviar el email de verificacion
      if (widget.onSave != null) {
        widget.onSave!(response);
      }
      // Se llama a la funcion para verificar el codigo enviado al email
      _showVerificationCodeDialog(email, username, password);
    } 
    catch (e) { // Si hay una excepcion, se informa al usuario de que ha habido un error
      setState(() => isSaving = false);
      _showError('Error al registrar usuario.');
    }
  }

  // Funcion para construir la pantalla
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Registro de Usuario"),
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
                  child: Column(
                    children: [
                      const Icon(
                        Icons.person_add,
                        size: 70,
                        color: Colors.blue,
                      ),
                      const SizedBox(height: 20),
                      // Se muestra el campo de nombre de usuario
                      buildInfoRow(
                        label: "Nombre de usuario",
                        value: usernameCtrl.text, 
                        editMode: true, 
                        controller: usernameCtrl, 
                        errorText: _usernameError, 
                        maxLength: 20
                      ),
                      // Se muestra el campo de nombre
                      buildInfoRow(
                        label: "Nombre", 
                        value: firstNameCtrl.text, 
                        editMode: true,
                        controller: firstNameCtrl, 
                        maxLength: 50
                      ),
                      // Campo del primer apellido
                      buildInfoRow(
                        label: "Primer apellido", 
                        value: lastName1Ctrl.text, 
                        editMode: true,
                        controller: lastName1Ctrl, 
                        maxLength: 50
                      ),
                      // Campo del segundo apellido
                      buildInfoRow(
                        label: "Segundo apellido", 
                        value: lastName2Ctrl.text, 
                        editMode: true,
                        controller: lastName2Ctrl, 
                        maxLength: 50
                      ),
                      // Campo del email
                      buildInfoRow(
                        label: "Correo electrónico", 
                        value: emailCtrl.text, 
                        editMode: true,
                        controller: emailCtrl, 
                        errorText: _emailError, 
                        maxLength: 60
                      ),
                      // Campo de la contraseña
                      passwordField(
                        "Contraseña", 
                        passwordCtrl,
                        _obscurePassword, 
                        () => setState(() => _obscurePassword = !_obscurePassword),
                        errorText: _passwordError
                      ),
                      // Campo de la confirmacion de la contraseña
                      passwordField(
                        "Confirmar contraseña", 
                        confirmPasswordCtrl, 
                        _obscureConfirmPassword, 
                        () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                        errorText: _confirmPasswordError
                      ),
                      // Campo del colectivo que tiene el usuario
                      buildDropdownRow<UsersType>(
                        label: "Colectivo al que pertenece",
                        currentValue: selectedRol,
                        items: UsersType.values.where((u) => u != UsersType.all).toList(), // Se evita que pueda poner all
                        onChanged: (val) => setState(() => selectedRol = val),
                        labelGetter: (c) => c.label,
                        editMode: true,
                      ),

                      const SizedBox(height: 30),
                      isSaving // Si se esta guardando, se muestra un mensjae informativo, si no se muestran los botones crear y cancelar
                        ? const Text("Creando usuario...", style: TextStyle(fontSize: 16))
                          : Row(
                            children: [
                              Expanded( // Boton de cancelar, que cierra la pantalla
                                child: ElevatedButton(
                                  onPressed: () => Navigator.pop(context),
                                  style: AppButtonStyles.secondary,
                                  child: const Text("Cancelar"),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded( // Boton de crear, para crear la cuenta del usuario
                                child: ElevatedButton(
                                  onPressed: _createAccount,
                                  style: AppButtonStyles.primary,
                                  child: const Text("Crear"),
                                ),
                              ),
                            ],
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}