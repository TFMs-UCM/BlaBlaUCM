
import 'package:blablaucm/models/vehicle_model.dart';
import 'package:flutter/material.dart';
import 'package:blablaucm/models/user_model.dart';
import 'package:blablaucm/models/enums.dart';
import 'package:blablaucm/screens/vehicles.dart';
import 'package:blablaucm/screens/helper.dart';

class Profile extends StatefulWidget {
  final UserModel user;

  const Profile({super.key, required this.user});

  @override
  State<Profile> createState() => _ProfileState();
}

// Lista de vehiculos de prueba
List<VehicleModel> exampleVehicles = [
  VehicleModel(id: "1", model: "Ford", brand: "Bronco", plate: "123456F", envSticker: EnvSticker.b, numSeats: 5),
  VehicleModel(id: "2", model: "Citroen", brand: "C3", plate: "123456F", envSticker: EnvSticker.b, numSeats: 5),
  VehicleModel(id: "3", model: "Toyota", brand: "Corolla", plate: "123456F", envSticker: EnvSticker.b, numSeats: 5),
  VehicleModel(id: "4", model: "Nissan", brand: "skyline", plate: "123456F", envSticker: EnvSticker.b, numSeats: 5),
  VehicleModel(id: "5", model: "Renault", brand: "Clio", plate: "123456F", envSticker: EnvSticker.b, numSeats: 5),
  VehicleModel(id: "6", model: "Tesla", brand: "Model S", plate: "123456F", envSticker: EnvSticker.b, numSeats: 5),
  VehicleModel(id: "7", model: "Caterpillar", brand: "797F", plate: "123456F", envSticker: EnvSticker.b, numSeats: 5),
];

List<double> exampleRatings =[4.5,3.9,1.0,2.2,5.0,0];


class _ProfileState extends State<Profile> {
  bool showPreferences = false;
  bool usernameError = false;
  bool validateEmail = false;
  

  void _openPreferencesDialog() {
    setState(() {
      showPreferences = !showPreferences;
    });
  }

  void _editUsername() {
    final controller = TextEditingController(text: widget.user.username);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Editar nombre de usuario"),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: "Nuevo nombre de usuario",
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  widget.user.username = controller.text;
                });
                Navigator.pop(context);
              },
              child: const Text("Guardar"),
            ),
          ],
        );
      },
    );
  }

  void _openRatingsDialog(List<double> ratings) {
    showRatingsDialog(context, ratings);
  }



  void _editEmail() {
    final controller = TextEditingController(text: widget.user.email);
    // TODO VALIDAR LA DIRECCION DE CORREO CON UN EMAIL Y QUE INTRODUZCA EL ID QUE SE LE ENVIA
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Editar email"),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: "Nuevo email",
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  widget.user.email = controller.text;
                });
                Navigator.pop(context);
              },
              child: const Text("Guardar"),
            ),
          ],
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    user.preferences ??= [];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Perfil"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(36),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        // FOTO DE PERFIL
                        CircleAvatar(
                          radius: 50,
                          backgroundImage: user.profilePicture?.image,
                          child: user.profilePicture == null
                              ? const Icon(Icons.person, size: 50)
                              : null,
                        ),

                        const SizedBox(height: 20),

                        // USERNAME
                        ListTile(
                        title: const Text("Nombre de usuario"),
                        subtitle: Text(
                          user.username,
                          style: TextStyle(
                            color: usernameError ? Colors.red : Colors.black,
                          ),
                        ),
                        trailing: const Icon(Icons.edit),
                        onTap: _editUsername,
                      ),

                      if (usernameError)
                        const Padding(
                          padding: EdgeInsets.only(left: 16, bottom: 8),
                          child: Text(
                            "El nombre de usuario ya esta en uso",
                            style: TextStyle(color: Colors.red),
                          ),
                        ),


                        // EMAIL
                        ListTile(
                          title: const Text("Email"),
                          subtitle: Text(user.email),
                          trailing: const Icon(Icons.edit),
                          onTap: _editEmail,
                        ),

                        const Divider(height: 30),

                        // PREFERENCIAS
                        ListTile(
                          title: const Text("Preferencias del conductor"),
                          subtitle: Text(
                            (user.preferences == null || user.preferences!.isEmpty)
                                ? "Ninguna seleccionada"
                                : "${user.preferences!.length} seleccionadas",
                          ),
                          trailing: const Icon(Icons.arrow_drop_down),
                          onTap: _openPreferencesDialog,
                        ),

                        if (showPreferences)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                for (var pref in DriverPreferences.values)
                                  CheckboxListTile(
                                    title: Text(pref.label),
                                    value: user.preferences!.contains(pref),
                                    onChanged: (value) {
                                      setState(() {
                                        if (value == true) {
                                          user.preferences!.add(pref);
                                        } else {
                                          user.preferences!.remove(pref);
                                        }
                                      });
                                    },
                                  ),
                              ],
                            ),
                          ),



                        const Divider(height: 30),

                        // VEHICULOS
                        ListTile(
                          title: const Text("Vehículos"),
                          trailing: const Icon(Icons.directions_car),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute( // TODO SUSTITUIR exampleVehicles por user.vehicles cuando se carguen del WS
                                builder: (context) => VehiclesScreen(vehicles: exampleVehicles ?? []),
                              ),
                            );
                          },
                        ),

                        // VALORACIONES
                        ListTile(
                          title: const Text("Valoraciones"),
                          trailing: const Icon(Icons.star), // TODO sustituir exampleRatings por user.ratings
                          onTap: () => _openRatingsDialog(exampleRatings),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // BOTONES COMO EN LA PANTALLA DE FILTROS
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.grey.shade300,
                          foregroundColor: Colors.black,
                        ),
                        child: const Text(
                          "Cancelar",
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (user.username == "Guacamole") { // TODO cambiar por validacion del WS, y no se cambia hasta que el WS lo de por valido en bbdd (la app reciba respuesta del WS)
                          // Evita que se ponga uno que ya esta en uso
                          setState(() {
                            usernameError = true;
                          });
                          return; // NO cerrar la pantalla
                        }
                        // Si no hay error, cerrar
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        "Guardar",
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),

                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
