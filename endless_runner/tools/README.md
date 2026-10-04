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
