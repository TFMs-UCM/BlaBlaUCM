
// Enum para las preferencias de los conductores
enum DriverPreferences {
  //todos,
  fumadoresPermitidos,
  espacioSinHumo,
  siempreConMusica,
  adoroElSilencio,
  meEncantaCharlar,
  soyMuyTimido,
  sinAnimales,
  puntualidadAnteTodo,
  flexibleHorario,
  musicaAlta,
  musicaSuave,
  meGustaCantar,
  conocerGenteNueva,
  noMeGustaHablarMucho,
  meEncantaHablar,
}

// Extension para extraer el texto del enum de preferencias
extension DriverPreferencesText on DriverPreferences {
  String get label {
    switch (this) {
      // case DriverPreferences.todos:
      //   return " - ";
      case DriverPreferences.fumadoresPermitidos:
        return "Fumadores permitidos";
      case DriverPreferences.espacioSinHumo:
        return "Espacio sin humo";
      case DriverPreferences.siempreConMusica:
        return "Siempre con música";
      case DriverPreferences.adoroElSilencio:
        return "Adoro el silencio";
      case DriverPreferences.meEncantaCharlar:
        return "Me encanta charlar";
      case DriverPreferences.soyMuyTimido:
        return "Soy muy tímido";
      case DriverPreferences.sinAnimales:
        return "Sin animales, por favor";
      case DriverPreferences.puntualidadAnteTodo:
        return "Puntualidad ante todo";
      case DriverPreferences.flexibleHorario:
        return "Flexible con el horario";
      case DriverPreferences.musicaAlta:
        return "Música alta, sin problema";
      case DriverPreferences.musicaSuave:
        return "Música suave, por favor";
      case DriverPreferences.meGustaCantar:
        return "Me gusta cantar en el coche";
      case DriverPreferences.conocerGenteNueva:
        return "Me encanta conocer gente nueva";
      case DriverPreferences.noMeGustaHablarMucho:
        return "No me gusta hablar mucho";
      case DriverPreferences.meEncantaHablar:
        return "Me encanta hablar";
    }
  }
}

enum TravelType {
  todos,
  periodico,
  puntual
}

extension TravelTypeText on TravelType {
    String get label {
      switch (this) {
        case TravelType.todos:
          return "Todos";
        case TravelType.periodico:
          return "Periódico";
        case TravelType.puntual:
          return "Puntual";
      }
    }
}

enum UsersType {
  todos,
  alumno,
  profesor,
  restoPersonal
}

extension UsersTypeText on UsersType {
    String get label {
      switch (this) {
        case UsersType.todos:
          return "Todos";
        case UsersType.alumno:
          return "Alumnos";
        case UsersType.profesor:
          return "Profesores";
        case UsersType.restoPersonal:
          return "Resto del personal";
      }
    }
}

enum EnvSticker {
  todas,
  eco,
  b,
  c,
  historico,
  cero,
}

extension EnvStickerText on EnvSticker {
    String get label {
      switch (this) {
        case EnvSticker.todas:
          return "Todas";
        case EnvSticker.eco:
          return "ECO";
        case EnvSticker.b:
          return "B";
        case EnvSticker.c:
          return "C";
        case EnvSticker.historico:
          return "H";
        case EnvSticker.cero:
          return "0";
      }
    }
}



