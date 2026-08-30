import 'package:flutter/material.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/services/api_service.dart';
import 'package:blablaucm/screens/custom_form_fields.dart';
import 'package:blablaucm/screens/helper.dart';
import 'package:blablaucm/screens/home.dart';

// Pantalla para completar el registro una vez se crea una cuenta usando Google

class GoogleRegisterScreen extends StatefulWidget {
  final String idToken;
  final String email;
  final String name;

  const GoogleRegisterScreen({
    super.key,
    required this.idToken,
    required this.email,
    required this.name,
  });

  @override
  State<GoogleRegisterScreen> createState() => _GoogleRegisterScreenState();
}

class _GoogleRegisterScreenState extends State<GoogleRegisterScreen> {
  final _apiService = ApiService();
  final _usernameCtrl = TextEditingController();
  final _surname2Ctrl = TextEditingController();
  UsersType? _selectedRol;
  bool _isSaving = false;
  String? _usernameError;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _surname2Ctrl.dispose();
    super.dispose();
  }

  // Función para completar el registro, valida los campos y llama ala api para crear la cuenta
  Future<void> _completeRegister() async {
    final username = _usernameCtrl.text.trim();

    setState(() => _usernameError = null);

    // Se valida que el nombre de usuario y el rol no esten vacios
    if (username.isEmpty) {
      setState(() => _usernameError = 'El nombre de usuario es obligatorio');
      return;
    }
    if (_selectedRol == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes seleccionar el colectivo al que perteneces'), backgroundColor: Colors.red),
      );
      return;
    }

    // Antes de crear la cuenta hay que aceptar los terminos y condiciones
    
    final bool termsAccepted = await showTermsAndConditionsModal(context);

    if (!termsAccepted) return; // Sin aceptar los terminos no se crea la cuenta

    if (!mounted) return;

    setState(() => _isSaving = true);

    try {
      // Se llama a la api para registrar al usuario
      final result = await _apiService.registerWithGoogle(
        idToken: widget.idToken,
        username: username,
        userType: _selectedRol!.name,
        surname2: _surname2Ctrl.text.trim(),
      );

      if (!mounted) return;
      setState(() => _isSaving = false);

      if (result == null) { // Si no se devuelve nada se muestra un mensaje con error de conexion
        _showError('Error de conexión');
        return;
      }

      final code = result['statusCode'] as int?;

      if (code == 200) { // Si se ha registrado correctamente, se avisa y se lleva al menu principal
        showModal(
          context,
          'Tu cuenta ha sido creada correctamente. ¡Bienvenido!',
          title: 'Éxito',
          type: AlertType.success,
          barrierDismissible: false,
          onAccepted: () => Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const HomePage()),
            (_) => false,
          ),
        );
        return;
      }

      final errorMsg = result['error'] as String?;
      if (errorMsg != null) {
        if (errorMsg.contains('usuario')) {
          setState(() => _usernameError = errorMsg);
        } 
        else { // Si hay un error con los datos del usuario se le muestra el error
          _showError(errorMsg);
        }
      } 
      else { // Si es un error distinto, se muestra error generico
        _showError('Error al crear la cuenta');
      }
    } 
    catch (_) { // Si se produce una excepcion, se muestra error de conexion
      if (mounted) {
        setState(() => _isSaving = false);
        _showError('Error de conexión');
      }
    }
  }

  // Funcion para mostrar un mensaje de error en el SnakBar
  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  // FUncion para construir la pantalla
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Completar registro')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Column(
                    children: [ // Se muestran los campos editables que debe rellenar el usuario
                      const Icon(Icons.person_add, size: 70, color: Colors.blue),
                      const SizedBox(height: 8),
                      const Text(
                        'Casi listo — completa tu perfil',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      // EL nombre y el email se extraen de los datos que devuelve Google
                      buildInfoRow(label: 'Nombre', value: widget.name, editMode: false),
                      buildInfoRow(label: 'Correo electrónico', value: widget.email, editMode: false),
                      const Divider(height: 32),
                      // El usuario debe introducir su nombre de usuario
                      buildInfoRow(
                        label: 'Nombre de usuario',
                        value: _usernameCtrl.text,
                        editMode: true,
                        controller: _usernameCtrl,
                        errorText: _usernameError,
                        maxLength: 20,
                      ),
                      buildInfoRow( // Puede añadir su segundo apellido si quiere
                        label: 'Segundo apellido (opcional)',
                        value: _surname2Ctrl.text,
                        editMode: true,
                        controller: _surname2Ctrl,
                        maxLength: 50,
                      ),
                      buildDropdownRow<UsersType>( // Debe espeificar su colectivo
                        label: 'Colectivo al que pertenece',
                        currentValue: _selectedRol,
                        items: UsersType.values.where((u) => u != UsersType.all).toList(),
                        onChanged: (val) => setState(() => _selectedRol = val),
                        labelGetter: (c) => c.label,
                        editMode: true,
                      ),
                      const SizedBox(height: 30),
                      _isSaving
                        ? const Text('Creando cuenta...', style: TextStyle(fontSize: 16))
                        : Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => Navigator.pop(context),
                                  style: AppButtonStyles.secondary,
                                  child: const Text('Cancelar'),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: ElevatedButton( // Se trata de crear la cuenta con los datos introducidos
                                  onPressed: _completeRegister,
                                  style: AppButtonStyles.primary,
                                  child: const Text('Crear cuenta'),
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
