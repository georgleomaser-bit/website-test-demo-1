#!/usr/bin/env python3
# =====================================================================
#  AKYTEX TYCOON – Tower-Ökonomie-Simulation (Startwerte für docs/DESIGN.md §B9)
#  Aufruf: python3 tools/economy_sim.py [--quick | --table]   (≈ 40 s / 8 s, nur Standardbibliothek)
#  Besitzer-Paket: WP5 (Tower-Ökonomie). Startwerte hier == Config/Tower.luau + Config/Progression.luau (DESIGN §B5/§B9).
#
#  Modell (vereinfacht, aber mit denselben Formeln wie Config/Tower.luau + Shared/TowerMath.luau):
#   Einkommen/s = Basis × Perm × TraderFaktor × Pässe × Timed
#     Basis        = Gehalt + Σ Etage(n): I(n) × Raum × Stufe(L) × (1 + Σ Personal)
#     Perm         = 1 + 0,1·Effizienz + 0,25·Börsengänge + 0,1·Perk"Wachstum"   (additiv)
#     TraderFaktor = (1 + Lizenz-Bonus) × (1 + 0,05·Ruf)                        (nur Skill, nie Robux)
#     Pässe        = 1 + x2 + 2·x3  (x2 → ×2, x3 → ×3, beide → ×4) × VIP 1,10
#   Handel direkt: CR/s = r × Basis(Lizenz) × Bau-Kurs(Lizenz) / 1200  (nur aktiv, nie multipliziert)
#   Greedy-Käufer: kleinste Amortisationszeit (Kosten / Einkommensplus) unter Etage, Raum-Stufe, Personal, Effizienz.
#  Ziele (Release-Blocker, DESIGN.md §B9.9; gemessen mit Spieler "Gratis, guter Trader", r = 2,5 %/Börsentag):
#   G1 teuerster Einzelpreis < 1e14 und nie ein Kontostand ≥ 9e15
#   G2 Handels-Anteil in aktiven Sitzungen (direkt + Trader-Faktor): ≥ 15 % in Stufe 4–6, 25–45 % ab Stufe 7
#   G3 Direkt-Anteil (Gewinn-Transfer) in aktiven Sitzungen ≥ 10 % in Stufe 1–7
#   G4 Pacing: Etage 4 ≤ 5 min, Etage 10 ≤ 25 min, Etage 25 (1. Börsengang) Tag 2–5, Etage 50 Tag 28–56;
#      Robux-Pässe (x2+x3+VIP) dürfen Etage 50 höchstens 15 % früher erreichen (Lizenz-Tore!)
# =====================================================================
import math
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
	t, xp, ipo, perks = 0.0, 0.0, 0, {}
	stars = 0
	for k in range(runs):
		target = 50 if ipo >= 1 else 25
		res = run(p, xp0=xp, t0=t, ipo=ipo, perks=perks, stop_floor=target)
		if verbose:
			show(f"{p.name} Lauf {k + 1} (IPO {ipo}, Perks {perks})", res, t)
		t, xp = res["t"], res["xp"]
		if res["floors"] >= 50:
			print(f"  → Etage 50 erreicht an Tag {t / DAY:.1f}")
			return t
		if res["floors"] < 25:
			print("  → Etage 25 nicht erreicht (Zeitlimit)")
			return t
		stars += stars_for(res["spend"])
		ipo += 1
		left = stars
		perks = {}
		for name, cap in (("Wachstum", 10), ("Blitz", 3), ("Bau", 8), ("Tempo", 5)):
			lv = min(cap, left)
			perks[name] = lv
			left -= lv
	return t


if __name__ == "__main__":
	print("Etagen-Kosten:", ", ".join(f"{n}:{floor_cost(n):.3g}" for n in (2, 5, 9, 12, 16, 20, 25, 30, 36, 40, 44, 50)))
	print("Summe bis 50:", f"{sum(floor_cost(n) for n in range(1, 51)):.3g}",
		" max. Raum-Stufe 50:", f"{upbase(50) * LEVEL_C[-1]:.3g}", " max. Personal 50:", f"{upbase(50) * STAFF[3][1]:.3g}",
		" max. Effizienz:", f"{EFF_BASE * EFF_R ** (EFF_MAX - 1):.3g}")
	if "--table" in sys.argv:
		print("| Etage | Kosten CR | Basis CR/s | Bauzeit |")
		for n in range(1, 51):
			print(f"| {n} | {floor_cost(n):,.0f} | {floor_income(n):,.1f} | {build_time(n):,.0f} s |")
		sys.exit(0)
	worst = max(upbase(50) * LEVEL_C[-1], upbase(50) * STAFF[3][1], EFF_BASE * EFF_R ** (EFF_MAX - 1), floor_cost(50))
	print("G1 teuerster Einzelpreis:", f"{worst:.3g}", "OK" if worst < 1e14 else "FEHLER (≥ 1e14)")
	quick = "--quick" in sys.argv
	campaign(Player("Gratis, guter Trader"), runs=2 if quick else 8)
	if not quick:
		campaign(Player("Gratis, Nicht-Trader (nur Akademie/Quests)", trades=False, xp_hour=300), runs=2)
		campaign(Player("x2+x3+VIP, guter Trader", passes=4.0, vip=1.1), runs=8)
		campaign(Player("Gratis, starker Trader (r 4 %)", r=0.04), runs=2)
