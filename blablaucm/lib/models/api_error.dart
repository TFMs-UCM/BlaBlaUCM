import 'package:blablaucm/models/enums.dart';

//Clase para representar un error devuelto por la API.

class ApiError {
  // Codigo de error del catalogo de la API. unknownError si no se reconoce.
  final ErrorCode code;

  // Texto para enseñar al usuario.
  final String message;

  // Errores por campo, cuando el fallo es de validacion:
  final Map<String, List<String>> fields;

  const ApiError({required this.code, required this.message, this.fields = const {}});

  // Devuelve el error contenido en una respuesta, o null si no lo es.

  static ApiError? from(Map<String, dynamic>? response) {
    if (response == null) return null;
    if (!_looksLikeError(response)) return null;

    return ApiError(
      code: _codeOf(response),
      message: _messageOf(response),
      fields: _fieldsOf(response),
    );
  }

  // Error generico para cuando la peticion ni siquiera llego a responder.
  static const ApiError connection = ApiError(
    code: ErrorCode.unknownError,
    message: 'No se ha podido conectar. Comprueba tu conexión e inténtalo de nuevo.',
  );

  // La API limita el ritmo de peticiones en el login, el envio de codigos y la
  // validacion de pasajeros. 
  bool get isTooManyRequests => code == ErrorCode.tooManyRequests;

  // El mensaje de un campo concreto, si el fallo fue de validacion.
  String? fieldMessage(String field) {
    final messages = fields[field];
    if (messages == null || messages.isEmpty){
      return null;
    }
    return messages.first;
  }

  // Si la respuesta parece un error, devuelve true. Se considera error si:
  // Trae un string y este es error, trae un error_code, trae un error, o solo tiene un detail.
  static bool _looksLikeError(Map<String, dynamic> response) {
    final status = response['status'];
    if (status is String) {
      return status.toLowerCase() == 'error';
    }
    if (response['error_code'] != null){
      return true;
    }
    if (response['error'] != null){
       return true;
    }
    if (response.length == 1 && response['detail'] is String){
      return true;
    }
    return false;
  }

  // Devuelve el codigo de error de la respuesta, o unknownError si no se reconoce.
  static ErrorCode _codeOf(Map<String, dynamic> response) {
    final raw = response['error_code'] ?? _nested(response)?['code'];
    if (raw == null){
      return ErrorCode.unknownError;
    }
    final parsed = int.tryParse(raw.toString());
    return parsed == null ? ErrorCode.unknownError : ErrorCode.fromCode(parsed);
  }

  // Devuelve el mensaje de error de la respuesta, o un mensaje por defecto si no se encuentra.
  static String _messageOf(Map<String, dynamic> response) {
    final candidates = <dynamic>[
      response['message'],
      _nested(response)?['message'],
      response['error'] is String ? response['error'] : null,
      response['detail'],
    ];

    for (final candidate in candidates) {
      if (candidate is String && candidate.trim().isNotEmpty){
        return candidate;
      }
    }

    // Si no hay mensaje general, sirve el del primer campo que falle
    for (final messages in _fieldsOf(response).values) {
      if (messages.isNotEmpty){
        return messages.first;
      }
    }

    return 'Ha ocurrido un error inesperado. Inténtalo de nuevo.';
  }

  static Map<String, List<String>> _fieldsOf(Map<String, dynamic> response) {
    final raw = response['fields'];
    if (raw is! Map) return const {};

    final result = <String, List<String>>{};
    raw.forEach((key, value) {
      if (value is List) {
        result[key.toString()] = value.map((e) => e.toString()).toList();
      } 
      else if (value != null) {
        result[key.toString()] = [value.toString()];
      }
    });
    return result;
  }

  static Map<String, dynamic>? _nested(Map<String, dynamic> response) {
    final error = response['error'];
    return error is Map<String, dynamic> ? error : null;
  }

  // Para mostrar el error, se muestra el nombre del codigo y el mensaje
  @override
  String toString() => 'ApiError(${code.name}: $message)';
}
