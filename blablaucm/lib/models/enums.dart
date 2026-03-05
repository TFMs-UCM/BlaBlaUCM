
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

enum UsersType {
  all,
  student,
  professor,
  universityStuff
}

extension UsersTypeText on UsersType {
    String get label {
      switch (this) {
        case UsersType.all:
          return "Todos";
        case UsersType.student:
          return "Alumnos";
        case UsersType.professor:
          return "Profesores";
        case UsersType.universityStuff:
          return "Resto del personal";
      }
    }
}

enum EnvSticker {
  all,
  eco,
  b,
  c,
  historic,
  cero,
}

extension EnvStickerText on EnvSticker {
    String get label {
      switch (this) {
        case EnvSticker.all:
          return "-"; // TODO mirar si se puede sustituir por "Todos"
        case EnvSticker.eco:
          return "ECO";
        case EnvSticker.b:
          return "B";
        case EnvSticker.c:
          return "C";
        case EnvSticker.historic:
          return "H";
        case EnvSticker.cero:
          return "0";
      }
    }
}


enum RatingsTypes{
  driverSkills,
  punctuality,
  kindness,
  cleanliness,
  flexibility,
  realiability
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
        case RatingsTypes.realiability:
          return "Fiabilidad";
      }
    }
}


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
}

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
    }
  }
}

enum TravelStatus{
  active,
  started,
  finished
}

extension TravelStatusLabel on TravelStatus{
  String get label{
    switch(this){
      case TravelStatus.active: return "Activo";
      case TravelStatus.started: return "En curso";
      case TravelStatus.finished: return "Finalizado";
    }
  }
}

enum RequestStatus{
  pending,
  accepted,
  rejected,
  validated,
  unvalidated
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
