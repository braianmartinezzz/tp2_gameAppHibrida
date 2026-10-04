"""Arma el atlas del corredor (`player_atlas.png`) a partir de la hoja original.

Qué hace:
  1. Limpia los 8 cuadros de carrera (sin número ni sombra) y los alinea.
  2. Separa cada cuadro en dos capas por color: "arriba" (pelo, cabeza, buzo,
     brazos, mochila) y "piernas" (pantalón y botas).
  3. Con esas capas compone poses nuevas de SALTO y de AGACHADO, deformando y
     moviendo cada capa por separado (estirar, achicar, abrir, bajar).

No inventa dibujo nuevo: todo sale de píxeles de la hoja original, así el
personaje es el mismo. Correr:  python3 tools/build_player_atlas.py
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from extract_run_frames import CELL_H, CELL_W, FEET_Y, load_frames, normalize  # noqa: E402

OUT = 'assets/images/character/player_atlas.png'
HIP = (CELL_W / 2, 112.0)           # pivote entre arriba y piernas
PALETTE = {                         # clase -> color de referencia
    'orange': (240, 160, 20), 'red': (125, 35, 35), 'skin': (240, 190, 150),
    'hair': (120, 70, 30), 'pants': (25, 25, 28), 'boot': (125, 85, 55),
    'sole': (160, 150, 140),
}
LEGS = {'pants', 'boot', 'sole'}


def split_layers(cell):
    """(cabeza, torso, piernas, y_del_cuello) con capas RGBA del tamaño de la celda."""
    a = np.array(cell)
    rgb = a[..., :3].astype(float)
    names = list(PALETTE)
    ref = np.array([PALETTE[n] for n in names], float)
    dist = ((rgb[:, :, None, :] - ref[None, None]) ** 2).sum(axis=3)
    cls = dist.argmin(axis=2)
    yy = np.arange(a.shape[0])[:, None] * np.ones((1, a.shape[1]))
    legs = np.zeros(a.shape[:2], bool)
    for i, n in enumerate(names):
        if n in LEGS:
            legs |= (cls == i)
    # el marrón del pelo y el de las botas se parecen: lo decide la altura
    hair = cls == names.index('hair')
    boot = cls == names.index('boot')
    legs = (legs & ~(boot & (yy < 128))) | (hair & (yy > 140))
    # el pantalón nunca está por encima del pecho (negro del pelo/mochila)
    legs &= yy > 96
    orange = cls == names.index('orange')
    neck = int(np.where(orange.any(axis=1))[0].min()) + 2   # donde empieza el buzo
    solid = a[..., 3] > 0
    head_m = solid & ~legs & (yy < neck)
    torso_m = solid & ~legs & (yy >= neck)
    legs_m = solid & legs
    out = []
    for m in (head_m, torso_m, legs_m):
        layer = np.zeros_like(a)
        layer[m] = a[m]
        out.append(Image.fromarray(layer))
    return out[0], out[1], out[2], neck


def xform(layer, pivot, sx=1.0, sy=1.0, dx=0.0, dy=0.0, rot=0.0, flip=False):
    """Escala/rota alrededor de [pivot] y mueve (dx, dy). Opcional espejo."""
    if flip:
        layer = layer.transpose(Image.FLIP_LEFT_RIGHT)
        pivot = (CELL_W - pivot[0], pivot[1])
    px, py = pivot
    c, s = math.cos(rot), math.sin(rot)
    # directa: p' = R*S*(p - pivot) + pivot + d
    f = np.array([[c * sx, -s * sy], [s * sx, c * sy]])
    inv = np.linalg.inv(f)
    off = np.array([px, py]) + np.array([dx, dy])
    b = np.array([px, py]) - inv @ off
    return layer.transform(
        layer.size, Image.AFFINE,
        (inv[0, 0], inv[0, 1], b[0], inv[1, 0], inv[1, 1], b[1]),
        resample=Image.BICUBIC)


def compose(parts, head=None, torso=None, legs=None, whole=None):
    """parts = (cabeza, torso, piernas, cuello). Cada capa se mueve por separado."""
    h_l, t_l, l_l, neck = parts
    head, torso, legs = head or {}, torso or {}, legs or {}
    cell = Image.new('RGBA', (CELL_W, CELL_H), (0, 0, 0, 0))
    cell.alpha_composite(xform(l_l, (CELL_W / 2, 112.0), **legs))
    cell.alpha_composite(xform(t_l, (CELL_W / 2, float(neck)), **torso))
    cell.alpha_composite(xform(h_l, (CELL_W / 2, float(neck)), **head))
    if whole:
        cell = xform(cell, (CELL_W / 2, FEET_Y), **whole)
    return cell


def feet_dy(sy):
    """dy que mantiene los pies en el suelo cuando las piernas se escalan sy."""
    return (FEET_Y - 112.0) * (1 - sy)


def build():
    run = normalize(load_frames())
    P = [split_layers(c) for c in run]

    poses = {}
    # --- Salto ------------------------------------------------------------
    # agachada previa al despegue (se usa un instante)
    poses['jump_crouch'] = compose(P[0], head=dict(dy=14), torso=dict(sy=0.9, dy=13),
                                   legs=dict(sy=0.8, dy=feet_dy(0.8)))
    # subiendo: cuerpo estirado, una rodilla levantada, la otra extendida
    poses['jump_rise'] = compose(P[1], head=dict(dy=-5), torso=dict(sy=1.04, dy=-4),
                                 legs=dict(sy=0.92, dy=-6))
    # punto más alto: piernas recogidas, abiertas y más cortas
    poses['jump_apex'] = compose(P[2], head=dict(dy=-2), torso=dict(dy=-2),
                                 legs=dict(sy=0.74, sx=1.12, dy=-14))
    # cayendo: las piernas se estiran hacia el suelo
    poses['jump_fall'] = compose(P[6], head=dict(dy=1), torso=dict(sy=0.98, dy=1),
                                 legs=dict(sy=1.05, dy=feet_dy(1.05)))
    # aterrizaje: aplastado, rodillas flexionadas
    poses['land'] = compose(P[0], head=dict(dy=24), torso=dict(sy=0.8, sx=1.06, dy=23),
                            legs=dict(sy=0.62, sx=1.14, dy=feet_dy(0.62)))

    # --- Agachado / deslizamiento -------------------------------------------
    # Postura de cuclillas vista de espaldas: la cabeza conserva su tamaño (si
    # se aplastara todo parecería un hongo), el torso se acorta y se inclina
    # hacia adelante, las piernas se pliegan y abren las rodillas.
    def slide(head_s, torso_s, legs_s, tilt=0.0, bob=0.0):
        legs_top = 112.0 + (FEET_Y - 112.0) * (1 - legs_s) - (FEET_Y - 112.0) * 0  # = tope del pantalón
        torso_h = 53.0 * torso_s                 # el buzo mide ~53 px de celda
        neck_new = legs_top - torso_h + 4        # el torso apoya sobre las piernas
        head_dy = neck_new - 71.0                # el cuello original está en ~y71
        return compose(
            P[0],
            head=dict(dy=head_dy + bob, sx=head_s, sy=head_s),
            torso=dict(sy=torso_s, sx=1.0, dy=head_dy + bob, rot=tilt),
            legs=dict(sy=legs_s, sx=1.2, dy=feet_dy(legs_s)),
        )
    poses['slide_in'] = slide(0.95, 0.62, 0.45)
    poses['slide_a'] = slide(0.86, 0.34, 0.24, tilt=0.05)
    poses['slide_b'] = slide(0.86, 0.34, 0.24, tilt=-0.05, bob=1.5)
    poses['slide_out'] = slide(0.95, 0.72, 0.55)

    order = (
        [f'run_{i}' for i in range(8)]
        + ['jump_crouch', 'jump_rise', 'jump_apex', 'jump_fall', 'land']
        + ['slide_in', 'slide_a', 'slide_b', 'slide_out']
    )
    frames = {f'run_{i}': c for i, c in enumerate(run)}
    frames.update(poses)
    return order, frames


if __name__ == '__main__':
    order, frames = build()
    cols = 8
    rows = math.ceil(len(order) / cols)
    sheet = Image.new('RGBA', (CELL_W * cols, CELL_H * rows), (0, 0, 0, 0))
    for i, name in enumerate(order):
        sheet.paste(frames[name], ((i % cols) * CELL_W, (i // cols) * CELL_H))
    sheet.save(OUT)
    print('atlas', sheet.size, 'cols', cols, 'rows', rows, 'frames', len(order))
    print(order)
    bg = Image.new('RGBA', sheet.size, (70, 78, 98, 255))
    bg.alpha_composite(sheet)
    bg.convert('RGB').save('/tmp/atlas_preview.png')
