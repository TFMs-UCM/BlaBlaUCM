
// Enum para las preferencias de los conductores
enum DriverPreferences {
  smokingAllowed,
  smokeFreeSpace,
  alwaysWithMusic,
  loveSilence,
  loveToChat,
  veryShy,
  noAnimals,
  punctualityFirst,
  flexibleSchedule,
  loudMusic,
  softMusic,
  likeToSing,
  meetingNewPeople,
  dontLikeToTalkMuch,
  loveToTalk,
}

// Extension para extraer el texto del enum de preferencias
extension DriverPreferencesText on DriverPreferences {
  String get label {
    switch (this) {
      case DriverPreferences.smokingAllowed:
        return "Fumadores permitidos";
      case DriverPreferences.smokeFreeSpace:
        return "Espacio sin humo";
      case DriverPreferences.alwaysWithMusic:
        return "Siempre con música";
      case DriverPreferences.loveSilence:
        return "Adoro el silencio";
      case DriverPreferences.loveToChat:
        return "Me encanta charlar";
      case DriverPreferences.veryShy:
        return "Soy muy tímido";
      case DriverPreferences.noAnimals:
        return "Sin animales, por favor";
      case DriverPreferences.punctualityFirst:
        return "Puntualidad ante todo";
      case DriverPreferences.flexibleSchedule:
        return "Flexible con el horario";
      case DriverPreferences.loudMusic:
        return "Música alta, sin problema";
      case DriverPreferences.softMusic:
        return "Música suave, por favor";
      case DriverPreferences.likeToSing:
        return "Me gusta cantar en el coche";
      case DriverPreferences.meetingNewPeople:
        return "Me encanta conocer gente nueva";
      case DriverPreferences.dontLikeToTalkMuch:
        return "No me gusta hablar mucho";
      case DriverPreferences.loveToTalk:
        return "Me encanta hablar";
    }
  }
}

// Funcion para cargar las preferencias del conductor desde un JSON
List<DriverPreferences> loadUserPreferences(Map<String, dynamic> json) {
  final results = json['results'] as List? ?? [];
  return results
      .map((item) => parseEnum<DriverPreferences>(item['pref_type'], DriverPreferences.values))
      .whereType<DriverPreferences>()
      .toList();
}


// Enum para los tipos de viaje
enum TravelType {
  all,
  periodic,
  punctual
}

extension TravelTypeText on TravelType {
    String get label {
      switch (this) {
        case TravelType.all:
          return "Todos";
        case TravelType.periodic:
          return "Periódico";
        case TravelType.punctual:
          return "Puntual";
      }
    }
}

// Enum para los tipos de usuarios
enum UsersType {
  all, // Representa a todos los usuarios
  std, // Estudiante
  prof, // Preofesor
  unStf // Resto del personal
}

extension UsersTypeText on UsersType {
    String get label {
      switch (this) {
        case UsersType.all:
          return "Todos";
        case UsersType.std:
          return "Alumnos";
        case UsersType.prof:
          return "Profesores";
        case UsersType.unStf:
          return "Resto del personal";
      }
    }
}

// Funcion generia que dado un string y una lista, pasa ese string a su enum correspondiente
T? parseEnum<T extends Enum>(String? value, List<T> values) {
  if (value == null || value.isEmpty) return null;

  final normalized = value.toLowerCase();

  try {
    return values.firstWhere(
      (e) => e.name.toLowerCase() == normalized,
    );
  } catch (_) {
    return null;
  }
}

// Enum para los tipos de distintivos medioambientales
enum EnvSticker {
  all, // Sin distintivo
  eco, // ECO
  b, // B
  c, // C
  hist, // Vehiculo historico
  cero, // CERO
}

extension EnvStickerText on EnvSticker {
    String get label {
      switch (this) {
        case EnvSticker.all:
          return "-"; 
        case EnvSticker.eco:
          return "ECO";
        case EnvSticker.b:
          return "B";
        case EnvSticker.c:
          return "C";
        case EnvSticker.hist:
          return "H";
        case EnvSticker.cero:
          return "0";
      }
    }
}

// Funcion para parsear el distintivo medioambiental desde un string
extension EnvStickerParser on EnvSticker {
  static EnvSticker? fromString(String? value) {
    if (value == null) return null;

    return EnvSticker.values.firstWhere(
      (e) => e.label.toLowerCase() == value.toLowerCase(),
      orElse: () => EnvSticker.all,
    );
  }
}

// Enum para los tipos de valoración
enum RatingsTypes{
  driverSkills,
  punctuality,
  kindness,
  cleanliness,
  flexibility,
  reliability
}

extension RatingsTypesText on RatingsTypes{
  String get label {
      switch (this) {
        case RatingsTypes.driverSkills:
          return "Habilidad al volante";
        case RatingsTypes.punctuality:
          return "Puntualidad";
        case RatingsTypes.kindness:
          return "Amabilidad";
        case RatingsTypes.cleanliness:
          return "Limpieza";
        case RatingsTypes.flexibility:
          return "Flexibilidad";
        case RatingsTypes.reliability:
          return "Fiabilidad";
      }
    }
}

// Enum para los colores de los vehículos
enum CarColor {
  white,
  black,
  gray,
  silver,
  blue,
  red,
  green,
  yellow,
  orange,
  brown,
  beige,
  burgundy,
  none
}

// Extension para obtener el texto de los colores de los vehículos
extension CarColorLabel on CarColor {
  String get label {
    switch (this) {
      case CarColor.white: return "Blanco";
      case CarColor.black: return "Negro";
      case CarColor.gray: return "Gris";
      case CarColor.silver: return "Plata";
      case CarColor.blue: return "Azul";
      case CarColor.red: return "Rojo";
      case CarColor.green: return "Verde";
      case CarColor.yellow: return "Amarillo";
      case CarColor.orange: return "Naranja";
      case CarColor.brown: return "Marrón";
      case CarColor.beige: return "Beige";
      case CarColor.burgundy: return "Burdeos";
      case CarColor.none: return "N/A";
    }
  }
}

CarColor? carColorParser(String? value) {
  if (value == null) return null;
  switch (value.toLowerCase()) {
    case "white":
    case "blanco":
      return CarColor.white;
    case "black":
    case "negro":
      return CarColor.black;
    case "gray":
    case "gris":
      return CarColor.gray;
    case "silver":
    case "plata":
      return CarColor.silver;
    case "blue":
    case "azul":
      return CarColor.blue;
    case "red":
    case "rojo":
      return CarColor.red;
    case "green":
    case "verde":
      return CarColor.green;
    case "yellow":
    case "amarillo":
      return CarColor.yellow;
    case "orange":
    case "naranja":
      return CarColor.orange;
    case "brown":
    case "marrón":
      return CarColor.brown;
    case "beige":
      return CarColor.beige;
    case "burgundy":
    case "burdeos":
      return CarColor.burgundy;
    default:
      return null;
  }
}

// Enum para los estados de los viajes
enum TravelStatus{
  active, // activo
  started, // en curso
  fnd // finalizado
}

extension TravelStatusLabel on TravelStatus{
  String get label{
    switch(this){
      case TravelStatus.active: return "Activo";
      case TravelStatus.started: return "En curso";
      case TravelStatus.fnd: return "Finalizado";
    }
  }
}

// Enum para los estados de las solicitudes de viaje
enum RequestStatus{
  pending, // pendiente
  accepted, // aceptada
  rejected, // rechazada
  validated, // validada (viaje finalizado y validado por el conductor, para que pueda valorarle)
  unvalidated // invalidada (viaje finalizado sin ser validado por el conductor, por lo que no puede valorarle)
}

extension RequestStatusLabel on RequestStatus{
  String get label{
    switch(this){
      case RequestStatus.pending: return "Pendiente";
      case RequestStatus.accepted: return "Aceptado";
      case RequestStatus.rejected: return "Rechazado";
      case RequestStatus.validated: return "Validado";
      case RequestStatus.unvalidated: return "Invalidado";
    }
  }
}

// Enum para los estados del chat
enum ChatStatus{
  deny,
  allow,
  silence
}

extension ChatStatusLabel on ChatStatus{
  String get label{
    switch(this){
      case ChatStatus.deny: return "Denegado";
      case ChatStatus.allow: return "Permitido";
      case ChatStatus.silence: return "Silenciado";
    }
  }
}

// Enum para las opciones de la API
enum ApiOptions{
  get,
  post,
  put,
  delete,
  patch
}

// Enum para los códigos de error de la API
enum ErrorCode {
  // User Errors
  userDontExist(0),
  emailAlreadyExists(1),
  usernameAlreadyExists(2),
  userDeleted(3),
  passwordMismatch(5),
  invalidCredentials(6),
  insufficientCredentials(7),
  tokenExpired(8),
  incorrectToken(9),
  userNotVerified(10),
  emailError(11),

  // Vehicle Errors
  licensePlateAlreadyExists(20),
  licensePlateTooLong(21),
  vehicleAssociatedToActiveTravel(22),
  vehicleNotFound(23),
  vehicleSeatsInsufficient(24),

  // Travel Errors
  travelDontExist(30),
  travelAlreadyDeleted(31),
  travelNotFound(32),
  travelAlreadyExists(33),
  travelIsFull(34),
  travelIsNotPeriodic(35),
  travelIsNotPunctual(36),
  fromDateRequired(37),
  toDateRequired(38),
  requestOwnTravel(39),
  alreadyRequested(40),
  invalidPeriodicInterval(41),
  seatsBelowOccupied(42),
  invalidValidationCode(43),
  pickupPointNotFound(44),
  travelAlreadyStarted(45),

  // Travel Request Errors
  invalidRequestStatus(60),

  // General Errors
  missingRequiredField(50),
  internalServerError(99),

  unknownError(-1);

  final int code;
  const ErrorCode(this.code);

  // funcion para sacar el enum a partir del código de error
  static ErrorCode fromCode(int code) {
    return ErrorCode.values.firstWhere(
      (error) => error.code == code,
      orElse: () => ErrorCode.unknownError,
    );
  }
}

// Enum para los tipos de alertas
enum AlertType{
  error,
  success,
  warning,
  info
}