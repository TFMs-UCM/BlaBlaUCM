import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Clases para definir los campos personalizados

// Widget que muestra un texto con un mensaje de ayuda opcional
Widget buildLabelWidget(String label, String? tooltipText) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      // Se muestra el texto del label
      Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      if (tooltipText != null) ...[ // SI se le añade el mensaje de ayuda, se muestra con un icono de informacion
        const SizedBox(width: 6),
        Tooltip(
          message: tooltipText,
          triggerMode: TooltipTriggerMode.tap,
          showDuration: const Duration(seconds: 4),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(10),
          child: const Icon(Icons.info_outline, color: Colors.blueGrey, size: 20),
        ),
      ],
    ],
  );
}

// Widget que muestra un campo de texto editable o solo lectura dependiendo de la variable editMode
Widget buildInfoRow({required String label, required String value, TextEditingController? controller, required bool editMode,  
    bool isNumber = false, String? errorText, int? maxLength, String? tooltipText, showLimitChars = false}) {
  
  // Muestra el contenido del label
  Widget labelWidget = buildLabelWidget(label, tooltipText);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: editMode && controller != null // Si se peude editar, hace el contenido editable
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              labelWidget,
              const SizedBox(height: 6),
              TextField(
                controller: controller,
                keyboardType: isNumber ? TextInputType.number : TextInputType.text,
                inputFormatters: isNumber ? [FilteringTextInputFormatter.digitsOnly] : [], // Si es un campo numerico, solo se permiten numeros
                maxLength: maxLength, // Se establece el maximo de caracteres o null si no se dice nada (ilimitado)
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  errorText: errorText, // EL mensaje de error (cuando lo haya) si se ha especificado
                  errorMaxLines: 3, // Permite mostrar hasta 3 lineas de errores para evitar que se corten los mensajes de error largos
                  counterText: showLimitChars && maxLength != null ? null : "",
                ),
              ),
            ],
          )
        : Row( // Si no se puede editar, muestra el valor como texto
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              labelWidget,
              Flexible(
                child: Text(
                  value, // Valor que se muestra cuando no se puede editar
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
  );
}

// Widget que muestra un campo de seleccion con los valores que se le han pasado
Widget buildDropdownRow<T>({required String label, required T? currentValue, required List<T> items, required Function(T?) onChanged, 
    required String Function(T) labelGetter, required bool editMode, String? errorText, String? tooltipText}) {
  
  Widget labelWidget = buildLabelWidget(label, tooltipText);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: editMode 
        ? Column( // Si se puede editar, se muestra un menu desplegable con las opciones
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              labelWidget, // Usa el widget definido anteriormente para mostrar el label con su mensaje de ayuda
              const SizedBox(height: 6),
              DropdownButtonFormField<T>( // Menu desplegable del tipo generico T
                initialValue: currentValue,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  errorText: errorText, // MUestra el texto de error si se ha especificado
                  errorMaxLines: 3, // Permite mostrar hasta 3 lineas de errores
                ),
                items: items.map((item) {
                  return DropdownMenuItem<T>(
                    value: item, // Se asocia a cada item un label
                    child: Text(labelGetter(item)), // Se le pasa tambien la lista de nombres que se deben mostar
                  );
                }).toList(),
                onChanged: onChanged,
              ),
            ],
          )
        : Row( // Si no se puede editar, se muestra el valor seleccionado como texto
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              labelWidget,
              Flexible(
                child: Text(
                  currentValue != null ? labelGetter(currentValue) : "N/A", // Si no hay ningun valor seleccionado, se muestra N/A
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
  );
}

// Widget que muestra un campo de contraseña, con el texto oculto y un boton para hacerlo visible
Widget passwordField(String label, TextEditingController controller, bool obscureText, VoidCallback onToggleVisibility, {String? errorText, String labelText = 'Contraseña', int errorMaxLines = 1}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [ 
        if (label.isNotEmpty)...[ // Si no tiene un label, no se pone ese campo
          Text(
            label, // MUestra el contenido del label
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6)
        ],
        TextField( // Muestra el campo de texto con el boton para cambiar el texto a visible o no
          controller: controller,
          obscureText: obscureText, 
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: true,
            labelText: labelText, // Texto que se muestra antes de escribir en el campo
            contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            suffixIcon: IconButton(
              icon: Icon(
                obscureText ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey,
              ),
              onPressed: onToggleVisibility, // Al pulsar sobre el icono, se cambia la visibilidad
            ),
            errorText: errorText,
            errorMaxLines: errorMaxLines,
          ),
        ),
      ],
    ),
  );
}