/// Versión de [isTestEnvironment] para plataformas sin `dart:io` (web, wasm):
/// en el navegador no hay forma de leer el entorno, y los tests ahí corren con
/// el plugin de audio real disponible.
bool get isTestEnvironment => false;
