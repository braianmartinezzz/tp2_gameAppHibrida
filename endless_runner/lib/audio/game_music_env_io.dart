import 'dart:io' show Platform;

/// true cuando la app corre dentro de `flutter test` (el flag lo inyecta la
/// herramienta de Flutter en el entorno del proceso). Ahí no existe el plugin
/// de audio: tocarlo levanta errores de canal que rompen los tests, así que
/// [GameMusic] directamente no hace nada.
bool get isTestEnvironment => Platform.environment.containsKey('FLUTTER_TEST');
