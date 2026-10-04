"""Etapa 1 del atlas del corredor: limpia la hoja original.

La hoja `sprites_corredor.png` trae, en cada cuadro, el número del cuadro y una
sombra gris pintada (que viajaba con el personaje al saltar). Acá se los saca y
se alinean los 8 cuadros de carrera (pies abajo, cabeza centrada, misma escala).
"""
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

SRC = 'assets/images/character/sprites_corredor.png'
CELL_W, CELL_H = 192, 192
FEET_Y = 186          # fila de los pies dentro de la celda
STAND_H = 150         # alto del personaje parado dentro de la celda


def load_frames():
    a = np.array(Image.open(SRC).convert('RGBA'))
    lab, n = ndi.label(a[..., 3] > 40)
    comps = []
    for i in range(1, n + 1):
        ys, xs = np.where(lab == i)
        if len(ys) > 20000:                       # personaje (+ sombra pegada)
            comps.append((ys.min(), xs.min(), ys.max(), xs.max(), i))
    # orden de lectura: fila de arriba primero, de izquierda a derecha
    top_row = [c for c in comps if c[0] < a.shape[0] * 0.35]
    bot_row = [c for c in comps if c[0] >= a.shape[0] * 0.35]
    comps = sorted(top_row, key=lambda c: c[1]) + sorted(bot_row, key=lambda c: c[1])
    assert len(comps) == 8, len(comps)

    frames = []
    for y0, x0, y1, x1, i in comps:
        pad = 6
        crop = a[max(0, y0 - pad):y1 + pad, max(0, x0 - pad):x1 + pad].copy()
        mine = (lab[max(0, y0 - pad):y1 + pad, max(0, x0 - pad):x1 + pad] == i)
        crop[~mine] = 0                            # solo este personaje
        frames.append(clean(crop))
    return frames


def clean(img):
    """Saca la sombra gris translúcida y deja el personaje."""
    rgb = img[..., :3].astype(int)
    al = img[..., 3]
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    shadow = (al > 0) & (al < 215) & (sat < 25)    # gris con alpha parcial
    solid = (al >= 215) & ~shadow
    near_solid = ndi.binary_dilation(solid, iterations=1)
    drop = shadow & ~near_solid                    # conserva el borde suave
    out = img.copy()
    out[drop, 3] = 0
    # restos sueltos (motas de la sombra): quedarse con el componente grande
    lab, n = ndi.label(out[..., 3] > 40)
    if n > 1:
        sizes = ndi.sum(np.ones_like(lab), lab, range(1, n + 1))
        keep = 1 + int(np.argmax(sizes))
        out[lab != keep, 3] = 0
    return out


def bbox(img):
    ys, xs = np.where(img[..., 3] > 40)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def head_center_x(img):
    x0, y0, x1, y1 = bbox(img)
    band = img[y0:y0 + int((y1 - y0) * 0.14), :, 3] > 40
    xs = np.where(band.any(axis=0))[0]
    return (xs.min() + xs.max()) / 2


def normalize(frames):
    heights = [bbox(f)[3] - bbox(f)[1] for f in frames]
    scale = STAND_H / float(np.median(heights))
    cells = []
    for f in frames:
        x0, y0, x1, y1 = bbox(f)
        hx = head_center_x(f)
        im = Image.fromarray(f[y0:y1])
        w, h = im.size
        sw, sh = max(1, round(w * scale)), max(1, round(h * scale))
        im = im.resize((sw, sh), Image.LANCZOS)
        cell = Image.new('RGBA', (CELL_W, CELL_H), (0, 0, 0, 0))
        px = round(CELL_W / 2 - (hx - x0) * scale)
        py = FEET_Y - sh
        cell.alpha_composite(im, (px, py))
        cells.append(cell)
    return cells


if __name__ == '__main__':
    cells = normalize(load_frames())
    sheet = Image.new('RGBA', (CELL_W * 8, CELL_H), (0, 0, 0, 0))
    for i, c in enumerate(cells):
        sheet.paste(c, (i * CELL_W, 0))
    sheet.save('/tmp/run_frames.png')
    bg = Image.new('RGBA', sheet.size, (70, 78, 98, 255))
    bg.alpha_composite(sheet)
    bg.convert('RGB').save('/tmp/run_frames_preview.png')
    print('ok', sheet.size)
