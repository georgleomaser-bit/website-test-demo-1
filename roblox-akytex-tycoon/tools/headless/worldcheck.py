#!/usr/bin/env python3
# =====================================================================
#  AKYTEX TYCOON – Headless-Harness: automatische Geometrie-Prüfungen auf world.json
#
#  python3 tools/headless/worldcheck.py [WORLD_JSON] [--out DATEI] [--json DATEI] [--max N]
#      WORLD_JSON  Standard: tools/headless/out/world/world.json (vom Szenario "world")
#      --out       Standard: neben world.json als worldcheck.txt (lesbar)
#      --json      Standard: neben world.json als worldcheck.json (für den Renderer: Markierungen)
#
#  Prüfungen (alle Teile mit Pfad, gruppiert nach Modell-Pfad-Präfix, größte Gruppen zuerst):
#    (a) unverankerte Teile ohne Schweißnaht-/Constraint-Kette zu einem verankerten Teil (fallen/zerstreuen sich in
#        echtem Roblox); Figuren (Humanoid) und Fahrzeuge (VehicleSeat) gelten als gewollte Physik-Baugruppen
#    (b) Z-Fighting: gleichgerichtete, koplanare (±0,01 Stud) und überlappende Flächen verschiedener sichtbarer Teile
#        (Paare + Fläche in Stud²)
#    (c) tiefe Durchdringung fester Teile verschiedener Modelle (Gebäude in Straßen, Requisiten in Wänden), gruppiert
#    (d) schwebende verankerte Teile/Baugruppen: kein Kontakt zu Gelände oder anderen Teilen; gewollt schwebende
#        Dinge (Neon, Lichter, Schilder an Wänden, Himmels-Deko …) per Heuristik getrennt aufgelistet
#    (e) Teile unter dem Boden: komplett im Gelände vergraben (unsichtbar, kosten Budget) und unter Y = 0 sichtbar
#        an Stellen ohne Gelände
#    (f) Ausreißer: winzige/riesige Teile, NaN-CFrames, schiefe Rotationsmatrizen, Teile weit außerhalb der Karte
#    (g) Teile-/Licht-Budgets je Bereich gegen docs/DESIGN.md §C16
#
#  Geometrie: Teile als orientierte Quader (Wedge/Zylinder/Kugel für Flächen und Punkt-Tests genau, MeshPart/
#  SpecialMesh nur als Hüllquader). Gelände aus den Terrain-Formen + Voxel-Säulen des Dumps (4-Stud-Auflösung).
#  Client-Teile (src "c") werden je Phase (lobby/floor6 …) zusammen mit der Server-Welt geprüft, nie phasenübergreifend.
# =====================================================================
import argparse
import collections
import json
import math
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_WORLD = os.path.join(HERE, "out", "world", "world.json")

# Schwellen (Studs)
ZF_PLANE_TOL = 0.01  # koplanar
ZF_MIN_AREA = 0.02  # Stud² Mindest-Überlappung für Z-Fighting
TOUCH_TOL = 0.05  # Kontakt (Abstand) für Stütz-Graph
DEEP_DEPTH = 0.5  # Mindest-Eindringtiefe für (c)
DEEP_FRAC = 0.25  # Mindest-Anteil des kleineren Teils im anderen für (c)
GROUND_TOL = 0.15  # Kontakt zum Gelände (glatte Formen)
VOXEL_TOL = 2.5  # Kontakt zum Gelände über Voxel-Säulen (4-Stud-Raster, geglättet)
MAP_HALF = 1024

INTENTIONAL_FLOAT = re.compile(
    r"(Light|Lamp|Lantern|Laterne|Neon|Sign|Schild|Logo|Letter|Holo|Beam|Sky|Cloud|Blimp|Halo|Glow|Ring|Banner|"
    r"Billboard|Drone|Crown|Beacon|Star|Spot|Ticker|Screen|Board|Tiko|Arrow|Strip|Line|Band|Crane|Hook|Marker|"
    r"Anchor|Glas|Glass|Window|Fenster|Panel|Display|Monitor|Canopy|Visor|Eye|Antenna|Tip|Orb|Aurora|Firework|"
    r"Confetti|Spark|Bulb|Head|Ticker|Label|Text|Plate|Number|Arch|Bridge|Rail|Cable|Wire|Kerb|Stripe)",
    re.I,
)
PIER_NAMES = re.compile(r"(Pier|Pillar|Pfeiler|Pile|Post|Column|Leg|Foundation|Fundament|Footing|Support)", re.I)


# ---------------------------------------------------------------------------------------------
#  Laden
# ---------------------------------------------------------------------------------------------
class World:
    def __init__(self, path):
        with open(path, encoding="utf-8") as f:
            self.w = json.load(f)
        w = self.w
        self.meta = w.get("meta", {})
        self.parts = w["parts"]
        self.models = {m["i"]: m for m in w.get("models", [])}
        self.n = len(self.parts)
        n = self.n
        self.pos = np.zeros((n, 3))
        self.R = np.zeros((n, 3, 3))
        self.size = np.zeros((n, 3))
        self.nan = np.zeros(n, bool)
        for k, p in enumerate(self.parts):
            cf = p["cf"]
            if p.get("nan") or any(v is None for v in cf):
                self.nan[k] = True
                self.R[k] = np.eye(3)
                continue
            self.pos[k] = cf[0:3]
            self.R[k] = np.array(cf[3:12]).reshape(3, 3)
            self.size[k] = p["s"]
        # Achsen als Zeilen: AX[n][k] = Weltrichtung der lokalen Achse k = Spalte k von R
        self.AX = np.transpose(self.R, (0, 2, 1))
        self.half = self.size / 2.0
        self.shape = [p.get("sh", "Block") for p in self.parts]
        # Kugel/Zylinder: Roblox rendert mit der kleinsten Achse (Kugel) bzw. min(Y, Z) als Durchmesser
        for k, sh in enumerate(self.shape):
            if sh == "Ball":
                r = self.half[k].min()
                self.half[k] = [r, r, r]
            elif sh == "Cylinder":
                r = min(self.half[k][1], self.half[k][2])
                self.half[k][1] = r
                self.half[k][2] = r
        absR = np.abs(self.R)
        ext = np.einsum("nij,nj->ni", absR, self.half)
        self.lo = self.pos - ext
        self.hi = self.pos + ext
        self.src = np.array([p.get("src", "s") for p in self.parts])
        self.phase = [p.get("ph") for p in self.parts]
        self.trans = np.array([p.get("t", 0) for p in self.parts], float)
        self.anch = np.array([p.get("a", 0) == 1 for p in self.parts])
        self.coll = np.array([p.get("cc", 0) == 1 for p in self.parts])
        self.mat = [p.get("m", "Plastic") for p in self.parts]
        self.path = [p["p"] for p in self.parts]
        self.name = [p["p"].rsplit(".", 1)[-1] for p in self.parts]
        self.md = [p.get("md") for p in self.parts]
        self.idx = {p["i"]: k for k, p in enumerate(self.parts)}
        # Figuren (Modell mit Humanoid, auch verschachtelt)
        self.hum = np.zeros(n, bool)
        for k, p in enumerate(self.parts):
            m = p.get("md")
            seen = 0
            while m is not None and seen < 20:
                mm = self.models.get(m)
                if mm is None:
                    break
                if mm.get("hum"):
                    self.hum[k] = True
                    break
                m = mm.get("up")
                seen += 1
        # Mesh: Sphere/FileMesh = gekrümmte/unbekannte Oberfläche
        self.meshKind = [(p.get("mesh") or {}).get("t") for p in self.parts]
        self.lightsByPart = collections.defaultdict(list)
        for l in w.get("lights", []):
            if l.get("pi"):
                self.lightsByPart[l["pi"]].append(l)
        self.guisByPart = collections.defaultdict(list)
        for g in w.get("guis", []):
            if g.get("pi"):
                self.guisByPart[g["pi"]].append(g)
        self.visible = (self.trans < 0.98) & ~self.nan
        self.terrain = Terrain(w.get("terrain", {}))

    def scene_ok(self, i, j):
        """Paar gehört zu einer gemeinsamen Szene (Server + höchstens eine Client-Phase)"""
        si, sj = self.src[i], self.src[j]
        if si == "s" or sj == "s":
            return True
        return self.phase[i] == self.phase[j]

    def where(self, k):
        x, y, z = self.pos[k]
        return "(%.1f, %.1f, %.1f)" % (x, y, z)

    def label(self, k):
        p = self.parts[k]
        ph = (" [Client %s]" % p.get("ph")) if p.get("src") == "c" else ""
        return "%s%s" % (p["p"], ph)


def prefix_of(path, depth=4):
    parts = path.split(".")
    # Plot-Türme: Workspace.AkyTowers.Plot1.Tower.Floors.F3 -> bis Tower
    return ".".join(parts[:depth])


# ---------------------------------------------------------------------------------------------
#  Gelände (Säulen-Modell: feste Intervalle je (x, z) aus Formen in Schreibreihenfolge + Voxel)
# ---------------------------------------------------------------------------------------------
def _sub(intervals, a, b):
    out = []
    for (x, y) in intervals:
        if y <= a or x >= b:
            out.append((x, y))
        else:
            if x < a:
                out.append((x, a))
            if y > b:
                out.append((b, y))
    return out


def _add(intervals, a, b):
    out = []
    for (x, y) in sorted(intervals + [(a, b)]):
        if out and x <= out[-1][1] + 1e-9:
            out[-1] = (out[-1][0], max(out[-1][1], y))
        else:
            out.append((x, y))
    return out


class Terrain:
    def __init__(self, t):
        self.shapes = []
        for sh in t.get("shapes", []):
            k = sh.get("k")
            if k in ("box", "wedge"):
                cf = sh["cf"]
                if any(v is None for v in cf):
                    continue
                self.shapes.append(("box", np.array(cf[0:3]), np.array(cf[3:12]).reshape(3, 3), np.array(sh["s"]) / 2, sh["m"]))
            elif k == "cyl":
                cf = sh["cf"]
                self.shapes.append(("cyl", np.array(cf[0:3]), np.array(cf[3:12]).reshape(3, 3), (sh["h"] / 2, sh["r"]), sh["m"]))
            elif k == "ball":
                self.shapes.append(("ball", np.array(sh["c"]), None, sh["r"], sh["m"]))
        self.cols = {}
        vox = t.get("voxels", {}).get("cols", [])
        for c in vox:
            x0, z0, runs, airs, mat = c
            self.cols[(int(x0), int(z0))] = ([tuple(r) for r in runs], [tuple(a) for a in airs], mat)
        self.cache = {}

    def column(self, x, z):
        """(feste Intervalle, Wasser-Intervalle, ist_voxel) an (x, z)"""
        key = (round(x * 2) / 2, round(z * 2) / 2)
        hit = self.cache.get(key)
        if hit is not None:
            return hit
        solid, water = [], []
        for kind, c, Rm, h, mat in self.shapes:
            if kind == "box":
                # nur achsparallele (bzw. um Y gedrehte) Blöcke: lokale x/z prüfen
                d = np.array([x - c[0], 0.0, z - c[2]])
                lx = Rm[0, 0] * d[0] + Rm[1, 0] * d[1] + Rm[2, 0] * d[2]
                lz = Rm[0, 2] * d[0] + Rm[1, 2] * d[1] + Rm[2, 2] * d[2]
                if abs(lx) > h[0] or abs(lz) > h[2]:
                    continue
                a, b = c[1] - h[1], c[1] + h[1]
            elif kind == "cyl":
                hh, r = h
                if (x - c[0]) ** 2 + (z - c[2]) ** 2 > r * r:
                    continue
                a, b = c[1] - hh, c[1] + hh
            else:
                r = h
                dd = r * r - (x - c[0]) ** 2 - (z - c[2]) ** 2
                if dd < 0:
                    continue
                s = math.sqrt(dd)
                a, b = c[1] - s, c[1] + s
            if mat == "Air":
                solid = _sub(solid, a, b)
                water = _sub(water, a, b)
            elif mat == "Water":
                solid = _sub(solid, a, b)
                water = _add(water, a, b)
            else:
                solid = _add(solid, a, b)
                water = _sub(water, a, b)
        isvox = False
        col = self.cols.get((int(math.floor(x / 4) * 4), int(math.floor(z / 4) * 4)))
        if col:
            runs, airs, _mat = col
            for a, b in airs:
                solid = _sub(solid, a, b)
            for a, b in runs:
                solid = _add(solid, a, b)
                isvox = True
        res = (solid, water, isvox)
        self.cache[key] = res
        return res

    def top(self, x, z):
        solid, _w, _v = self.column(x, z)
        return max((b for _a, b in solid), default=-1e9)

    def contact(self, x, z, ybot, ytop):
        """Berührt/steckt der Bereich [ybot, ytop] an (x, z) im Gelände? -> (Kontakt, Abstand nach unten, voxel)"""
        solid, water, isvox = self.column(x, z)
        tol = VOXEL_TOL if isvox else GROUND_TOL
        best_gap = None
        for a, b in solid:
            if ybot <= b + tol and ytop >= a - tol:
                return True, 0.0, isvox
            if b <= ybot:
                g = ybot - b
                best_gap = g if best_gap is None else min(best_gap, g)
        return False, best_gap, isvox

    def water_at(self, x, z, y, tol=1.0):
        _s, water, _v = self.column(x, z)
        for a, b in water:
            if a - tol <= y <= b + tol:
                return True
        return False


# ---------------------------------------------------------------------------------------------
#  Kandidaten-Paare (Sweep über x) + SAT
# ---------------------------------------------------------------------------------------------
def candidate_pairs(W, mask, tol):
    ids = np.nonzero(mask)[0]
    if len(ids) == 0:
        return np.zeros((0, 2), int)
    lo, hi = W.lo[ids] - tol, W.hi[ids] + tol
    order = np.argsort(lo[:, 0])
    ids, lo, hi = ids[order], lo[order], hi[order]
    xs = lo[:, 0]
    I, J = [], []
    for a in range(len(ids)):
        end = np.searchsorted(xs, hi[a, 0], side="right")
        if end <= a + 1:
            continue
        b = np.arange(a + 1, end)
        ok = (lo[b, 1] <= hi[a, 1]) & (hi[b, 1] >= lo[a, 1]) & (lo[b, 2] <= hi[a, 2]) & (hi[b, 2] >= lo[a, 2])
        b = b[ok]
        if len(b):
            I.append(np.full(len(b), ids[a]))
            J.append(ids[b])
    if not I:
        return np.zeros((0, 2), int)
    P = np.stack([np.concatenate(I), np.concatenate(J)], axis=1)
    # Szenen-Regel (Client-Phasen nicht mischen)
    keep = np.array([W.scene_ok(i, j) for i, j in P], bool)
    return P[keep]


def sat_gap(W, P):
    """größte Trennlücke über 15 SAT-Achsen je Paar (>0 getrennt, <0 = -Eindringtiefe)"""
    if len(P) == 0:
        return np.zeros(0)
    I, J = P[:, 0], P[:, 1]
    A, B = W.AX[I], W.AX[J]
    hA, hB = W.half[I], W.half[J]
    T = W.pos[J] - W.pos[I]
    axes = [A[:, k] for k in range(3)] + [B[:, k] for k in range(3)]
    for i in range(3):
        for j in range(3):
            axes.append(np.cross(A[:, i], B[:, j]))
    best = np.full(len(P), -np.inf)
    for L in axes:
        nrm = np.linalg.norm(L, axis=1)
        valid = nrm > 1e-6
        Ln = np.where(valid[:, None], L / np.where(valid, nrm, 1)[:, None], 0)
        rA = np.sum(np.abs(np.einsum("pi,pki->pk", Ln, A)) * hA, axis=1)
        rB = np.sum(np.abs(np.einsum("pi,pki->pk", Ln, B)) * hB, axis=1)
        dist = np.abs(np.einsum("pi,pi->p", Ln, T))
        gap = dist - rA - rB
        gap = np.where(valid, gap, -np.inf)
        best = np.maximum(best, gap)
    return best


# ---------------------------------------------------------------------------------------------
#  Form-Tests (lokale Koordinaten)
# ---------------------------------------------------------------------------------------------
def inside_local(shape, h, L):
    """L: (n,3) lokale Punkte -> bool (n,)"""
    hx, hy, hz = h
    x, y, z = L[:, 0], L[:, 1], L[:, 2]
    box = (np.abs(x) <= hx + 1e-6) & (np.abs(y) <= hy + 1e-6) & (np.abs(z) <= hz + 1e-6)
    if shape == "Wedge":
        return box & (y * hz <= z * hy + 1e-6)
    if shape == "CornerWedge":
        # Näherung: Spitze bei (+hx, +hy, -hz)
        return box & ((y + hy) / (2 * hy) <= np.minimum((x + hx) / (2 * hx), (hz - z) / (2 * hz)) + 1e-6)
    if shape == "Cylinder":
        return (np.abs(x) <= hx) & (y * y + z * z <= hy * hy)
    if shape == "Ball":
        return x * x + y * y + z * z <= hx * hx
    return box


def sample_points(W, k, n=6):
    """Punkte im Inneren von Teil k (Weltkoordinaten)"""
    g = (np.arange(n) + 0.5) / n * 2 - 1
    X, Y, Z = np.meshgrid(g, g, g, indexing="ij")
    L = np.stack([X.ravel(), Y.ravel(), Z.ravel()], axis=1) * W.half[k]
    L = L[inside_local(W.shape[k], W.half[k], L)]
    return W.pos[k] + L @ W.R[k].T


def overlap_fraction(W, a, b):
    """Anteil des Volumens von a, der in b liegt (Stichprobe)"""
    pts = sample_points(W, a)
    if len(pts) == 0:
        return 0.0
    L = (pts - W.pos[b]) @ W.R[b]
    return float(np.mean(inside_local(W.shape[b], W.half[b], L)))


def volume(W, k):
    s = W.size[k]
    v = s[0] * s[1] * s[2]
    sh = W.shape[k]
    if sh == "Wedge":
        v /= 2
    elif sh == "CornerWedge":
        v /= 3
    elif sh == "Cylinder":
        v = math.pi * W.half[k][1] ** 2 * s[0]
    elif sh == "Ball":
        v = 4 / 3 * math.pi * W.half[k][0] ** 3
    return v


# ---------------------------------------------------------------------------------------------
#  Flächen (für Z-Fighting)
# ---------------------------------------------------------------------------------------------
def local_faces(shape, h):
    hx, hy, hz = h
    if shape in ("Block", "Union", "Truss") or shape is None:
        f = []
        for ax in range(3):
            for s in (-1, 1):
                n = np.zeros(3)
                n[ax] = s
                u = (ax + 1) % 3
                v = (ax + 2) % 3
                verts = []
                for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                    p = np.zeros(3)
                    p[ax] = s * h[ax]
                    p[u] = a * h[u]
                    p[v] = b * h[v]
                    verts.append(p)
                f.append((n, np.array(verts)))
        return f
    if shape == "Wedge":
        V = lambda x, y, z: np.array([x, y, z], float)  # noqa: E731
        f = [
            (V(0, -1, 0), np.array([V(-hx, -hy, -hz), V(hx, -hy, -hz), V(hx, -hy, hz), V(-hx, -hy, hz)])),
            (V(0, 0, 1), np.array([V(-hx, -hy, hz), V(hx, -hy, hz), V(hx, hy, hz), V(-hx, hy, hz)])),
            (V(1, 0, 0), np.array([V(hx, -hy, -hz), V(hx, -hy, hz), V(hx, hy, hz)])),
            (V(-1, 0, 0), np.array([V(-hx, -hy, -hz), V(-hx, hy, hz), V(-hx, -hy, hz)])),
        ]
        n = np.array([0, hz, -hy], float)
        n /= np.linalg.norm(n)
        f.append((n, np.array([V(-hx, -hy, -hz), V(hx, -hy, -hz), V(hx, hy, hz), V(-hx, hy, hz)])))
        return f
    if shape == "Cylinder":
        f = []
        r = hy
        ang = np.linspace(0, 2 * np.pi, 17)[:-1]
        for s in (-1, 1):
            verts = np.stack([np.full(16, s * hx), r * np.cos(ang), r * np.sin(ang)], axis=1)
            f.append((np.array([s, 0, 0], float), verts))
        return f
    return []  # Kugel, Mesh: keine ebenen Flächen


def world_faces(W, k):
    p = W.parts[k]
    sh = W.shape[k]
    mk = W.meshKind[k]
    if sh == "Mesh" or mk in ("Sphere", "FileMesh", "Head", "Cylinder", "Torso", "Wedge", "CornerWedge"):
        return []
    h = W.half[k].copy()
    off = np.zeros(3)
    if mk in ("Brick", "BlockMesh"):
        m = p.get("mesh") or {}
        sc = np.array(m.get("sc") or [1, 1, 1], float)
        h = h * sc
        off = np.array(m.get("off") or [0, 0, 0], float)
        sh = "Block"
    out = []
    for n, verts in local_faces(sh, h):
        wn = W.R[k] @ n
        wv = (verts + off) @ W.R[k].T + W.pos[k]
        out.append((wn, float(wn @ wv[0]), wv))
    return out


def clip_poly(subject, clip):
    """Sutherland–Hodgman (2D, beide konvex, clip gegen den Uhrzeigersinn)"""
    out = subject
    n = len(clip)
    for i in range(n):
        if len(out) == 0:
            break
        a, b = clip[i], clip[(i + 1) % n]
        inp = out
        out = []
        ex, ey = b[0] - a[0], b[1] - a[1]

        def side(p):
            return ex * (p[1] - a[1]) - ey * (p[0] - a[0])

        for j in range(len(inp)):
            p, q = inp[j], inp[(j + 1) % len(inp)]
            sp, sq = side(p), side(q)
            if sp >= 0:
                out.append(p)
            if (sp >= 0) != (sq >= 0):
                t = sp / (sp - sq)
                out.append((p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1])))
    return out


def area2d(poly):
    s = 0.0
    for i in range(len(poly)):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % len(poly)]
        s += x1 * y2 - x2 * y1
    return s / 2


def coplanar_overlap(fa, fb):
    na, da, va = fa
    nb, db, vb = fb
    if na @ nb < 0.9995 or abs(da - db) > ZF_PLANE_TOL:
        return 0.0
    # 2D-Basis in der Ebene
    t = np.array([1.0, 0, 0]) if abs(na[0]) < 0.9 else np.array([0, 1.0, 0])
    u = np.cross(na, t)
    u /= np.linalg.norm(u)
    v = np.cross(na, u)
    pa = [(float(p @ u), float(p @ v)) for p in va]
    pb = [(float(p @ u), float(p @ v)) for p in vb]
    if area2d(pa) < 0:
        pa = pa[::-1]
    if area2d(pb) < 0:
        pb = pb[::-1]
    inter = clip_poly(pa, pb)
    if len(inter) < 3:
        return 0.0
    return abs(area2d(inter))


# ---------------------------------------------------------------------------------------------
#  Hilfen
# ---------------------------------------------------------------------------------------------
class UF:
    def __init__(self, n):
        self.p = list(range(n))

    def find(self, a):
        while self.p[a] != a:
            self.p[a] = self.p[self.p[a]]
            a = self.p[a]
        return a

    def union(self, a, b):
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self.p[ra] = rb


def footprint_points(W, k):
    lo, hi = W.lo[k], W.hi[k]
    cx, cz = (lo[0] + hi[0]) / 2, (lo[2] + hi[2]) / 2
    ex, ez = (hi[0] - lo[0]) / 2 * 0.8, (hi[2] - lo[2]) / 2 * 0.8
    return [(cx, cz), (cx - ex, cz - ez), (cx + ex, cz - ez), (cx - ex, cz + ez), (cx + ex, cz + ez)]


RIGID = {"Weld", "WeldConstraint", "Motor6D", "Motor", "Snap", "ManualWeld", "ManualGlue", "Glue", "RigidConstraint"}
NONPHYS = {"NoCollisionConstraint"}


# ---------------------------------------------------------------------------------------------
#  Prüfungen
# ---------------------------------------------------------------------------------------------
def check_unanchored(W, res):
    uf = UF(W.n)
    for j in W.w.get("joints", []):
        if j.get("e") != 1 or j.get("c") in NONPHYS:
            continue
        a, b = j.get("p0"), j.get("p1")
        if a in W.idx and b in W.idx:
            uf.union(W.idx[a], W.idx[b])
    comps = collections.defaultdict(list)
    for k in range(W.n):
        if not W.nan[k]:
            comps[uf.find(k)].append(k)
    findings = []
    for root, members in comps.items():
        if any(W.anch[m] for m in members):
            continue
        if any(W.hum[m] for m in members):
            continue
        vehicle = any(W.parts[m]["c"] == "VehicleSeat" for m in members)
        allNoColl = all(not W.coll[m] for m in members)
        k = min(members, key=lambda m: W.lo[m][1])
        # liegt die Baugruppe auf? (Gelände oder verankertes Teil direkt darunter)
        rest = False
        for (x, z) in footprint_points(W, k):
            c, gap, _v = W.terrain.contact(x, z, W.lo[k][1], W.hi[k][1])
            if c:
                rest = True
        findings.append({
            "members": members,
            "vehicle": vehicle,
            "noColl": allNoColl,
            "rest": rest,
            "k": k,
        })
    res["a"] = findings


def check_pairs(W, res):
    mask = ~W.nan & ~W.hum & W.visible
    P = candidate_pairs(W, mask, TOUCH_TOL)
    gap = sat_gap(W, P)
    res["pairs"] = (P, gap)
    # (b) Z-Fighting
    zf = []
    cand = P[gap <= ZF_PLANE_TOL]
    face_cache = {}

    def faces(k):
        f = face_cache.get(k)
        if f is None:
            f = world_faces(W, k)
            face_cache[k] = f
        return f

    for i, j in cand:
        fa, fb = faces(i), faces(j)
        if not fa or not fb:
            continue
        total = 0.0
        kinds = []
        for x in fa:
            for y in fb:
                a = coplanar_overlap(x, y)
                if a > 1e-6:
                    total += a
                    kinds.append(tuple(np.round(x[0], 2)))
        if total >= ZF_MIN_AREA:
            zf.append((int(i), int(j), total, kinds[0] if kinds else None))
    res["b"] = zf
    # (c) tiefe Durchdringung (verschiedene Modelle, beide fest)
    deep = []
    solid = (W.trans < 0.5)
    cand = P[gap <= -DEEP_DEPTH]
    cg = gap[gap <= -DEEP_DEPTH]
    for (i, j), g in zip(cand, cg):
        if not (solid[i] and solid[j]):
            continue
        same_model = W.md[i] is not None and W.md[i] == W.md[j]
        a, b = (i, j) if volume(W, i) <= volume(W, j) else (j, i)
        frac = overlap_fraction(W, a, b)
        if frac < DEEP_FRAC:
            continue
        deep.append((int(a), int(b), float(-g), frac, same_model))
    res["c"] = deep
    # Kontakt-Graph für (d)
    res["touch"] = P[gap <= TOUCH_TOL]


def classify_float(W, members):
    names = " ".join(W.name[m] for m in members)
    if all(W.mat[m] == "Neon" for m in members):
        return "Neon-Element"
    if any(W.lightsByPart.get(W.parts[m]["i"]) for m in members) and len(members) <= 4:
        return "Lichtquelle"
    if all(W.guisByPart.get(W.parts[m]["i"]) for m in members):
        return "Schild/Bildschirm (SurfaceGui)"
    if INTENTIONAL_FLOAT.search(names):
        return "Name: " + INTENTIONAL_FLOAT.search(names).group(1)
    if min(W.lo[m][1] for m in members) > 120:
        return "hoch am Himmel (> 120)"
    if all(W.trans[m] >= 0.5 for m in members):
        return "durchsichtig"
    return None


def check_floating(W, res):
    """(d) verankerte, sichtbare Baugruppen ohne Kontakt zu Gelände/anderen Teilen"""
    base = ~W.nan & ~W.hum & W.visible & W.anch
    uf = UF(W.n)
    for i, j in res["touch"]:
        if base[i] and base[j]:
            uf.union(i, j)
    for j in W.w.get("joints", []):
        a, b = j.get("p0"), j.get("p1")
        if j.get("e") == 1 and a in W.idx and b in W.idx:
            uf.union(W.idx[a], W.idx[b])
    # Szenen getrennt: Server-Cluster dürfen über Client-Teile nicht "geerdet" werden – darum Client-Teile nur
    # als Stütze für Client-Teile derselben Phase (scene_ok ist in candidate_pairs schon erzwungen)
    comps = collections.defaultdict(list)
    for k in np.nonzero(base)[0]:
        comps[uf.find(int(k))].append(int(k))
    floats = []
    vox_gaps = []
    for root, members in comps.items():
        grounded = False
        best_gap = None
        voxel_near = False
        water = False
        # mit Server-Teilen verbundene Client-Cluster: OK; reine Server-Cluster brauchen eigenen Kontakt
        for m in members:
            if grounded:
                break
            for (x, z) in footprint_points(W, m):
                c, gap, isvox = W.terrain.contact(x, z, W.lo[m][1], W.hi[m][1])
                if c:
                    grounded = True
                    if isvox and gap == 0.0:
                        voxel_near = isvox
                    break
                if gap is not None:
                    best_gap = gap if best_gap is None else min(best_gap, gap)
                if W.terrain.water_at(x, z, W.lo[m][1]):
                    water = True
        if grounded:
            continue
        if water:
            continue  # schwimmt (Bojen, Stege, Boote) – getrennt nicht gemeldet
        # Gibt es ein (nicht verbundenes) sichtbares Teil direkt darunter? -> Spalt-Höhe
        k = min(members, key=lambda m: W.lo[m][1])
        bottom = W.lo[k][1]
        x, z = W.pos[k][0], W.pos[k][2]
        under = (W.visible & ~W.nan & (W.lo[:, 0] <= x) & (W.hi[:, 0] >= x) & (W.lo[:, 2] <= z) & (W.hi[:, 2] >= z)
                 & (W.hi[:, 1] <= bottom + 1e-6))
        under[members] = False
        if W.src[k] == "s":
            under &= W.src == "s"
        support_top = W.hi[under, 1].max() if under.any() else None
        tt = W.terrain.top(x, z)
        cands = [v for v in (support_top, tt) if v is not None and v > -1e8]
        gap = bottom - max(cands) if cands else None
        floats.append({"members": members, "k": k, "gap": gap, "why": classify_float(W, members)})
    res["d"] = floats


def check_below(W, res):
    buried, under = [], []
    for k in range(W.n):
        if W.nan[k] or not W.visible[k] or W.hum[k]:
            continue
        if W.hi[k][1] > 0.5 and W.lo[k][1] > -0.3:
            continue
        pts = footprint_points(W, k)
        tops = []
        holes = 0
        for (x, z) in pts:
            solid, water, _v = W.terrain.column(x, z)
            inside = any(a - 0.05 <= W.lo[k][1] and W.hi[k][1] <= b + 0.05 for a, b in solid)
            tops.append(inside)
            if not any(a - 0.05 <= W.lo[k][1] <= b + 0.05 for a, b in solid) and W.lo[k][1] < -0.3:
                holes += 1
        if all(tops):
            buried.append(k)
        elif holes >= 3 and W.lo[k][1] < -0.3:
            under.append(k)
    res["e"] = (buried, under)


def check_outliers(W, res):
    out = collections.defaultdict(list)
    for k in range(W.n):
        p = W.parts[k]
        if W.nan[k]:
            out["NaN-CFrame"].append(k)
            continue
        s = W.size[k]
        if s.min() < 0.05 and W.visible[k]:
            out["winzig (< 0,05 Stud)"].append(k)
        if s.max() > 600:
            out["riesig (> 600 Stud)"].append(k)
        Rm = W.R[k]
        if np.abs(Rm @ Rm.T - np.eye(3)).max() > 2e-3 or abs(np.linalg.det(Rm) - 1) > 2e-3:
            out["schiefe/gespiegelte Rotation"].append(k)
        x, y, z = W.pos[k]
        if abs(x) > MAP_HALF + 64 or abs(z) > MAP_HALF + 64:
            out["außerhalb der Karte (|x|,|z| > 1088)"].append(k)
        if y < -60 or y > 1200:
            out["Höhe außerhalb -60…1200"].append(k)
        if p.get("c") == "Part" and W.shape[k] == "Ball" and (abs(s[0] - s[1]) > 1e-3 or abs(s[1] - s[2]) > 1e-3):
            out["Kugel mit ungleicher Größe (Roblox nimmt die kleinste Achse)"].append(k)
    res["f"] = out


# ---------------------------------------------------------------------------------------------
#  Bericht
# ---------------------------------------------------------------------------------------------
def group_lines(W, items, key_fn, line_fn, max_groups, max_per_group, title_fn=None):
    groups = collections.defaultdict(list)
    for it in items:
        groups[key_fn(it)].append(it)
    order = sorted(groups.items(), key=lambda kv: -len(kv[1]))
    L = []
    for gi, (g, lst) in enumerate(order):
        if gi >= max_groups:
            L.append("    … %d weitere Gruppen" % (len(order) - max_groups))
            break
        L.append("  [%d] %s" % (len(lst), title_fn(g, lst) if title_fn else g))
        for it in lst[:max_per_group]:
            L.append("      " + line_fn(it))
        if len(lst) > max_per_group:
            L.append("      … %d weitere" % (len(lst) - max_per_group))
    return L


def zone_of(x, z, cfg):
    zones = ((cfg or {}).get("City") or {}).get("Zones") or {}
    r = math.hypot(x, z)
    for name, zz in zones.items():
        c = zz.get("Center")
        if not c:
            continue
        cx, cz = c[0], c[2]
        if "Width" in zz:
            if abs(x - cx) <= zz["Width"] / 2 + 20 and abs(z - cz) <= zz.get("Depth", zz["Width"]) / 2 + 20:
                return name
        elif "Radius" in zz:
            if math.hypot(x - cx, z - cz) <= zz["Radius"] + 10:
                return name
        elif name == "Helipad" and math.hypot(x - cx, z - cz) <= 120:
            return name
    if 380 <= r <= 470:
        return "Plots (Skyline-Ring)"
    if 225 <= r <= 265:
        return "Ring-Boulevard"
    if 540 <= r <= 580:
        return "Äußerer Ring"
    if 920 <= r <= 980:
        return "Autobahnring"
    if 640 <= r <= 900 and z < 0:
        return "Finanzviertel-Kulisse"
    return "sonst"


def budgets(W, res):
    cfg = W.w.get("config") or {}
    L = []
    srv = W.src == "s"
    city = sum(1 for k in range(W.n) if srv[k] and W.path[k].startswith("Workspace.AkytexCity"))
    tower = sum(1 for k in range(W.n) if srv[k] and W.path[k].startswith("Workspace.AkyTowers"))
    chars = sum(1 for k in range(W.n) if srv[k] and W.hum[k])
    rest = int(srv.sum()) - city - tower - chars
    total = int(srv.sum())
    L.append("  Server-Teile (§C16: Stadt ≤ 12.000 · Tower ≤ 4.600 · Rest ≤ 400 · gesamt ≤ 17.000):")
    L.append("    Stadt   Workspace.AkytexCity  %6d  %s" % (city, "OK" if city <= 12000 else "ÜBER BUDGET"))
    L.append("    Tower   Workspace.AkyTowers   %6d  %s" % (tower, "OK" if tower <= 4600 else "ÜBER BUDGET"))
    L.append("    Rest    (ohne Figuren)        %6d  %s" % (rest, "OK" if rest <= 400 else "ÜBER BUDGET"))
    L.append("    Figuren (Humanoid)            %6d" % chars)
    L.append("    gesamt                        %6d  %s" % (total, "OK" if total <= 17000 else "ÜBER BUDGET"))
    # Hochrechnung Tower: Hüllen-Teile je Etage
    plots = W.w.get("plots") or []
    for pl in plots:
        a = pl.get("attrs") or {}
        fl = a.get("Floors") or 0
        if fl and fl > 0:
            pref = pl["p"] + "."
            n = sum(1 for k in range(W.n) if srv[k] and W.path[k].startswith(pref))
            per = n / fl
            L.append("    Hochrechnung %s: %d Teile bei %d Etagen = %.1f/Etage -> 10 Tower × 50 Etagen ≈ %d (Budget 4.600)"
                     % (pl["p"], n, fl, per, int(per * 500)))
    # Lichter
    lights = W.w.get("lights", [])
    sl = [l for l in lights if l.get("src") == "s"]
    on = sum(1 for l in sl if l.get("e") == 1)
    sh = sum(1 for l in sl if l.get("sh") == 1)
    L.append("  Lichter Server: %d (eingeschaltet %d, mit Schatten %d) – WorldLook schaltet clientseitig die nächsten N ein"
             % (len(sl), on, sh))
    tiers = cfg.get("Quality") or {}
    budget = ", ".join("%s %s" % (k, (tiers.get(k) or {}).get("Lights")) for k in ("Low", "Medium", "High", "Ultra"))
    L.append("    Licht-Budget je Grafikstufe (Config.Quality): " + budget + " · §C16 PC High/Ultra ≤ 32/64")
    for c in W.w.get("client", []):
        on = c.get("clientLightsOn", 0)
        L.append("    Client-Phase %-7s: %d Lichter im Client-Workspace, %d eingeschaltet %s · %d Teile im Client-Workspace (Budget sichtbar ≤ 8.000) · %d GUI-Objekte in Welt-GUIs"
                 % (c["phase"], c.get("clientLights", 0), on,
                    "-> ÜBER PC-Ultra-Budget 64" if on > 64 else ("-> über High-Budget 32" if on > 32 else "OK"),
                    c.get("clientWorkspaceParts", 0), c.get("clientWorldGuiObjects", 0)))
    # Je Zone
    zc = collections.defaultdict(lambda: [0, 0, 0, 0])
    for k in range(W.n):
        if not srv[k] or W.nan[k]:
            continue
        z = zone_of(W.pos[k][0], W.pos[k][2], cfg)
        zc[z][0] += 1
    for l in sl:
        x, y, z = l["pos"]
        zz = zone_of(x, z, cfg)
        zc[zz][1] += 1
        if l.get("sh") == 1:
            zc[zz][2] += 1
    for g in W.w.get("guis", []):
        if g.get("src") == "s" and g.get("pi") in W.idx:
            k = W.idx[g["pi"]]
            zc[zone_of(W.pos[k][0], W.pos[k][2], cfg)][3] += g.get("n", 0)
    L.append("  Je Bereich (Server): Teile / Lichter / davon mit Schatten / GUI-Objekte in Welt-GUIs")
    for z, v in sorted(zc.items(), key=lambda kv: -kv[1][0]):
        L.append("    %-28s %6d Teile %4d Lichter %3d Schatten %5d GUI-Objekte" % (z, v[0], v[1], v[2], v[3]))
    # dichteste 128er-Zellen
    cells = collections.Counter()
    lcell = collections.Counter()
    for k in range(W.n):
        if srv[k] and not W.nan[k]:
            cells[(int(W.pos[k][0] // 128), int(W.pos[k][2] // 128))] += 1
    for l in sl:
        lcell[(int(l["pos"][0] // 128), int(l["pos"][2] // 128))] += 1
    L.append("  Dichteste 128×128-Zellen (Teile): " + ", ".join(
        "(%d…%d, %d…%d) %d" % (a * 128, a * 128 + 128, b * 128, b * 128 + 128, n) for (a, b), n in cells.most_common(6)))
    L.append("  Dichteste 128×128-Zellen (Lichter): " + ", ".join(
        "(%d…%d, %d…%d) %d" % (a * 128, a * 128 + 128, b * 128, b * 128 + 128, n) for (a, b), n in lcell.most_common(6)))
    # Streaming: große Atomic-Modelle, Persistent-Teile
    models = W.w.get("models", [])
    pers = sum(m.get("n", 0) for m in models if m.get("mode") in ("Persistent", "PersistentPerPlayer") and m.get("src") == "s")
    big_atomic = sorted([m for m in models if m.get("mode") == "Atomic" and m.get("src") == "s"], key=lambda m: -m.get("n", 0))[:6]
    L.append("  Streaming: %d Teile in Persistent-Modellen (immer beim Client) · größte Atomic-Modelle: %s"
             % (pers, ", ".join("%s (%d)" % (m["p"], m["n"]) for m in big_atomic)))
    nomodel = sum(1 for k in range(W.n) if srv[k] and W.md[k] is None and not W.hum[k])
    L.append("  Streaming: %d Server-Teile ohne Model (streamen einzeln, Teil für Teil)" % nomodel)
    res["g"] = L


def main():
    ap = argparse.ArgumentParser(description="Geometrie-Prüfungen für world.json")
    ap.add_argument("world", nargs="?", default=DEFAULT_WORLD)
    ap.add_argument("--out", default=None)
    ap.add_argument("--json", default=None)
    ap.add_argument("--max", type=int, default=12, help="Beispiele je Gruppe")
    args = ap.parse_args()
    W = World(args.world)
    base = os.path.dirname(os.path.abspath(args.world))
    out_txt = args.out or os.path.join(base, "worldcheck.txt")
    out_json = args.json or os.path.join(base, "worldcheck.json")
    res = {}
    check_unanchored(W, res)
    check_pairs(W, res)
    check_floating(W, res)
    check_below(W, res)
    check_outliers(W, res)
    budgets(W, res)
    mx = args.max

    L = []
    meta = W.meta
    cnt = meta.get("counts", {})
    L.append("AKYTEX TYCOON · Headless-Harness · worldcheck (%s)" % os.path.relpath(args.world))
    L.append("=" * 100)
    L.append("Welt: %d Teile (Server %d, Client %d in Phasen %s), Simulationszeit %.1f s, Modus %s" % (
        W.n, int((W.src == "s").sum()), int((W.src == "c").sum()),
        "/".join(sorted({p for p in W.phase if p})), meta.get("simTime", 0), meta.get("mode", "?")))
    a_bug = [f for f in res["a"] if not f["vehicle"]]
    a_veh = [f for f in res["a"] if f["vehicle"]]
    zf = res["b"]
    deep_x = [d for d in res["c"] if not d[4]]
    deep_s = [d for d in res["c"] if d[4]]
    fl_bug = [f for f in res["d"] if f["why"] is None]
    fl_ok = [f for f in res["d"] if f["why"] is not None]
    buried, under = res["e"]
    L.append("")
    L.append("ZUSAMMENFASSUNG")
    L.append("  (a) unverankert ohne Halt:          %4d Baugruppen (%d Teile) · Fahrzeuge (Physik, ok): %d" % (
        len(a_bug), sum(len(f["members"]) for f in a_bug), len(a_veh)))
    L.append("  (b) Z-Fighting:                     %4d Paare, %.0f Stud² gesamt" % (len(zf), sum(z[2] for z in zf)))
    L.append("  (c) tiefe Durchdringung:            %4d Paare verschiedener Modelle · %d im selben Modell (Info)" % (len(deep_x), len(deep_s)))
    L.append("  (d) schwebend (verdächtig):         %4d Baugruppen · gewollt schwebend (Heuristik): %d" % (len(fl_bug), len(fl_ok)))
    L.append("  (e) vergraben (unsichtbar):         %4d Teile · unter Y=0 sichtbar ohne Gelände: %d" % (len(buried), len(under)))
    L.append("  (f) Ausreißer:                      %s" % (", ".join("%s %d" % (k, len(v)) for k, v in res["f"].items()) or "keine"))

    # (a)
    L.append("")
    L.append("(a) UNVERANKERTE TEILE OHNE VERBINDUNG ZU EINEM VERANKERTEN TEIL (fallen/zerstreuen sich)")
    L.append("-" * 100)
    if not a_bug:
        L.append("  (keine)")
    L += group_lines(
        W, a_bug, lambda f: prefix_of(W.path[f["k"]]),
        lambda f: "%s %s · %d Teile%s%s" % (
            W.label(f["k"]), W.where(f["k"]), len(f["members"]),
            " · CanCollide=false -> fällt durch den Boden" if f["noColl"] else "",
            " · liegt auf dem Gelände (kann weggeschoben werden)" if f["rest"] else " · ohne Auflage -> fällt"),
        40, mx)
    if a_veh:
        L.append("  Fahrzeuge (VehicleSeat, gewollte Physik): " + ", ".join(sorted({prefix_of(W.path[f["k"]], 5) for f in a_veh}))[:600])

    # (b)
    L.append("")
    L.append("(b) Z-FIGHTING (koplanare, gleichgerichtete Flächen verschiedener sichtbarer Teile, Toleranz %.2f Stud)" % ZF_PLANE_TOL)
    L.append("-" * 100)
    if not zf:
        L.append("  (keine)")
    zf_sorted = sorted(zf, key=lambda z: -z[2])

    def zkey(z):
        a, b = prefix_of(W.path[z[0]]), prefix_of(W.path[z[1]])
        return " <-> ".join(sorted({a, b})) if a != b else a

    def zline(z):
        i, j, area, n = z
        return "%.2f Stud² · %s %s  <->  %s · Normale %s · Material %s/%s" % (
            area, W.label(i), W.where(i), W.path[j] + (" [Client]" if W.src[j] == "c" else ""), n, W.mat[i], W.mat[j])

    L += group_lines(W, zf_sorted, zkey, zline, 40, mx,
                     lambda g, lst: "%s  (%.1f Stud²)" % (g, sum(z[2] for z in lst)))

    # (c)
    L.append("")
    L.append("(c) TIEFE DURCHDRINGUNG FESTER TEILE VERSCHIEDENER MODELLE (Tiefe ≥ %.1f Stud, ≥ %d %% des kleineren Teils)" % (DEEP_DEPTH, DEEP_FRAC * 100))
    L.append("-" * 100)
    if not deep_x:
        L.append("  (keine)")

    def dkey(d):
        return prefix_of(W.path[d[0]]) + "  IN  " + prefix_of(W.path[d[1]])

    def dline(d):
        a, b, depth, frac, _s = d
        return "%s %s steckt %.1f Stud tief (%d %%) in %s%s" % (
            W.label(a), W.where(a), depth, frac * 100, W.path[b], " [Client]" if W.src[b] == "c" else "")

    L += group_lines(W, sorted(deep_x, key=lambda d: -d[2] * d[3]), dkey, dline, 50, mx)
    if deep_s:
        L.append("  Im selben Modell (oft gewollt, nur Info – größte 15):")
        for d in sorted(deep_s, key=lambda d: -d[2] * d[3])[:15]:
            L.append("      " + dline(d))

    # (d)
    L.append("")
    L.append("(d) SCHWEBENDE VERANKERTE TEILE/BAUGRUPPEN (kein Kontakt zu Gelände oder anderen sichtbaren Teilen)")
    L.append("-" * 100)
    if not fl_bug:
        L.append("  (keine)")

    def fline(f):
        k = f["k"]
        return "%s %s · %d Teile · Unterkante %.1f · Spalt nach unten %s" % (
            W.label(k), W.where(k), len(f["members"]), W.lo[k][1],
            ("%.2f Stud" % f["gap"]) if f["gap"] is not None else "?")

    L += group_lines(W, sorted(fl_bug, key=lambda f: -(f["gap"] or 0)), lambda f: prefix_of(W.path[f["k"]]), fline, 40, mx)
    L.append("  Gewollt schwebend (Heuristik: Neon, Lichter, Schilder, Himmels-Deko, Name) – nur Übersicht:")
    L += group_lines(W, fl_ok, lambda f: "%s (%s)" % (prefix_of(W.path[f["k"]]), f["why"].split(":")[0]), fline, 30, 3)

    # (e)
    L.append("")
    L.append("(e) TEILE UNTER DEM BODEN")
    L.append("-" * 100)
    L.append("  Komplett im Gelände vergraben (unsichtbar, kosten Teile-Budget): %d" % len(buried))
    L += group_lines(W, buried, lambda k: prefix_of(W.path[k]),
                     lambda k: "%s %s · Oberkante %.2f" % (W.label(k), W.where(k), W.hi[k][1]), 30, mx)
    L.append("  Unter Y = 0 sichtbar an Stellen ohne Gelände (Wasser/Loch/Kartenrand): %d" % len(under))
    L += group_lines(W, under, lambda k: prefix_of(W.path[k]),
                     lambda k: "%s %s · Unterkante %.2f%s" % (W.label(k), W.where(k), W.lo[k][1],
                                                              " (Pfeiler/Stütze, wohl gewollt)" if PIER_NAMES.search(W.name[k]) else ""), 30, mx)

    # (f)
    L.append("")
    L.append("(f) AUSREISSER")
    L.append("-" * 100)
    if not res["f"]:
        L.append("  (keine)")
    for kind, lst in res["f"].items():
        L.append("  %s: %d" % (kind, len(lst)))
        for k in lst[: mx * 2]:
            p = W.parts[k]
            L.append("      %s · Größe %s · %s%s" % (W.label(k), p["s"], ("Erzeugt: " + p["mk"]) if p.get("mk") else "", ""))

    # (g)
    L.append("")
    L.append("(g) BUDGETS (docs/DESIGN.md §C16)")
    L.append("-" * 100)
    L += res["g"]

    text = "\n".join(L) + "\n"
    with open(out_txt, "w", encoding="utf-8") as f:
        f.write(text)
    # Markierungen für den Renderer
    marks = []
    for f in a_bug:
        marks.append({"kind": "a", "i": W.parts[f["k"]]["i"]})
    for z in zf_sorted[:400]:
        marks.append({"kind": "b", "i": W.parts[z[0]]["i"], "j": W.parts[z[1]]["i"], "area": z[2]})
    for d in deep_x[:400]:
        marks.append({"kind": "c", "i": W.parts[d[0]]["i"], "j": W.parts[d[1]]["i"]})
    for f in fl_bug:
        marks.append({"kind": "d", "i": W.parts[f["k"]]["i"], "n": len(f["members"])})
    for k in buried:
        marks.append({"kind": "e", "i": W.parts[k]["i"]})
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump({"marks": marks}, f)
    head = text.split("\n(a) ")[0]
    print(head)
    print("Bericht: %s · Markierungen: %s" % (os.path.relpath(out_txt), os.path.relpath(out_json)))


if __name__ == "__main__":
    main()
