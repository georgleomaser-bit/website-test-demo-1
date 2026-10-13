#!/usr/bin/env python3
# =====================================================================
#  AKYTEX TYCOON – Tower-Ökonomie-Simulation + Release-Gates G1–G4 (DESIGN.md §B5, §B9.10)
#  Besitzer-Paket: WP6 (Turm-Ökonomie). Startwerte hier == src/shared/Config/Tower.luau == Shared/TowerMath
#  (tests/towermath.test.luau vergleicht alle 50 Etagen mit dieser Datei; --quick prüft den Gleichstand mit Config).
#  Aufruf (im Projektordner):
#    python3 tools/economy_sim.py --quick    ≈ 10 s: Config-Abgleich + G1 (muss "OK" melden) + G2–G4 ohne Pass-Vergleich
#    python3 tools/economy_sim.py            ≈ 45 s: Voll-Lauf, alle Gates G1–G4 (inkl. Pässe höchstens 15 % schneller)
#    python3 tools/economy_sim.py --table    volle Kosten-/Einkommens-/Bauzeit-Tabelle der 50 Etagen (§B5.1)
#  Exit-Code 1, wenn ein geprüftes Gate oder der Config-Abgleich scheitert (scripts/check.sh nutzt --quick).
#  Nur Python-Standardbibliothek.
#
#  Modell (vereinfacht, mit denselben Formeln wie Config/Tower.luau + Shared/TowerMath.luau):
#   Einkommen/s = Basis × Perm × TraderFaktor × Pässe
#     Basis        = Gehalt + Σ Etage(n): I(n) × Raum (Ø 1,15) × Stufe(L) × (1 + Σ Personal)
#     Perm         = 1 + 0,1·Effizienz + 0,25·Börsengänge + 0,1·Vorstand "Wachstum"   (additiv)
#     TraderFaktor = (1 + Lizenz-Bonus) × (1 + 0,03·Ruf)                              (nur Skill, nie Robux)
#     Pässe        = (1 + x2 + 2·x3) × VIP 1,10   (x2 -> ×2, x3 -> ×3, beide -> ×4)
#   Handel direkt (Gewinn-Transfer): CR/s = r × Basis(Lizenz) × Bau-Kurs(Lizenz) / 1200  (nur aktiv, nie multipliziert)
#   Offline: 50 % des Einkommens bis 8 h, dann nichts. Greedy-Käufer: kleinste Amortisationszeit unter Etage,
#   Raum-Stufe, Personal, Effizienz. Stufen-Tore = Lizenz (Trader-XP) + Börsengang.
#  Gates (Spieler „gratis, guter Trader“: 1,5 h aktiv/Tag, r = 2,5 %/Börsentag, 700 Trader-XP/h):
#   G1 teuerster Einzelpreis < 1e14, kein Kontostand ≥ 9e15, alle Config-Preise ganzzahlig
#   G2 Handels-Anteil aktiv (Gewinn-Transfer + Trader-Faktor): ≥ 15 % in Stufen 4–6, 25–45 % ab Stufe 7
#   G3 Gewinn-Transfer-Anteil aktiv ≥ 10 % in Stufen 1–7
#   G4 Etage 4 ≤ 5 min · Etage 10 ≤ 25 min · Etage 25 Tag 2–5 · Etage 50 Tag 28–56 ·
#      Pässe (x2+x3+VIP) höchstens 15 % schneller zu Etage 50 (Lizenz-Tore bremsen)
#   Anteile je Stufe aus dem ersten Lauf, in dem die Stufe erreicht wird, auf ganze Prozent gerundet (wie §B5.4/§B9.10).
# =====================================================================
import math
import os
import re
import sys

CAP = 9e15
DAY = 86400.0

# ---------------------------------------------------------------- Etagen
I0, IR = 4.0, 1.30  # Basis-Einkommen Etage n: I0 · IR^(n−1)
C2 = 1000.0  # Etage 1 gratis, Etage 2 = 1000 CR
BANDS = ((3, 12, 1.50), (13, 25, 1.56), (26, 40, 1.58), (41, 50, 1.60))
FLOORS = 50
SALARY = 3.0


def floor_cost(n):
	if n <= 1:
		return 0.0
	c = C2
	for k in range(3, n + 1):
		for a, b, r in BANDS:
			if a <= k <= b:
				c *= r
	return float(round(c))


def floor_income(n):
	return I0 * IR ** (n - 1)


def build_time(n):
	if n <= 9:
		return 3.0
	return min(90 * 60.0, 20.0 * 1.33 ** (n - 10))


# Stufen: (erste Etage, Lizenz-Index, Börsengänge nötig)
STAGES = (
	(1, 0, 0), (2, 0, 0), (4, 0, 0), (7, 0, 0), (10, 1, 0), (14, 2, 0),
	(18, 3, 0), (22, 3, 0), (26, 4, 0), (31, 5, 0), (37, 6, 0), (44, 6, 1),
)


def stage_of(nfloors):
	s = 0
	for i, row in enumerate(STAGES):
		if nfloors >= row[0]:
			s = i
	return s


def gate(n):
	g, ipo = 0, 0
	for f, lic, need in STAGES:
		if n >= f:
			g, ipo = lic, need
	return g, ipo


# ---------------------------------------------------------------- Lizenzen
# Name, XP gesamt, Basis (AKY), Bau-Kurs (CR je AKY), Turm-Bonus
LIC = (
	("Azubi I", 0, 25_000, 40, 0.00),
	("Azubi II", 300, 50_000, 200, 0.04),
	("Azubi III", 1_200, 100_000, 800, 0.08),
	("Trader I", 3_000, 250_000, 1_500, 0.12),
	("Trader II", 7_000, 600_000, 3_000, 0.16),
	("Trader III", 14_000, 1_500_000, 6_000, 0.20),
	("Fondsmanager I", 28_000, 4_000_000, 12_000, 0.25),
	("Fondsmanager II", 50_000, 10_000_000, 20_000, 0.30),
	("Fondsmanager III", 80_000, 25_000_000, 30_000, 0.35),
	("Börsen-Legende", 125_000, 60_000_000, 40_000, 0.40),
)

LEVEL_F = (1.0, 1.25, 1.5, 1.8, 2.2)
LEVEL_C = (1.0, 2.5, 6.0, 15.0)  # × max(C(n), 500)
STAFF = ((0.10, 1.0, 1), (0.25, 3.0, 2), (0.50, 9.0, 4), (1.00, 25.0, 7))  # Bonus, Kostenfaktor, Mindest-Stufe (0-basiert)
ROOM = 1.15  # Ø Raum-Faktor (Mischung)
EFF_STEP, EFF_BASE, EFF_R, EFF_MAX = 0.10, 10_000.0, 3.0, 20
RUF_TH = (10, 30, 60, 100, 150, 210, 280, 360, 450, 550)


def upbase(n):
	return max(floor_cost(n), 500.0)


def stars_for(run_spend):
	if run_spend < 1e7:
		return 0
	return int(4 * math.log10(run_spend / 1e6))


class Player:
	def __init__(self, name, passes=1.0, vip=1.0, xp_hour=700.0, r=0.025, active_h=1.5, trades=True):
		self.name, self.passes, self.vip = name, passes, vip
		self.xp_hour, self.r, self.active_h, self.trades = xp_hour, r, active_h, trades


def run(p, xp0=0.0, t0=0.0, ipo=0, perks=None, stop_floor=25, max_days=120, dt=10.0):
	perks = perks or {}
	t, xp, cr = t0, xp0, 0.0
	floors = [[0, []] for _ in range({0: 1, 1: 4, 2: 8, 3: 12}[perks.get("Blitz", 0)])]
	eff, crane, spend = 0, t0, 0.0
	cost_mult = 1 - 0.05 * perks.get("Bau", 0)
	acc = [0.0, 0.0, 0.0]  # direkt, Trader-Faktor, Rest
	act = [0.0, 0.0, 0.0]  # nur aktive Sitzungen
	amark = [0.0, 0.0, 0.0]
	hits, seen, mark = {}, -1, [0.0, 0.0, 0.0]
	maxval = 0.0

	def lic():
		i = 0
		for k, row in enumerate(LIC):
			if xp >= row[1]:
				i = k
		return i

	def ruf(day):
		# Ruf-Punkte: guter Trader ≈ 18/Tag (Deckel 20/UTC-Tag), Schwellen laut Config.Progression.Ruf
		if not p.trades:
			return 0
		pts = min(20, 18 * p.r / 0.025) * day
		lv = 0
		for k, th in enumerate(RUF_TH):
			if pts >= th:
				lv = k + 1
		return lv

	def income(day):
		base = SALARY
		for i, (lv, st) in enumerate(floors):
			base += floor_income(i + 1) * ROOM * LEVEL_F[lv] * (1 + sum(STAFF[s][0] for s in st))
		tf = (1 + LIC[lic()][4]) * (1 + 0.03 * ruf(day)) if p.trades else 1.0
		perm = 1 + EFF_STEP * eff + 0.25 * min(ipo, 20) + 0.1 * perks.get("Wachstum", 0)
		tot = base * perm * tf * p.passes * p.vip
		return tot, tot * (1 - 1 / tf), base * tf * p.passes * p.vip

	while t < t0 + max_days * DAY:
		day = t / DAY
		tod = t % DAY
		active = tod < p.active_h * 3600
		inc, skill, _ = income(day)
		if active:
			g = inc * dt
			acc[1] += skill * dt
			acc[2] += (inc - skill) * dt
			act[1] += skill * dt
			act[2] += (inc - skill) * dt
			if p.trades:
				li = lic()
				tr = p.r * LIC[li][2] * LIC[li][3] / 1200 * dt
				g += tr
				acc[0] += tr
				act[0] += tr
			cr = min(CAP, cr + g)
			xp += p.xp_hour / 3600 * dt + (300 / 3600 * dt if t < 3600 else 0)
		elif tod - p.active_h * 3600 < 8 * 3600:
			g = inc * 0.5 * dt
			cr = min(CAP, cr + g)
			acc[1] += skill * 0.5 * dt
			acc[2] += (inc - skill) * 0.5 * dt
		maxval = max(maxval, cr)
		if active:
			for _ in range(40):
				li, st = lic(), stage_of(len(floors))
				best = None
				n = len(floors) + 1
				gl, gi = gate(n)
				if n <= stop_floor and t >= crane and gl <= li and ipo >= gi:
					c = floor_cost(n) * cost_mult
					best = (c / (floor_income(n) * ROOM), "floor", c, n)
				for i, (lv, stf) in enumerate(floors):
					nn = i + 1
					b0 = floor_income(nn) * ROOM * (1 + sum(STAFF[s][0] for s in stf))
					if lv < 4:
						c = upbase(nn) * LEVEL_C[lv] * cost_mult
						cand = (c / (b0 * (LEVEL_F[lv + 1] - LEVEL_F[lv])), "lvl", c, i)
						best = cand if best is None or cand[0] < best[0] else best
					if len(stf) < 2:
						for s in range(3, -1, -1):
							if st >= STAFF[s][2]:
								c = upbase(nn) * STAFF[s][1] * cost_mult
								cand = (c / (floor_income(nn) * ROOM * LEVEL_F[lv] * STAFF[s][0]), "staff", c, (i, s))
								best = cand if best is None or cand[0] < best[0] else best
								break
				if eff < EFF_MAX:
					c = EFF_BASE * EFF_R**eff
					_, _, bt = income(day)
					cand = (c / (bt * EFF_STEP), "eff", c, None)
					best = cand if best is None or cand[0] < best[0] else best
				if best is None or best[2] > cr:
					break
				_, kind, c, arg = best
				maxval = max(maxval, c)
				cr -= c
				spend += c
				if kind == "floor":
					floors.append([0, []])
					crane = t + build_time(arg) * (1 - 0.10 * perks.get("Tempo", 0))
				elif kind == "lvl":
					floors[arg][0] += 1
				elif kind == "staff":
					floors[arg[0]][1].append(arg[1])
				else:
					eff += 1
		s = stage_of(len(floors))
		if s != seen:
			if seen >= 0:
				d = [acc[k] - mark[k] for k in range(3)]
				tt = sum(d) or 1
				a = [act[k] - amark[k] for k in range(3)]
				ta = sum(a) or 1
				hits[seen] = hits[seen] + (d[0] / tt, (d[0] + d[1]) / tt, a[0] / ta, (a[0] + a[1]) / ta)
			mark = acc[:]
			amark = act[:]
			seen = s
			inc, _, _ = income(day)
			li = lic()
			hits[s] = (t, len(floors), inc, (p.r * LIC[li][2] * LIC[li][3] / 1200) if p.trades else 0.0, LIC[li][0])
		if len(floors) >= stop_floor and t >= crane:
			break
		t += dt
	d = [acc[k] - mark[k] for k in range(3)]
	tt = sum(d) or 1
	a = [act[k] - amark[k] for k in range(3)]
	ta = sum(a) or 1
	hits[seen] = hits[seen][:5] + (d[0] / tt, (d[0] + d[1]) / tt, a[0] / ta, (a[0] + a[1]) / ta)
	tot = sum(acc) or 1
	return {
		"t": t, "xp": xp, "floors": len(floors), "eff": eff, "spend": spend, "hits": hits, "max": maxval,
		"direct": acc[0] / tot, "skill": acc[1] / tot,
	}


def fmt_t(s):
	h = s / 3600
	if h < 1:
		return f"{s / 60:.0f} min"
	if h < 48:
		return f"{h:.1f} h"
	return f"{h / 24:.1f} d"


def show(title, res, t0=0.0):
	print(f"== {title}: Etagen {res['floors']}, Effizienz {res['eff']}, XP {res['xp']:.0f}, Zeit {fmt_t(res['t'] - t0)} "
		f"(Tag {res['t'] / DAY:.1f}), Ausgaben {res['spend']:.3g}, max. Betrag {res['max']:.3g}")
	for s in sorted(res["hits"]):
		h = res["hits"][s]
		extra = (f"| Stufe: direkt {h[5] * 100:4.1f} % Handel {h[6] * 100:4.1f} % · aktiv: direkt {h[7] * 100:4.1f} % Handel {h[8] * 100:4.1f} %"
			if len(h) > 5 else "")
		print(f"  Stufe {s + 1:2d} nach {fmt_t(h[0] - t0):>9} (Etage {h[1]:2d}) Einkommen {h[2]:9.3g}/s  Handel {h[3]:9.3g}/s "
			f"{h[4]:16s} {extra}")
	print(f"  gesamt: direkt {res['direct'] * 100:.1f} %, Trader-Faktor {res['skill'] * 100:.1f} %")


def campaign(p, runs=8, verbose=True):
	"""Läufe bis Etage 50 (Börsengang ab Etage 25). Gibt eine Auswertung für die Gates zurück."""
	t, xp, ipo, perks = 0.0, 0.0, 0, {}
	stars = 0
	out = {"t25": None, "t50": None, "stages": {}, "max": 0.0, "t4": None, "t10": None}
	for k in range(runs):
		target = 50 if ipo >= 1 else 25
		t_start = t
		res = run(p, xp0=xp, t0=t, ipo=ipo, perks=perks, stop_floor=target)
		if verbose:
			show(f"{p.name} Lauf {k + 1} (IPO {ipo}, Perks {perks})", res, t)
		out["max"] = max(out["max"], res["max"])
		for s, h in res["hits"].items():
			# je Stufe zählt der erste Lauf, in dem sie erreicht wurde (spätere Läufe starten mit Blitzstart)
			if s not in out["stages"] and len(h) > 5:
				out["stages"][s] = {"t": h[0] - t_start, "abs": h[0], "direct": h[7], "trade": h[8], "run": k + 1}
		t, xp = res["t"], res["xp"]
		if k == 0 and res["floors"] >= 25:
			out["t25"] = t
		if res["floors"] >= 50:
			out["t50"] = t
			if verbose:
				print(f"  → Etage 50 erreicht an Tag {t / DAY:.1f}")
			break
		if res["floors"] < 25:
			if verbose:
				print("  → Etage 25 nicht erreicht (Zeitlimit)")
			break
		stars += stars_for(res["spend"])
		ipo += 1
		left = stars
		perks = {}
		for name, cap in (("Wachstum", 10), ("Blitz", 3), ("Bau", 8), ("Tempo", 5)):
			lv = min(cap, left)
			perks[name] = lv
			left -= lv
	if 2 in out["stages"]:
		out["t4"] = out["stages"][2]["abs"]  # Stufe 3 = Etage 4 (erster Lauf)
	if 4 in out["stages"]:
		out["t10"] = out["stages"][4]["abs"]  # Stufe 5 = Etage 10
	return out


# ---------------------------------------------------------------- Config-Abgleich (Config/Tower.luau, Config/Trading.luau)
def _read(path):
	try:
		with open(path, encoding="utf-8") as f:
			return f.read()
	except OSError:
		return None


def _strip_comments(text):
	return re.sub(r"--[^\n]*", "", text)


def _block(text, name):
	"""Inhalt des Tabellen-Konstruktors nach `name = {` (geschweifte Klammern gezählt)."""
	m = re.search(re.escape(name) + r"\s*=\s*\{", text)
	if not m:
		return None
	depth, i = 0, m.end() - 1
	start = m.end()
	while i < len(text):
		if text[i] == "{":
			depth += 1
		elif text[i] == "}":
			depth -= 1
			if depth == 0:
				return text[start:i]
		i += 1
	return None


def _num(text, key):
	m = re.search(r"\b" + re.escape(key) + r"\s*=\s*(-?[0-9][0-9_.eE+-]*)", text or "")
	return float(m.group(1).replace("_", "")) if m else None


def _numbers(text):
	return [float(x) for x in re.findall(r"-?[0-9]+(?:\.[0-9]+)?(?:e[0-9]+)?", text or "")]


def _entries(block):
	"""Einträge mit Key = "…" einer Liste (für Stages/Staff/Rooms)."""
	out = {}
	if not block:
		return out
	pieces = re.split(r'(?=\bKey\s*=\s*")', block)
	for piece in pieces:
		m = re.match(r'Key\s*=\s*"([A-Za-z0-9_]+)"', piece)
		if m:
			out[m.group(1)] = piece
	return out


def config_sync(root):
	"""Prüft, dass die Startwerte dieser Simulation exakt in Config/Tower.luau stehen. Gibt (Fehler, Hinweise) zurück."""
	errors, notes = [], []
	tower = _read(os.path.join(root, "src", "shared", "Config", "Tower.luau"))
	if tower is None:
		return ["src/shared/Config/Tower.luau fehlt"], notes
	t = _strip_comments(tower)

	def same(label, cfg, sim):
		if cfg is None:
			errors.append(f"{label}: nicht in Config.Tower gefunden")
		elif abs(cfg - sim) > 1e-9 * max(1.0, abs(sim)):
			errors.append(f"{label}: Config {cfg:g} ≠ Simulation {sim:g}")

	same("I0", _num(t, "Tower.I0"), I0)
	same("IR", _num(t, "Tower.IR"), IR)
	same("C2", _num(t, "Tower.C2"), C2)
	same("Salary", _num(t, "Tower.Salary"), SALARY)
	same("Floors", _num(t, "Tower.Floors"), FLOORS)
	same("UpgradeMin", _num(t, "Tower.UpgradeMin"), 500.0)
	bands = _numbers(_block(t, "Tower.Bands"))
	if [tuple(bands[i:i + 3]) for i in range(0, len(bands), 3)] != [tuple(map(float, b)) for b in BANDS]:
		errors.append(f"Bands: Config {bands} ≠ Simulation {BANDS}")
	if _numbers(_block(t, "Tower.LevelFactor")) != list(LEVEL_F):
		errors.append("LevelFactor: Config ≠ Simulation")
	if _numbers(_block(t, "Tower.LevelCost")) != list(LEVEL_C):
		errors.append("LevelCost: Config ≠ Simulation")
	eff = _block(t, "Tower.Efficiency")
	same("Efficiency.Step", _num(eff, "Step"), EFF_STEP)
	same("Efficiency.Base", _num(eff, "Base"), EFF_BASE)
	same("Efficiency.Ratio", _num(eff, "Ratio"), EFF_R)
	same("Efficiency.Max", _num(eff, "Max"), EFF_MAX)
	build = _block(t, "Tower.Build")
	same("Build.Instant", _num(build, "Instant"), 9)
	same("Build.BaseSeconds", _num(build, "BaseSeconds"), 20)
	same("Build.Ratio", _num(build, "Ratio"), 1.33)
	same("Build.Cap", _num(build, "Cap"), 5400)
	stages = _entries(_block(t, "Tower.Stages"))
	order = ["Garage", "Kiosk", "Loft", "Office", "Glass", "Business", "HighRise", "Skyscraper", "Skyline", "Mega",
		"Hyper", "Orbit"]
	for i, key in enumerate(order):
		piece = stages.get(key)
		if piece is None:
			errors.append(f"Stages.{key}: fehlt")
			continue
		first, lic, need = STAGES[i]
		same(f"Stages.{key}.First", _num(piece, "First"), first)
		same(f"Stages.{key}.Licence", _num(piece, "Licence"), lic + 1)
		same(f"Stages.{key}.Ipo", _num(piece, "Ipo"), need)
	staff = _entries(_block(t, "Tower.Staff"))
	for i, key in enumerate(["Intern", "Analyst", "Senior", "Quant"]):
		piece = staff.get(key)
		if piece is None:
			errors.append(f"Staff.{key}: fehlt")
			continue
		bonus, cost, stage0 = STAFF[i]
		same(f"Staff.{key}.Bonus", _num(piece, "Bonus"), bonus)
		same(f"Staff.{key}.CostMult", _num(piece, "CostMult"), cost)
		same(f"Staff.{key}.MinStage", _num(piece, "MinStage"), stage0 + 1)
	# G1: alle Preise/Geldwerte in Config.Tower ganzzahlig
	for key in ("Price", "Credits", "C2", "UpgradeMin", "VaultPrefill"):
		for m in re.finditer(r"\b" + key + r"\s*=\s*(-?[0-9][0-9_.eE+-]*)", t):
			v = float(m.group(1).replace("_", ""))
			if v != int(v) or v < 0 or v >= 1e14:
				errors.append(f"{key} = {m.group(1)}: ganze Zahl 0 … 1e14 erwartet (G1)")
	# Lizenz-Tabelle (Bau-Kurs, Basis): Config.Progression (WP9), sonst Config.Trading.LicenceFallback (WP4)
	prog = _read(os.path.join(root, "src", "shared", "Config", "Progression.luau"))
	source, rows = None, []
	if prog is not None:
		block = _block(_strip_comments(prog), "Progression.Licences")
		if block:
			rows = [(_num(r, "Basis"), _num(r, "BauKurs")) for r in re.findall(r"\{[^{}]*BauKurs[^{}]*\}", block)]
			source = "Config.Progression.Licences"
	if not rows:
		trading = _read(os.path.join(root, "src", "shared", "Config", "Trading.luau"))
		if trading is not None:
			block = _block(_strip_comments(trading), "Trading.LicenceFallback")
			if block:
				rows = [(_num(r, "Basis"), _num(r, "BauKurs")) for r in re.findall(r"\{[^{}]*BauKurs[^{}]*\}", block)]
				source = "Config.Trading.LicenceFallback"
	if len(rows) == len(LIC):
		for i, (basis, kurs) in enumerate(rows):
			name, _, aky, rate, _ = LIC[i]
			if kurs is None or kurs != rate:
				errors.append(f"{source}[{i + 1}] Bau-Kurs {kurs} ≠ Simulation {rate} ({name})")
			# Basis steht dort in Cent (Trading) oder AKY (Progression) – beides akzeptieren
			if basis is not None and basis not in (aky, aky * 100):
				errors.append(f"{source}[{i + 1}] Basis {basis:g} ≠ Simulation {aky} AKY ({name})")
		notes.append(f"Lizenz-Tabelle geprüft: {source}")
	else:
		notes.append("Lizenz-Tabelle nicht gefunden – Abgleich übersprungen")
	return errors, notes


# ---------------------------------------------------------------- Gates
def pct(x):
	return round(x * 100)


def gates(free, passes=None):
	"""Wertet G2–G4 aus. Gibt Liste (Gate, ok, Text) zurück; ok = None bedeutet „nicht geprüft“."""
	res = []
	st = free["stages"]
	# G2: Handels-Anteil aktiv
	bad, vals = [], []
	for s in range(3, 12):
		if s not in st:
			continue
		v = pct(st[s]["trade"])
		vals.append(f"S{s + 1} {v} %")
		if s <= 5 and v < 15:
			bad.append(f"Stufe {s + 1}: {v} % < 15 %")
		if s >= 6 and not (25 <= v <= 45):
			bad.append(f"Stufe {s + 1}: {v} % nicht in 25–45 %")
	if len([s for s in range(3, 12) if s in st]) < 9:
		bad.append("nicht alle Stufen 4–12 erreicht")
	res.append(("G2", not bad, (", ".join(bad) if bad else "OK") + " · " + ", ".join(vals)))
	# G3: Gewinn-Transfer-Anteil aktiv in Stufen 1–7
	bad, vals = [], []
	for s in range(0, 7):
		if s not in st:
			bad.append(f"Stufe {s + 1} nicht erreicht")
			continue
		v = pct(st[s]["direct"])
		vals.append(f"S{s + 1} {v} %")
		if v < 10:
			bad.append(f"Stufe {s + 1}: {v} % < 10 %")
	res.append(("G3", not bad, (", ".join(bad) if bad else "OK") + " · " + ", ".join(vals)))
	# G4: Pacing
	bad, vals = [], []
	t4, t10, t25, t50 = free["t4"], free["t10"], free["t25"], free["t50"]
	if t4 is None or t4 > 5 * 60:
		bad.append("Etage 4 > 5 min")
	if t10 is None or t10 > 25 * 60:
		bad.append("Etage 10 > 25 min")
	if t25 is None or not (2 * DAY <= t25 <= 5 * DAY):
		bad.append("Etage 25 nicht an Tag 2–5")
	if t50 is None or not (28 * DAY <= t50 <= 56 * DAY):
		bad.append("Etage 50 nicht an Tag 28–56")
	vals.append(f"Etage 4 {fmt_t(t4) if t4 is not None else '–'}")
	vals.append(f"Etage 10 {fmt_t(t10) if t10 is not None else '–'}")
	vals.append(f"Etage 25 Tag {t25 / DAY:.1f}" if t25 is not None else "Etage 25 –")
	vals.append(f"Etage 50 Tag {t50 / DAY:.1f}" if t50 is not None else "Etage 50 –")
	ok = not bad
	if passes is not None:
		tp = passes["t50"]
		if tp is None or t50 is None:
			bad.append("Pässe: Etage 50 nicht erreicht")
		else:
			gain = 1 - tp / t50
			vals.append(f"Pässe Tag {tp / DAY:.1f} ({gain * 100:+.0f} % schneller)")
			if gain > 0.15:
				bad.append(f"Pässe {gain * 100:.0f} % schneller (> 15 %)")
		ok = not bad
		res.append(("G4", ok, (", ".join(bad) if bad else "OK") + " · " + ", ".join(vals)))
	else:
		res.append(("G4", ok, (", ".join(bad) if bad else "OK") + " · " + ", ".join(vals)
			+ " · Pass-Vergleich nur im Voll-Lauf"))
	return res


if __name__ == "__main__":
	root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
	print("Etagen-Kosten:", ", ".join(f"{n}:{floor_cost(n):.3g}" for n in (2, 5, 9, 12, 16, 20, 25, 30, 36, 40, 44, 50)))
	print("Summe bis 50:", f"{sum(floor_cost(n) for n in range(1, 51)):.3g}",
		" max. Raum-Stufe 50:", f"{upbase(50) * LEVEL_C[-1]:.3g}", " max. Personal 50:", f"{upbase(50) * STAFF[3][1]:.3g}",
		" max. Effizienz:", f"{EFF_BASE * EFF_R ** (EFF_MAX - 1):.3g}")
	if "--table" in sys.argv:
		print("| Etage | Kosten CR | Basis CR/s | Bauzeit |")
		for n in range(1, 51):
			print(f"| {n} | {floor_cost(n):,.0f} | {floor_income(n):,.1f} | {build_time(n):,.0f} s |")
		sys.exit(0)
	failed = False
	sync_errors, sync_notes = config_sync(root)
	for note in sync_notes:
		print("  (Hinweis)", note)
	if sync_errors:
		failed = True
		print("Config-Abgleich: FEHLER")
		for e in sync_errors:
			print("  -", e)
	else:
		print("Config-Abgleich: OK (Config/Tower.luau == Simulation)")
	quick = "--quick" in sys.argv
	free = campaign(Player("Gratis, guter Trader"), runs=2 if quick else 8)
	results = [free]
	passes = None
	if not quick:
		results.append(campaign(Player("Gratis, Nicht-Trader (nur Akademie/Quests)", trades=False, xp_hour=300), runs=2))
		passes = campaign(Player("x2+x3+VIP, guter Trader", passes=4.0, vip=1.1), runs=8)
		results.append(passes)
		results.append(campaign(Player("Gratis, starker Trader (r 4 %)", r=0.04), runs=2))
	prices = [upbase(50) * LEVEL_C[-1], upbase(50) * STAFF[3][1], EFF_BASE * EFF_R ** (EFF_MAX - 1), floor_cost(50)]
	worst = max(prices)
	highest = max(r["max"] for r in results)
	integral = all(float(floor_cost(n)).is_integer() for n in range(1, 51))
	g1 = worst < 1e14 and highest < CAP and integral and not any("G1" in e for e in sync_errors)
	print(f"G1 teuerster Einzelpreis {worst:.3g}, höchster Kontostand {highest:.3g}, Preise ganzzahlig: "
		+ ("OK" if g1 else "FEHLER"))
	failed = failed or not g1
	for name, ok, text in gates(free, passes):
		print(f"{name} {'OK' if ok else 'FEHLER'}: {text}")
		if not ok and not quick:
			failed = True
	sys.exit(1 if failed else 0)
