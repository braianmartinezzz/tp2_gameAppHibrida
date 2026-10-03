# Contexto de la aplicación — Endless Runner 2.5D

Documento de referencia completo del proyecto: qué es, cómo está armado, qué
mecánicas tiene, qué está simulado y cómo correrlo.

---

## 1. Descripción general

**Endless runner 2.5D estilo Subway Surfers** — Trabajo 2 de la materia
Laboratorio de Apps Móviles.

| Dato | Valor |
|---|---|
| Paquete (`pubspec.yaml`) | `runner_flutter` |
| Nombre visible | `Runner 2.5D` (app), `Endless Runner` (iOS) / `endless_runner` (Android/web) |
| Versión | `1.0.0+1` |
| SDK Dart | `>=3.0.0 <4.0.0` |
| Framework | Flutter + **Flame `^1.18.0`** (motor de juego 2D) |
| UI | Material 3 (`useMaterial3: true`), modo claro/oscuro |
| Assets | Ninguno: todo el arte es **vectorial dibujado a mano** en Canvas |

### Qué está simulado (sin backend)

Todo el estado del jugador y la monetización es **local y simulada**, como pide
la consigna:

- **Usuario** ya "logueado": `braian_123` (fijo, sin autenticación).
- **Diamantes**: empieza con 85; la tienda solo suma a un contador en memoria.
- **Anuncio**: modal con countdown de 3 s antes de cada reinicio.
- **Cuenta basic/pro**: chip informativo en el header.
- **Récord**: vive en memoria — sobrevive a los reinicios de partida, no a
  cerrar la app.

---

## 2. Arquitectura

### Árbol de `lib/`

```
lib/
├── main.dart                 → RunnerApp: crea el GameState único y el MaterialApp
├── screens/
│   └── home_screen.dart      → HomeScreen: header + juego + botonera
├── state/
│   └── game_state.dart       → GameState global (ValueNotifier)
├── theme/
│   └── app_theme.dart        → AppTheme.light / AppTheme.dark
├── widgets/                  → Capa Flutter alrededor del canvas
│   ├── game_header.dart          (barra superior)
│   ├── game_controls.dart        (botonera externa)
│   ├── game_over_overlay.dart    (resumen al morir)
│   ├── record_chip.dart          (récord en pantalla)
│   ├── ad_modal.dart             (anuncio simulado)
│   └── diamond_shop_modal.dart   (tienda de diamantes)
└── game/                     → Motor Flame
    ├── runner_game.dart          (orquestador del juego)
    ├── perspective.dart          (proyección 2.5D)
    ├── depth_component.dart      (base de actores con profundidad)
    ├── player_component.dart     (corredor: carril/salto/roll)
    ├── obstacle_component.dart   (3 tipos de obstáculos)
    ├── coin_component.dart       (diamantes en el corredor + patrones)
    ├── power_up_component.dart   (ítems: escudo/imán/x2)
    ├── power_up_state.dart       (estado puro de power-ups)
    ├── map_renderer.dart         (desierto, 10 capas de parallax)
    └── juice.dart                (feedback: chispas, shake, destellos)
```

### Diagrama de relaciones

```
                    ┌────────────────────────────┐
                    │        main.dart           │
                    │   RunnerApp (Stateless)    │
                    │   crea GameState() único   │
                    └─────────────┬──────────────┘
                                  │
                    ┌─────────────▼──────────────┐
                    │   HomeScreen (Stateful)    │
                    │  crea RunnerGame en init   │
                    └─────────────┬──────────────┘
                                  │
     ┌────────────────────────────┼────────────────────────────┐
     │                            │                            │
┌────▼─────────┐   ┌──────────────▼──────────────┐   ┌─────────▼────────┐
│ GameHeader   │   │  Stack (área del corredor)  │   │  GameControls    │
│ usuario      │   │  ┌────────────────────────┐ │   │  ▶ play          │
│ score        │   │  │ GameWidget(RunnerGame) │ │   │  ⏸ pausa         │
│ chip BASIC/  │   │  │  canvas Flame          │ │   │  ↻ reiniciar     │
│ PRO          │   │  │  + HUD power-ups       │ │   │    (tras anuncio) │
│ 💎 → tienda  │   │  ├────────────────────────┤ │   │  🌓 tema         │
└──────┬───────┘   │  │ RecordChip (sup-izq)   │ │   └─────────┬────────┘
       │           │  │ GameOverOverlay (si    │ │             │
       │           │  │  isGameOver)           │ │             │
       │           │  └────────────────────────┘ │             │
       │           └──────────────┬──────────────┘             │
       │                          │                            │
       └──────────────┬───────────┴────────────┬───────────────┘
                      │   GameState (ValueNotifier)  ◄─── lee/escribe
                      │   username score diamonds     ambos lados
                      │   accountType isGameOver
                      │   themeMode bestScore
                      │   isNewRecord runDiamonds
                      └──────────────┬──────────────┘
                                     │ referencia compartida
                      ┌──────────────▼──────────────┐
                      │     RunnerGame (Flame)      │
                      │  update/render + spawns     │
                      └─────────────────────────────┘
```

### Patrón clave: desacoplamiento UI ↔ motor

`GameState` se pasa **por referencia** al `FlameGame`. El juego lee/escribe
score y diamantes; la UI Flutter (header, botonera, modales) se suscribe con
`ValueListenableBuilder` sobre los `ValueNotifier`. Así:

- La UI **nunca** toca componentes del motor ni viceversa (salvo las llamadas
  explícitas `resumeEngine/pauseEngine/restartRun` desde la botonera).
- Cualquier cambio de estado se propaga solo a los widgets suscriptos.

---

## 3. Estado global — `state/game_state.dart`

Clase `GameState` con `ValueNotifier` públicos:

| Campo | Tipo | Default | Descripción |
|---|---|---|---|
| `username` | `String` | `'braian_123'` | Usuario simulado |
| `score` | `int` | `0` | Puntaje de la partida actual |
| `diamonds` | `int` | `85` | Billetera (se gasta en tienda/golpes) |
| `accountType` | `String` | `'basic'` | `'basic'` \| `'pro'` |
| `isGameOver` | `bool` | `false` | La partida terminó |
| `themeMode` | `ThemeMode` | `dark` | Modo claro/oscuro |
| `bestScore` | `int` | `0` | Récord de la sesión (en memoria) |
| `isNewRecord` | `bool` | `false` | La partida superó el récord |
| `runDiamonds` | `int` | `0` | Diamantes ganados en la corrida (para el resumen) |

### Métodos principales

- `collectDiamond()` — suma **1 a la billetera y 1 a `runDiamonds`**: el
  resumen puede contar lo ganado en la corrida sin pisar la billetera.
- `finishRun()` — **única puerta de entrada al game over**. Calcula
  `isNewRecord`, actualiza `bestScore` si corresponde y recién entonces pone
  `isGameOver = true`. Un segundo llamado (colisión doble) no pisa lo celebrado.
- `spendDiamonds(int)` — devuelve `false` si no alcanza; nunca falla si hay
  saldo.
- `resetRun()` — limpia score/`runDiamonds`/`isNewRecord`/`isGameOver`.
  **`bestScore` no se toca**: el récord sobrevive a los reinicios.
- `toggleTheme()` / `toggleAccountType()` — alternan modo y cuenta.
  > Nota: `toggleAccountType()` existe pero **no está conectado a ningún
  > botón**; el chip `BASIC/PRO` es solo informativo.
- `isPro` (getter) — `accountType == 'pro'`.

---

## 4. Motor del juego — `game/`

### 4.1 `runner_game.dart` — orquestador

`class RunnerGame extends FlameGame with PanDetector, HasCollisionDetection`

Responsabilidades: loop de vida, spawns, colisiones, gestos, render en capas y
reinicio. Expone `player`, `powerUps`, `juice` y `perspective` como públicos
para que los tests lo lean/disparen a mano.

**Ciclo de `update(dt)`:**

1. Si `isGameOver`: el mundo queda **congelado** (no llama `super.update`),
   solo se disipa el `juice` y, cuando termina la gracia de muerte
   (`_deathGrace = 1.05 s`), se **pausa el motor**. Así el destello de la
   muerte no se congela a plena opacidad ni la cámara queda corrida.
2. Si no: actualiza perspectiva, power-ups, parpadeo de invulnerabilidad,
   polvo al aterrizar, score, dificultad, mapa, spawns y colisiones.

**Score:** acumulador fraccionario `_scoreCarry += dt * 20 * multiplier`
(20 pts/s; ×2 con multiplicador). Se trunca a enteros para que a 60 fps no se
quede clavado en 0.

**Dificultad:** velocidad base `260 px/s`, acelera `+6 px/s` por segundo
transcurrido (`260 + _elapsed * 6`). El piso avanza a la misma velocidad.

**Spawns:**

| Elemento | Cadencia | Pesos |
|---|---|---|
| Obstáculos | `max(0.45, 1.1 - elapsed*0.01)` s | 40% bloque / 30% valla / 30% losa |
| Tandas de monedas | 2.6–4.0 s (inicial 2.0 s) | 30% line / 25% arc / 20% zigzag / 25% high |
| Power-ups | 14–22 s (inicial 10 s) | 40% escudo / 30% imán / 30% x2 |

**Regla de fair-play (spawn seguro):**

- `_nextLane()` garantiza que entre los 3 obstáculos más cercanos **nunca haya
  3 carriles distintos**: siempre queda un carril libre para esquivar.
- `_depthIsFree()` impide que monedas/power-ups nazcan sobre un obstáculo
  (misma profundidad ±28 px y solape de carril); hasta 6 intentos de anclaje.

**Colisión (`_onCollision`):** primero intenta el escudo (`absorbHit()`); si no
absorbe, si `diamonds >= 10` **paga 10 diamantes** ("revivir") y queda
invulnerable un respiro; si no, `finishRun()` + `juice.death()` + gracia de
1.05 s antes de pausar.

**Gestos (`PanDetector`):** acumula deltas hasta cruzar el umbral de **22 px**
y dispara **una acción por gesto**, eligiendo el eje dominante:

- `←` / `→` → cambiar de carril
- `↑` → saltar
- `↓` → agacharse (o tirarse si está en el aire)

**`render()`:** aplica la **sacudida de cámara** con overscan (`1 + 2*shake/
min(w,h)`) para que el borde del mapa no asome; dentro de la traslación dibuja
mapa → componentes → juice; afuera (sin temblor) dibuja el destello de viñeta
y el **HUD de power-ups** (fichas de 38 px + barras de progreso, esquina
superior derecha, sobre el canvas — no usa widgets de Flutter).

**`restartRun()`:** limpia obstáculos/monedas/ítems, `powerUps.reset()`,
`juice.reset()`, resetea cooldowns/velocidad/score, `gameState.resetRun()`,
`player.resetTo()` y `resumeEngine()`.

### 4.2 `perspective.dart` — proyección 2.5D

`Perspective(width, height)` const con la **fuente única de verdad** de la
geometría (la comparten mapa, actores y jugador):

- Profundidad normalizada `t`: `t = 0` horizonte, `t = 1` línea base.
- Punto de fuga: `vanishY = height * 0.14`, `vanishX = width * 0.5`.
- Base del corredor: `baseLeftX = width * 0.04` … `baseRightX = width * 0.96`.
- `xAtT(lane, t)` — los carriles **colapsan** en el punto de fuga.
- `halfWidthAtT(t) = baseWidth * 0.5 * t`, `scaleAtT(t) = t`.
- Métodos: `tAtY`, `yAtT`, `clampToCorridor`.

### 4.3 `depth_component.dart` — base de los actores

`abstract class DepthComponent extends PositionComponent` — de la que derivan
obstáculos, monedas y power-ups.

- **Ley de movimiento:** `baseY += speed * (0.5 + 0.5*t) * dt` (misma
  aceleración perspectiva que las rayas del piso; `t` es la profundidad).
- Constantes: `spawnT` default `0.06`, `fadeSpan = 0.14` (fundida de
  aparición), **`depthMargin = 14` px** (ventana de fila para la colisión).
- **Colisión en 3 pasos** (`collidesWith(player)`):
  1. **fila**: `|(baseY − player.groundFeetY)| ≤ 14`;
  2. **carril**: solape de `hitBox` en X;
  3. **altura**: banda `[bandMin, bandMax]` del actor vs.
     `[jumpY, jumpY + bodyHeight]` del jugador.
- `false` mientras `alpha <= 0` (aún en fundida). Getter `offScreen` para
  reciclar.

### 4.4 `player_component.dart` — el corredor

Fila de suelo fija (`size.y * 0.86`): la profundidad del jugador **nunca
cambia**, solo salta. Eso mantiene estable el carril y da una referencia exacta
para las colisiones por altura.

**Constantes de balance:**

| Constante | Valor | Efecto |
|---|---|---|
| `playerSize` | 34 px | Alto parado |
| `rollHeight` | 16 px | Alto agachado (pasa bajo la losa 24..130) |
| `laneSpeed` | 4.5 carriles/s | ~0.22 s por carril |
| `jumpSpeed` | 380 px/s | Con `gravity` → salto ~0.63 s / **~60 px** |
| `gravity` | 1200 px/s² | |
| `rollDuration` | 0.55 s | Duración del agachado |
| `diveSpeed` | 900 px/s | Caída rápida al agacharse en el aire (dive) |

El salto de ~60 px **supera la valla (16 px)** pero **no el bloque (90 px) ni
la losa (arranca en 24 px)**: así cada obstáculo exige su gesto.

**API:** `moveLane(dir)`, `jump()` (solo en suelo y sin roll), `roll()` (en
aire = dive + roll pendiente al aterrizar), `resetTo()`, `setGroundY()`,
getters `groundY`, `groundFeetY`, `isAirborne`, `isRolling`, `bodyHeight`,
`hitBox`.

**Estado:** `lane` (objetivo −1/0/1), `lanePos` (interpolado, el que se
dibuja), `jumpY`/`jumpV` (parábola con integración semi-implícita),
`rollTimer`, `blinkAlpha` (parpadeo de invulnerabilidad). La X de pantalla
sale de `perspective.xAtT(lanePos, t)` — al saltar **no cambia de carril**.

### 4.5 `obstacle_component.dart` — obstáculos

Enum `ObstacleKind`. La **banda de altura** sobre el suelo define el gesto:

| Kind | Ancho | Banda | Gesto requerido |
|---|---|---|---|
| `lowBarrier` (valla) | 52 | 0..16 | **Se salta** |
| `overhead` (losa colgante/túnel) | 46 | 24..130 | **Hay que agacharse** (saltar no sirve) |
| `block` (contenedor) | 44 | 0..90 | **Hay que cambiar de carril** (más alto que el salto) |

Campo `wasTouching` para disparar la colisión **una sola vez por cruce**.
Render: sombra elíptica + dibujo por tipo (valla ámbar con franjas, losa con
franjas de peligro, contenedor rojo con costuras).

### 4.6 `coin_component.dart` — diamantes en el corredor

`CoinComponent` (enum `CoinPattern`) + `buildCoinPattern(...)`. Las monedas
del corredor **son diamantes**: cada una llama `gameState.collectDiamond()`.

| Patrón | Cantidad | Descripción |
|---|---|---|
| `line` | 7 | Barrido en línea recta |
| `arc` | 7 | Barrido curvo (anclajes ±0.5) |
| `zigzag` | 10 | Bloques de 4 alternando ±0.5 carril |
| `high` | 5 | **Elevadas** (banda 56..82) → hay que saltar |

- `worldSize = 26`, gema cian (`0xFF46DDF2`) con faceta y brillo.
- `spawnT = 0.13` (más profundo que los obstáculos, `0.06`, para que un
  obstáculo posterior nunca nazca pegado a la cola de monedas).
- Nunca monedas sueltas: siempre tandas validadas contra obstáculos.

### 4.7 Power-ups

**`power_up_component.dart`** — `PowerUpComponent` + `buildPowerUp(...)`:

| Kind | Color | Efecto |
|---|---|---|
| `shield` | `0xFF5AA9FF` | Absorbe **un** golpe (no apilable) |
| `magnet` | `0xFFFF6B6B` | Atrae monedas al carril del jugador |
| `multiplier` | `0xFFFFD166` | Score ×2 |

Se agarran **tocándolos** (banda 4..44, flotan con balanceo). El dibujo
compartido `static drawBadge(...)` es la única fuente de las fichas: la usan
el ítem, el HUD y las etiquetas de juice.

**`power_up_state.dart`** — `PowerUpState`, estado puro **fuera del árbol de
componentes**:

| Propiedad | Duración |
|---|---|
| `magnetDuration` | 6 s |
| `multiplierDuration` | 8 s |
| `invulnerableDuration` | 1.2 s (respiro tras absorber un golpe) |

API: `apply(kind)` (devuelve `false` si el escudo ya estaba activo → el ítem
no se consume), `absorbHit()`, `grantInvulnerability()`, `update(dt)`,
`reset()`, `scoreMultiplier`.

**Imán (en `runner_game.dart`):** ventana de 240 px antes de los pies, los
carriles se mueven a 4.0 carriles/s. **Solo mueve el carril** de la moneda —
la profundidad la gobierna la ley de perspectiva, así no se "teletransporta".

### 4.8 `map_renderer.dart` — el desierto

`MapRenderer` dibuja el ambiente en **10 capas**:

1. Cielo con gradiente → 2. Estrellas (solo noche) → 3. Luna/sol con halo →
4. Nubes a la deriva → 5. Parallax de mesetas + dunas (con "guiñada" según
`playerX`) → 6. Arena → 7. Hombro de grava + asfalto → 8. Marcas viales
(rayas de velocidad, divisores punteados ±0.5, líneas de borde ±1.14) →
9. Props de desierto (cactus, roca, arbusto, meseta, cartel — 7 por lado) →
10. Bruma de distancia + resplandor del horizonte.

- Avance en coordenada de mundo `z` (`dz = worldSpeed / corridorHeight * dt`):
  el piso se mueve a la misma velocidad que el juego.
- Dos paletas `_dark` / `_light`: **tema oscuro ⇒ desierto nocturno
  estrellado**; tema claro ⇒ desierto de día.
- Expuesto a tests: `props` y `drawProps` (`@visibleForTesting`).

### 4.9 `juice.dart` — feedback instantáneo

`Juice` **no es componente de Flame**: lo actualiza/dibuja `RunnerGame`.
Nada usa `TextPainter` (el "+1" es un trazo dibujado a mano, para que la
fuente de relleno de los tests/previews no salga un rectángulo).

| Evento | Feedback |
|---|---|
| `coinPickup` | Anillo cian + 7 chispas + etiqueta "+1" |
| `powerUpPickup` | Anillo grande + 14 chispas + ficha del poder + destello |
| `shieldAbsorb` | Onda azul (sin rojo) + shake 3.5 |
| `hitPaid` | Destello rojo 0.55 + shake 6 |
| `death` | Anillo hasta r=96 + 24 chispas + flash 0.9 + shake 11 |
| `landDust` | Anillo aplastado (polvo al aterrizar), tinte según tema |
| `flash` | Viñeta radial (un flash débil no pisa a uno fuerte) |

- `maxShake = 12` px, decaimiento exponencial (~9 Hz de wobble).
- `shake` / `shakeOffset` gobiernan la traslación de cámara en `render()`;
  `renderFlash()` se dibuja **fuera** del temblor (es viñeta, no mundo).

---

## 5. Interfaz de usuario — `screens/`, `widgets/`, `theme/`

### 5.1 `screens/home_screen.dart`

`HomeScreen` (StatefulWidget) crea el `RunnerGame` en `initState`. Layout:

```
Scaffold > SafeArea > Column
├── GameHeader
├── Expanded > Padding(12) > ClipRRect(18) > Stack
│   ├── GameWidget(game: _game)
│   ├── RecordChip (Positioned sup-izq, solo si !isGameOver)
│   └── GameOverOverlay (solo si isGameOver)
└── GameControls
```

`_restartAfterAd()`: `await showAdModal(context)` → `_game.restartRun()`
(mismo camino que la botonera: requisito de la consigna).

### 5.2 Widgets

| Widget | Qué hace |
|---|---|
| **`GameHeader`** | Barra superior: `CircleAvatar` + username + `score: N` + chip `BASIC`/`PRO` + ícono 💎 con contador → **tap abre la tienda** (`showDiamondShopModal`) |
| **`GameControls`** | Botonera externa de 4 `IconButton`: ▶ `resumeEngine()`, ⏸ `pauseEngine()`, ↻ **anuncio simulado + `restartRun()`**, 🌓 `toggleTheme()` (ícono según modo) |
| **`GameOverOverlay`** | Card animada (240 ms, `easeOutBack`) sobre el corredor: título "PARTIDA TERMINADA", filas **Puntaje** y **Récord**, píldora "¡NUEVO RÉCORD!" si aplica, "Ganaste N diamantes", botón **Reintentar** → `onRestart`. Lee los valores al construir (la partida está congelada) |
| **`RecordChip`** | Chip semitransparente arriba a la izquierda: trofeo ámbar + "Récord N" (suscripto a `bestScore`). Se oculta en game over. Colores fijos para verse igual en calle clara/oscura |
| **`showAdModal`** | `AlertDialog` "Anuncio simulado" con ícono de play, **countdown de 3 s** y botón "Cerrar (Ns)" deshabilitado hasta que termine. `barrierDismissible: false` |
| **`showDiamondShopModal`** | `showModalBottomSheet` "Comprar diamantes": packs **100 / 500 / 1200**, cada uno con botón "Comprar" → `addDiamonds(pack)` y cierra. Sin backend |

### 5.3 `theme/app_theme.dart`

| Modo | Background | Seed | Brillo |
|---|---|---|---|
| `AppTheme.light` | `0xFFF4F1EA` (hueso) | `0xFF3C34D8` (índigo) | light |
| `AppTheme.dark` | `0xFF15151A` (casi negro) | `0xFF7F77DD` (lila) | dark |

> El tema cambia la **UI Flutter** alrededor (header, botonera, modales) y la
> **paleta del mapa** en `MapRenderer` (día/noche). El resto del canvas de
> Flame es el mismo en ambos modos.

---

## 6. Economía y features simulados

### Flujo de diamantes

```
85 iniciales ──► recolección en el corredor (+1 c/u, suma a billetera y a runDiamonds)
     │
     ├──► tienda (packs 100/500/1200, suma local)
     │
     └──► golpe sin escudo: si diamonds >= 10 → gasta 10 ("revivir" + invuln. 1.2 s)
                                      si no  → finishRun() (game over)
```

### Flujo de reinicio (con anuncio)

```
Botón ↻ de GameControls  ─┐
                          ├──► showAdModal (3 s) ──► game.restartRun()
Botón "Reintentar" del    ─┘
GameOverOverlay
```

### Récord

`finishRun()` es la única puerta al game over: congela el resultado, actualiza
`bestScore` y deja `isGameOver`. `resetRun()` **no** toca `bestScore`.

---

## 7. Tests — `test/`

≈ **60 tests en 12 archivos**. Patrón común: `TestWidgetsFlutterBinding`,
geometría fija `const Perspective(width: 480, height: 760)` y helpers
(`_player()`, `_jumping({seconds})`, `_atRow(...)`).

| Archivo | Qué cubre |
|---|---|
| `perspective_test.dart` | Profundidad `t↔y` ida y vuelta, escala, carriles que convergen al punto de fuga, `clampToCorridor` |
| `gameplay_test.dart` | Colisión por altura (valla/saltar, losa/agacharse, bloque/carril), interpolación de carriles, parábola del salto, dive, gestos de swipe, **spawn con siempre un carril libre**, morir sin diamantes |
| `coins_powerups_test.dart` | Patrones de monedas (cabece, dibujo, recolección en piso/altas), estado de power-ups (escudo una vez, timers, `reset`), imán, spawns nunca sobre obstáculos |
| `game_over_test.dart` | Récord que sobrevive a reinicios, `finishRun` idempotente, `collectDiamond`/`resetRun`, overlay y chip de récord |
| `juice_test.dart` | Unidades (anillos, chispas con gravedad, etiquetas, shake, destellos), integración en partida y **tests de píxeles** (viñeta, "+1") |
| `game_smoke_test.dart` | Corre ~1.5 s, dibuja el mapa, spawnea obstáculos, no muere, `restartRun` deja score 0 |
| `gameplay_render_test.dart` | Cada moneda/power-up aporta píxeles; el temblor máximo no descubre el borde (overscan) |
| `map_props_test.dart` | Props en ambos lados, no pisan el asfalto, avance/reciclaje/orden |
| `desert_look_test.dart` | **Píxel a píxel**: asfalto más oscuro que arena, divisorias discontinuas, props fuera del asfalto, tema oscuro opaco |
| `widget_test.dart` | `GameHeader` muestra `braian_123`, `score: 0`, `85` diamantes, chip `BASIC` |
| `map_preview_test.dart` | Genera `build/map_preview_{dark,light}.png` |
| `gameplay_preview_test.dart` | Genera `build/gameplay_preview_{dark,light,death}.png` |

---

## 8. Plataformas y configuración

**Targets** (los 6 estándar de Flutter): `android/`, `ios/`, `web/`, `linux/`,
`macos/`, `windows/`.

### Android

- `namespace` / `applicationId`: `com.example.endless_runner` *(TODO: cambiar)*.
- JVM 17; `compileSdk`/`minSdk`/`targetSdk`/`versionCode`/`versionName` →
  los que inyecta Flutter.
- Release firmado con claves **debug** *(TODO: claves propias)*.
- `AndroidManifest`: **sin permisos declarados** (no hay INTERNET ni otros),
  label `endless_runner`, `MainActivity` `singleTop` + `hardwareAccelerated`.
- No hay configuración de anuncios ni de compras reales: todo es simulado en
  UI.

### iOS

- `CFBundleDisplayName`: `Endless Runner`.
- `CADisableMinimumFrameDurationOnPhone = true` (120 Hz).
- Orientaciones: portrait + landscape en iPhone, las 4 en iPad.
- Sin claves `NS*UsageDescription` (no usa cámara/mic/etc.).

### Web / escritorio

- `web/`: `flutter_bootstrap.js`, manifest `endless_runner`, icons 192/512 +
  maskable + favicon.
- `linux/` (CMake), `macos/` (entitlements), `windows/` (runner CMake).

### Análisis

`analysis_options.yaml`: `include: package:flutter_lints/flutter.yaml` y
`analyzer.exclude` sobre `build/` y las carpetas de plataformas. Sin reglas
extra.

---

## 9. Cómo correr el proyecto

```bash
# 1. Dependencias
flutter pub get

# 2. Correr (con dispositivo/emulador conectado o en web/desktop)
flutter run

# 3. Tests (~60)
flutter test

# 4. Lint
flutter analyze
```

- Los **tests de preview** escriben PNGs en `build/`:
  `map_preview_{dark,light}.png`, `gameplay_preview_{dark,light,death}.png`.
- Repo git: la raíz está en el workspace padre (`tp2_gameAppHibrida`), no en
  `endless_runner/`.

---

## Resumen rápido de mecánicas

- **3 carriles** (−1/0/1) fijos en profundidad; X proyectada por perspectiva.
- **Gestos**: swipe ←/→ carril, ↑ salto, ↓ agacharse (umbral 22 px, una
  acción por gesto).
- **Obstáculos**: valla → saltar · losa → agacharse · bloque → cambiar de
  carril. El spawn **siempre deja un carril libre**.
- **Monedas = diamantes**: 4 patrones en tandas validadas contra obstáculos.
- **Power-ups**: escudo (1 golpe), imán (6 s), multiplicador ×2 (8 s), con
  HUD propio sobre el canvas.
- **Economía simulada**: 85 diamantes, golpe = 10 diamantes o game over,
  tienda de packs, anuncio de 3 s antes de cada reinicio, récord en memoria.
- **Juice**: shake (máx. 12 px), chispas, anillos, "+1", destellos, polvo al
  aterrizar y gracia de 1.05 s de muerte antes de pausar.
- **Tema**: claro (desierto de día) / oscuro (desierto nocturno estrellado).
