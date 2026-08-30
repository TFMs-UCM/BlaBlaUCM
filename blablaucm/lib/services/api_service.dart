import 'dart:convert';
import 'package:blablaucm/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:blablaucm/providers/storage_provider.dart';
import 'package:blablaucm/main.dart';
import 'package:blablaucm/screens/login_screen.dart';
import 'dart:io';
import 'dart:typed_data';

// Clase que engloba las funciones para la realizacion de peticiones a la api

class ApiService {
  // URL base de la api, todos los endpoints deberan empezar por esta url
  static String get baseUrl => dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:8000/api/v1';
  // Endpoint para ralizar el login
  static String get loginEndpoint => dotenv.env['LOGIN_ENDPOINT'] ?? '/login/';
  // Endpoint para solicitar un nuevo token
  static String get refreshEndpoint => dotenv.env['REFRESH_ENDPOINT'] ?? '/refresh/';

  final SecureStorageService _storage = SecureStorageService();

  // Evita redirigir a login varias veces si caducan varias peticiones a la vez
  static bool _sessionExpiredHandled = false;

  // Guarda la sesion (tokens e id de usuario) que devuelve la api
  Future<bool> saveSession(Map<String, dynamic>? data) async {
    if (data == null) return false;

    final access = data['access'];
    final refresh = data['refresh'];
    final user = data['user'];

    // Se exigen las tres cosas, una respuesta a medias no es una sesion valida
    if (access == null || refresh == null || user == null || user['id'] == null) {
      return false;
    }

    await _storage.saveElement('access_token', access);
    await _storage.saveElement('refresh_token', refresh);
    await _storage.saveElement('user_id', user['id']);
    _sessionExpiredHandled = false; // Nueva sesion valida
    return true;
  }

  // Funcion para realizar el login, devuelve un mapa con los datos del usuario y los tokens
  Future<Map<String, dynamic>?> login(String username, String password, {String? code}) async {
    final url = Uri.parse(baseUrl + loginEndpoint);
    
    // Construimos el body con los datos de inicio de sesion
    final Map<String, dynamic> bodyData = {
      'username': username,
      'password': password,
    };

    if (code != null && code.isNotEmpty) {
      bodyData['code'] = code; // Añade el codigo si se proporciona (el codigo es opcional, solo si el usuario tiene activado el 2FA)
    }

    // Se convierte el body a JSON para que se pueda enviar bien
    String jsonBody = jsonEncode(bodyData);

    // Se realiza la peticion a la api
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonBody,
    );

    if (response.statusCode == 200) { // Si la api responde con un codigo 200, es que se ha iniciado sesion correctamente
      final data = jsonDecode(response.body); // Se decodifica la respuesta

      // Se guarda la informacion del usuario y los tokens para futuras peticiones
      await saveSession(data);

      return data;
    } 
    else {
      // Si hay error se extrae el JSON del error para leer el mensaje
      if (response.body.isNotEmpty) {
        try {
          Map<String, dynamic>? json = jsonDecode(response.body);
          if (json?['error'] != null){
            return json; // Si hay un mensaje de error se devuelve el JSON con el mensaje de error
          }
          else{
            return null;
          }
        } 
        catch (_) {} // Se captura para devolver luego null
      }
      return null; // Si no hay mensaje de error se devuelve null
    }
  }

  // Funcion para realizar el login con Google, envia el id_token al backend y guarda los JWT si el usuario ya existe
  Future<Map<String, dynamic>?> loginWithGoogle(String idToken) async {
    // Se construye la url
    final endpoint = dotenv.env['GOOGLE_AUTH_LOGIN_ENDPOINT'] ?? '/auth/google/login/';
    final url = Uri.parse(baseUrl + endpoint);
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'id_token': idToken}),
    );
    if (response.body.isEmpty) return null;
    final data = jsonDecode(response.body);
    // Si la respuesta es correcta, se guardan los tokens y el id del usuario
    if (response.statusCode == 200) {
      await saveSession(data);
    }
    return {'statusCode': response.statusCode, ...data};
  }

  // Funcion para realizar el registro con Google
  Future<Map<String, dynamic>?> registerWithGoogle({required String idToken, required String username, required String userType, String? surname2}) async {
    // Se construye la url
    final endpoint = dotenv.env['GOOGLE_AUTH_REGISTER_ENDPOINT'] ?? '/auth/google/register/';
    final url = Uri.parse(baseUrl + endpoint);
    // Se envian los datos del usuario junto con el token_id para validarlo y crear al usuario
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'id_token': idToken,
        'username': username,
        'user_type': userType,
        if (surname2 != null && surname2.isNotEmpty) 'surname2': surname2,
      }),
    );
    if (response.body.isEmpty) return null;
    final data = jsonDecode(response.body);
    // Si la respuesta es correcta, se guardan los tokens y el id del usuario
    if (response.statusCode == 200) {
      await saveSession(data);
    }
    return {'statusCode': response.statusCode, ...data};
  }

  // Funcion general para ralizar cualquier peticion a la api, se le pasa el endpoint, si requiere autenticacion, los queryparams, el metodo (get, patch...) y el body
  Future<Map<String, dynamic>?> requestToApi(String endpoint, {bool requireAuthentication = true, Map<String, String>? queryParams, ApiOptions op = ApiOptions.get, Map<String, dynamic>? body}) async {
    // Se construye la url completa con la url base, si la url que se le pasa ya tiene http es porque no es necesario añadir la url base
    final fullUrl = endpoint.startsWith('http') ? endpoint : "$baseUrl$endpoint";
    // Se le añade a la url los queryparams si se le han pasado
    final url = Uri.parse(fullUrl).replace(queryParameters: queryParams?.map((key, value) => MapEntry(key, value)));

    String? accessToken = await _storage.getElement("access_token");

    // Funcion interna para hacer la solicitud con el token actual
    Future<http.Response> makeRequest() {
      final headers = <String, String>{};
      // Se codifica el body a un JSON si lo tiene
      final jsonBody = body != null && body.isNotEmpty ? jsonEncode(body) : null;
      
      // Si tiene body, se añade el header para que se peuda interpretar bien
      if(jsonBody != null){
        headers['Content-Type'] = 'application/json';
      }
      if (requireAuthentication) { // Si necesita autenticacion, se añade el token a los headers
        headers['Authorization'] = 'Bearer $accessToken';
      }
      // Se realiza la peticion segun el metodo que se le haya especificado
      switch (op) {
        case ApiOptions.get:
          return http.get(
            url,
            headers: headers,
          );
        case ApiOptions.post:
          return http.post(
            url,
            headers: headers,
            body: jsonBody,
          );
          case ApiOptions.patch:
            return http.patch(
              url,
              headers: headers,
              body: jsonBody,
            );
          case ApiOptions.delete:
            return http.delete(
              url,
              headers: headers,
            );
        default: // Por defecto es un get
          return http.get(
            url,
            headers: headers,
          );
      }
    }
    
    // Se realiza la peticion
    http.Response response = await makeRequest();

    if (response.statusCode == 401) { // SI da un error 401 (unautorized) es porque el token ha expirado, se solicita un nuevo token y se vuelve a hacer la peticion
      final refreshed = await requestNewToken();
      if (refreshed) {
        response = await makeRequest();
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) { // Si es un codigo entre 200 y 300 es que ha ido bien
      if (response.body.isEmpty){ 
        return {}; // SI no hay respuesta, se devuelve un mapa vacio
      }
      // Si no, se decodifica el JSON de la respuesta y se devuelve
      return jsonDecode(response.body);
    } 
    else { // Si es otro codifo es que hay un error
      if (response.body.isNotEmpty) {
        try {
          // Se trata de decodificarlo para extrer el mensaje de error
          Map<String, dynamic>? json = jsonDecode(response.body);
          if (json?['error'] != null || json?['status'] != null){ // SI trae mensaje de error, se devuelve el JSON
            return json;
          }
          else{ // Si no, se devuelve null
            return null;
          }
        } 
        catch (_) {} // Si hay una excepcion, se captura para devolver null
      }
      return null; // Se deveulve null en cualquier otro caso de error
    }
  }

  // Funcion para solicitar un nuevo token, devuelve true si se ha obtenido uno nuevo, o false en caso contrario
  Future <bool> requestNewToken() async {
    // Creacion de la url
    final url = Uri.parse(baseUrl + refreshEndpoint);
    // Se carga el token de refresco
    String? refreshToken = await _storage.getElement("refresh_token");
    // Sin refresh token no hay sesion que renovar
    if (refreshToken == null || refreshToken.isEmpty) {
      await _handleSessionExpired();
      return false;
    }
    // Se codifica el token en un JSON
    String jsonBody = jsonEncode({
      'refresh': refreshToken,
    });
    // Se realiza la peticion a la api
    http.Response response;
    try {
      response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonBody,
      );
    } 
    catch (_) {
      return false;
    }
    if (response.statusCode == 200) { // Si el codigo es 200, se ha realizado correctamente
      final data = jsonDecode(response.body);
      await _storage.saveElement('access_token', data['access']);
      await _storage.saveElement('refresh_token', data['refresh']);
      _sessionExpiredHandled = false; // Hay una sesion valida de nuevo
      return true;
    }
    if (response.statusCode == 401) {
      // El refresh token ya no es valido, ha expirado, revocado... por lo que la sesion se da por terminada
      await _handleSessionExpired();
    }
    return false;
  }

  // Cierra la sesion cuando el refresh token deja de ser valido
  //borra los datos guardados y lleva al usuario a la pantalla de login
  // Se protege con un flag para no navegar varias veces si fallan varias peticiones a la vez
  Future<void> _handleSessionExpired() async {
    if (_sessionExpiredHandled) return;
    _sessionExpiredHandled = true;
    await _storage.deleteAll();
    final navigator = navigatorKey.currentState;
    if (navigator != null) {
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  // Funcion para obtener la imagen de perfil del usuario
  Future <Image?> getProfilePicture(String path) async {
    // Se construye la url 
    String mediaUrl = dotenv.env['PROF_PIC_ENDPOINT'] ?? '/media/';
    final url = Uri.parse("$baseUrl$mediaUrl$path");
    String? accessToken = await _storage.getElement("access_token");

    // Funcion para hacer la solicitud
    Future<http.Response> makeRequest() {
      return http.get(
        url,
        headers: {'Authorization': 'Bearer $accessToken'},
      );
    }

    // Se realiza la peticion
    http.Response response = await makeRequest();

    if (response.statusCode == 401) {
      // Error porque el token ha expirado, por lo que se solicita uni nuevo
      await requestNewToken();
      response = await makeRequest(); // Se vuelve a intentar con el nuevo token
    }

    if (response.statusCode == 200) { // Si el codigo es 200, se ha obtenido la imagen correctamente
      return Image.memory(response.bodyBytes);
    } 
    else {
      return null; // Si hay algun fallo, se devuelve null
    }
  }

  // Funcion para subir la imagen de perfil del usuario
  Future<String?> uploadProfileImage(String userId, {File? file, Uint8List? bytes,}) async {
    // Se construye la url
    String mediaUrl = dotenv.env['UPLOAD_PROF_PIC_ENDPOINT'] ?? '/upload-profile_picture/';
    String usersUrl = dotenv.env['USER_ENDPOINT'] ?? '/users/';
    final uri = Uri.parse("$baseUrl$usersUrl$userId$mediaUrl");

    String? accessToken = await _storage.getElement("access_token");

    // Funcion interna para ahcer la solicitud
    Future<http.StreamedResponse> makeRequest() async {
      final request = http.MultipartRequest("PATCH", uri);
      request.headers['Authorization'] = 'Bearer $accessToken';

      if (bytes != null) { // Si se le pasa la imagen en formsto bytes, se añade al request
        request.files.add(
          http.MultipartFile.fromBytes(
            'profile_picture',
            bytes,
            filename: 'profile.jpg',
          ),
        );
      } 
      else if (file != null) { // SI se le pasa la imagen en formato file, se añade al request
        request.files.add(
          await http.MultipartFile.fromPath(
            'profile_picture',
            file.path,
          ),
        );
      } 
      else { // Si no se le pasa la imagen, se lanza una excepcion
        throw Exception("No se ha subido ninguna imagen");
      }
      return request.send();
    }

    // Se realiza la peticion
    var streamedResponse = await makeRequest();

    if (streamedResponse.statusCode == 401) { // Si da un error 401, es porque el token ha expirado, se solicita un nuevo token y se vuelve a hacer la peticion
      await requestNewToken();
      accessToken = await _storage.getElement("access_token");
      streamedResponse = await makeRequest();
    }

    // Se convierte la respuesta para poder leer la imagen
    final response = await http.Response.fromStream(streamedResponse);

    // Si el codigo no esta entre 200 y 300, es que ha habido un error al subir la imagen, por lo que se lanza una excepcion
    if (response.statusCode < 200 || response.statusCode > 300) {
      throw Exception("Error al subir la imagen");
    }

    // Se ha subido correctamenete, se decodifica la respuesta para obtener el nombre de la imagen
    final data = jsonDecode(response.body);

    return data["name"];
  }
}


