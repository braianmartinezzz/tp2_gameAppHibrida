# Herramientas de arte

`build_player_atlas.py` genera `assets/images/character/player_atlas.png` (el
atlas que dibuja `PlayerComponent`) a partir de `sprites_corredor.png`:

```
pip install pillow numpy scipy
python3 tools/build_player_atlas.py     # desde endless_runner/
```

- Limpia los 8 cuadros de carrera (saca los números y la sombra pintada).
- Compone poses de salto y de agachado reutilizando los píxeles del personaje.
- Los índices de las poses están en `player_component.dart` (`_jumpRise`, ...):
  si cambiás el orden del atlas, cambiá también esas constantes.

# Efectos de sonido

`build_sfx.py` sintetiza los efectos de `assets/audio/sfx/*.wav` (botones,
diamantes, golpes, muerte, pasos, salto...) con numpy, sin samples de terceros:

```
pip install numpy scipy
python3 tools/build_sfx.py     # desde endless_runner/
```

Los nombres de archivo se usan en `lib/audio/game_sfx.dart` (enum `Sfx`): si
agregás un efecto, sumalo en `CUES` del script y como valor del enum.
