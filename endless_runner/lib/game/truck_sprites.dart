import 'zombie_sprites.dart' show PixelSprite;

/// Arte de 8 bits de los camiones: la cara trasera de la caja (las puertas
/// que ve el corredor al llegar). Es una cuadrícula de texto como los zombis:
/// cada carácter es un píxel y '.' es transparente. Los costados, el techo y
/// la rampa se dibujan con formas en [TruckComponent].
///
/// Letras (ver [TruckComponent] para los colores de cada aspecto):
///  O contorno · b/l/d chapa (base/luz/sombra) · s/S franja (clara/oscura)
///  r/R luz trasera · y reflejo · D/k negro (marcos, goma) · g metal
///  u óxido · W blanco sucio (letras y patente).
abstract final class TruckSprites {
  /// Cara trasera de la caja: 36x30 píxeles.
  static final PixelSprite rear = PixelSprite(_rear);

  static const List<String> _rear = [
    '.OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO.',
    'OllllllllllllllllllllllllllllllllllO',
    'OllllllllllllllllllllllllllllllllllO',
    'OblbbbbbbbbbbbbddDDlbbbbbbbbbbbddddO',
    'OblbbbgDbbbbgDbddDDlbbbgDbbubgDddddO',
    'ODDbubgDbbbbgDbddDDlbbbgDbbubgDddDDO',
    'ODDbubgDbbbbgDbddDDlbbbgDbbubgDddDDO',
    'OblbuWWDWWbWWDbddDDlbbbWWbWubWWddddO',
    'OblbuWWDWWbWWDbddDDlbbbWWbWubWWddddO',
    'OblbubbbbbbbbDbddDDlbbbbbbbubbbddddO',
    'OblbuWWDWWbWWDkddDDlbkbWWbWubWWddddO',
    'OblbuWWDWWbWWDkddDDlbkbWWbWubWWddddO',
    'ODDbubgDbbbbgDkddDDlbkbgddddbgDudDDO',
    'ODDbubgDbbbbgDkddDDlbkbgddddbgDudDDO',
    'OblbbbgDbbbbgDkddDDlbkbgDddbbgDudddO',
    'OblssssssssssssssDDssssssssssssudddO',
    'OblssssssusssssssDDssssssssssssudddO',
    'OblSSSSSSuSSSSSSSDDSSSSSSSSSSSSudddO',
    'OblbbbgDbubbgDbddDDlbuuuubbbbgDudddO',
    'ODDbbbuuuubbgDbddDDlbuuuubbbbgDudDDO',
    'ORyrrbuuuubbgDbddDDlbuuuubbbbgDrryRO',
    'ORrrrbuuuubbbbbddDDlbbbbbbbbbbbrrrRO',
    'ORrrrddddudddddddDDddddddddddddrrrRO',
    'ORRRRddddddddddddddddddddddddddRRRRO',
    'OddddddddddddddddddddddddddddddddddO',
    'ggggggggggggggWWWWWWWWgggggggggggggg',
    'DDDDDDDDDDDDDDWkkWkkkWDDDDDDDDDDDDDD',
    'kkkkkkkkkkkkkkWWWWWWWWkkkkkkkkkkkkkk',
    'kkggkkkkkkkkkkkkkkkkkkkkkkkkkkkkggkk',
    '.kggkkkkkkkkkkkkkkkkkkkkkkkkkkkkggk.',
  ];
}
