#!/usr/bin/env python3
# =====================================================================
#  AKYTEX TYCOON – Kalibrier- und Balancing-Werkzeug für die Markt-Engine (tools/market_calibrate.py)
#  Besitzer: WP3 (Markt-Engine). Referenz-Implementierung des Preis-Modells aus docs/MARKET.md §4–§7 mit den
#  Änderungen aus DESIGN.md §C19 (Firmen CGVO/KRWK/PFFR, Tiko-Ampel) und den Release-Gates DESIGN.md §B9.10:
#    G5  Freie-Option-Gate: Strategie "Zufall + Gewinn-Transfer + Starthilfe" (Regeln §B8.2/§B8.4) zieht höchstens
#        15 % der CR-Menge der Strategie "Tiko-Ampel" (50 Börsentage × 3 Seeds).
#    G6  Skill-Gate MARKET §19.6: Zufall ≤ +0,2 %/Börsentag, Spam < −2 %, Ampel ≥ +0,5 %, Smart ≥ +1,5 %,
#        positive Tage Smart ≥ 75 %, Zufall ≤ 55 %.
#
#  Aufruf:  python3 tools/market_calibrate.py            (≈ 1–3 min, braucht numpy; Ausgabe "G5 OK" / "G6 OK")
#           python3 tools/market_calibrate.py --quick    (2 Seeds × 20 Börsentage, nur zum schnellen Ausprobieren)
#           python3 tools/market_calibrate.py --crash    (Plan-Crashs/-Rallyes mitsimulieren; Gates gelten ohne)
#  Rückgabe-Code 0 = alle Gates OK, 1 = mindestens ein Gate verfehlt.
#
#  Die Hash-/Noise-Funktionen sind 1:1 die aus Luau (Server/Market/Noise): 32-Bit-Hash "lowbias32", Value-Noise mit
#  linearer Interpolation, Oktaven 2 s … 16.384 s (Oktaven-Index im Hash 0-basiert = Luau k − 1), Feld-Ids wie in
#  der PriceEngine (Markt 1, Regime 2, Sektor 10 + Index, Firma 100 + Id, Mikro 200 + Id).
#  Die Ereignis-Ziehung nutzt numpy-Zufall (statistisch gleich, nicht bitgleich zum Spiel-Plan).
#  Jede Zahl unten = Config/Market.luau bzw. Config/Companies.luau (bei Änderungen dort hier nachziehen).
# =====================================================================
import argparse
import math
import sys

import numpy as np

M32 = 0xFFFFFFFF

# ---------------------------------------------------------------- Hash (skalar + numpy-vektorisiert)


def h32(x):
	# lowbias32 (Chris Wellons). In Luau: Multiplikation per 16-Bit-Split (MARKET.md §5.2)
	x &= M32
	x ^= x >> 16
	x = (x * 0x7FEB352D) & M32
	x ^= x >> 15
	x = (x * 0x846CA68B) & M32
	x ^= x >> 16
	return x


def hcomb(*parts):
	h = 0x9E3779B9
	for p in parts:
		h = h32(h ^ (p & M32))
	return h


def uni(*parts):  # gleichverteilt in [-1, 1)
	return hcomb(*parts) / 2147483648.0 - 1.0


def h32v(x):
	x = x & M32
	x ^= x >> np.uint64(16)
	x = (x * np.uint64(0x7FEB352D)) & np.uint64(M32)
	x ^= x >> np.uint64(15)
	x = (x * np.uint64(0x846CA68B)) & np.uint64(M32)
	x ^= x >> np.uint64(16)
	return x


def univ(a, b, c, d):
	"""uni(a, b, c, d) für ein Array d (a, b, c Skalare) – identisch zu hcomb/uni oben."""
	h = h32(0x9E3779B9 ^ (a & M32))
	h = h32(h ^ (b & M32))
	h = h32(h ^ (c & M32))
	dv = np.asarray(d, dtype=np.int64).astype(np.uint64) & np.uint64(M32)
	hv = h32v(np.uint64(h) ^ dv)
	return hv.astype(np.float64) / 2147483648.0 - 1.0


# Testvektoren MARKET §19.2 (Selbstprüfung beim Start)
VECTORS = [((123456, 1, 0, 0), 3076564673), ((123456, 1, 0, 1), 1222392628), ((123456, 1, 13, 7), 3917177298),
           ((987654321, 104, 5, 123456789), 4043101596), ((2147483647, 9, 9001, 86399), 2536699204)]

# ---------------------------------------------------------------- Noise-Felder (= Luau Noise.NewField/FieldAt)
P0, K = 2, 14
AMPS = [math.sqrt(P0 * 2**k) for k in range(K)]
AMPS[K - 1] *= 0.6
AMPS[K - 2] *= 0.6


def field(seed, fid, ts, k_lo=1, k_hi=K):
	out = np.zeros(len(ts))
	norm = math.sqrt(sum(AMPS[k - 1] ** 2 for k in range(k_lo, k_hi + 1)) * (2 / 3) * (1 / 3))
	for k in range(k_lo - 1, k_hi):
		P = P0 * 2**k
		ph = hcomb(seed, fid, k, 777) % P
		u = (ts + ph) / P
		n = np.floor(u).astype(np.int64)
		f = u - n
		lo, hi = int(n.min()), int(n.max()) + 1
		lut = univ(seed, fid, k, np.arange(lo, hi + 1))
		v0 = lut[n - lo]
		v1 = lut[n + 1 - lo]
		out += AMPS[k] * (v0 + (v1 - v0) * f)
	return out / norm


def white(seed, fid, ts):
	return univ(seed, fid, 9001, ts) + univ(seed, fid, 9002, ts) + univ(seed, fid, 9003, ts)


# ---------------------------------------------------------------- Parameter (= Config/Market.luau)
DAY = 1200
CLASSES = {  # Sigma, voller Spread (bps), News-Faktor, Crash-Beta
	"Stabil": (0.030, 4, 0.74, 0.7),
	"Normal": (0.055, 8, 1.00, 1.0),
	"Wild": (0.100, 16, 1.35, 1.4),
}
BETA, GAMMA, EPS, MICRO = 0.45, 0.55, 0.70, 0.010
REGIME_K, REGIME_OCT = 0.25, (10, 14)
DRIFT_BASE, DRIFT_Q, DRIFT_REVERT, DRIFT_MAX = 0.002, 0.004, 0.025, 0.04
BRAKE = [(0.9, 0.30), (1.6, 0.15)]
POS_BASE = 0.52
BANDS = [(0.50, 0.01, 0.03), (0.30, 0.03, 0.06), (0.15, 0.06, 0.12), (0.05, 0.12, 0.25)]
NEWS_MEAN_GAP = 1500
KIND_P = {"fact": 0.55, "rumor": 0.25, "priced": 0.20}
STARS_MIX = [0.45, 0.35, 0.20]
CONFIRM = {1: 0.35, 2: 0.60, 3: 0.85}
DELAY, TAU, RESOLVE = 8, 45, 120
OVERSHOOT_MAX, OVERSHOOT_DECAY = 0.3, 300.0
SECTOR_GAP, SENS, THEME_SHARE, THEME_MULT = 600, (0.6, 1.4), 0.4, (1, 2, 3.5)
MACRO_JUMP, MACRO_FLAT, MACRO_MINUTE = 0.015, 0.25, 10
EARN_Q, EARN_Z, EARN_J, EARN_MAX, EARN_SLOTS = 0.6, 0.8, 0.03, 0.20, (3, 7, 11, 15)
DIV_MINUTE = 19
CRASH_RATE, CRASH_DROP, RALLY_RISE, CRASH_SHARE = 1 / 12600, (0.12, 0.30), (0.08, 0.20), 0.5
SECTORS = ["T", "E", "M", "K", "G", "F"]
MATRIX = {
	"Rates": [-1.0, -0.3, -0.6, -0.3, -0.5, 0.8], "Growth": [0.6, 0.5, 0.8, 0.6, 0.5, 0.6],
	"Energy": [-0.2, 1.0, -0.8, -0.4, -0.1, 0.0], "Ai": [1.2, 0.4, 0.3, 0.0, 0.6, 0.2],
	"Chips": [-0.8, 0.0, -0.7, 0.0, -0.6, 0.0], "Heat": [0.0, 0.5, 0.0, 0.6, 0.2, -0.2],
	"Esport": [0.0, 0.0, 0.0, 0.2, 1.0, 0.0], "Space": [0.2, 0.0, 0.9, 0.0, 0.2, 0.0],
}
MACROS, THEMES = ["Rates", "Growth", "Energy"], ["Ai", "Chips", "Heat", "Esport", "Space"]

# Depot-Regeln (Config/Trading WP4 + DESIGN §B8.2/§B8.4/§B8.3, Lizenz Azubi I)
FEE = 0.0010  # Azubi-Gebühr je Seite
MIN_FEE = 1.0  # AKY
BASIS = 25000.0  # AKY
TRANSFER_THRESHOLD, TRANSFER_CAP = 1.02, 0.06
REFILL_BELOW, REFILL_TO, REFILL_EVERY = 0.5, 0.5, 72  # Starthilfe 1× je UTC-Tag = 72 Börsentage
BAU_KURS = 40  # CR je AKY (Azubi I)
MAX_WEIGHT, TRADE_PCT, MAX_POS = 0.30, 0.20, 5

# Die 36 Firmen (DESIGN §B6.2; umbenannt nach §C19: CGVO, KRWK, PFFR) = Config/Companies.luau
FIRMS = [
	(1, "CGVO", "Cognivo KI", "T", "Normal", 240, 0.0, "Trader"), (2, "KRWK", "Kernwerk Systems", "T", "Stabil", 180, 0.4, "Azubi"),
	(3, "QTRX", "Quantorix Quantum", "T", "Wild", 42, 0.0, "Fonds"), (4, "LMRA", "Lumora Chips", "T", "Normal", 115, 0.2, "Trader"),
	(5, "NMBY", "Nimbusly Cloud", "T", "Stabil", 88, 0.3, "Azubi"), (6, "PXWK", "Pixelwerk Robotics", "T", "Wild", 27, 0.0, "Fonds"),
	(7, "SNWK", "Sonnwerk Solar", "E", "Normal", 64, 0.3, "Azubi"), (8, "FSNT", "Fusionaut", "E", "Wild", 19, 0.0, "Fonds"),
	(9, "NBRZ", "Nordbrise Wind", "E", "Stabil", 52, 0.6, "Azubi"), (10, "HDRV", "Hydrava", "E", "Normal", 36, 0.0, "Fonds"),
	(11, "VLTR", "Voltaris", "E", "Normal", 98, 0.2, "Trader"), (12, "GTHM", "Geotherma", "E", "Stabil", 74, 0.7, "Trader"),
	(13, "ORBV", "Orbivo Space", "M", "Wild", 155, 0.0, "Fonds"), (14, "MGLN", "Magliner", "M", "Stabil", 61, 0.5, "Azubi"),
	(15, "VLCT", "Velocitra Motors", "M", "Normal", 210, 0.1, "Azubi"), (16, "DRNR", "Dronaro", "M", "Normal", 33, 0.0, "Trader"),
	(17, "ARLF", "Aerolift", "M", "Wild", 24, 0.0, "Fonds"), (18, "RTXO", "Robotaxo", "M", "Normal", 47, 0.0, "Trader"),
	(19, "KNSX", "Knusperix", "K", "Stabil", 58, 0.8, "Azubi"), (20, "BLBR", "Blubbro", "K", "Stabil", 41, 0.9, "Fonds"),
	(21, "SNKA", "Sneakora", "K", "Normal", 132, 0.3, "Trader"), (22, "BGPT", "Burgerplanet", "K", "Stabil", 77, 0.7, "Azubi"),
	(23, "PFFR", "Pfotenfreund", "K", "Normal", 29, 0.2, "Fonds"), (24, "SPWK", "Spielwerk Toys", "K", "Normal", 45, 0.4, "Trader"),
	(25, "ARCN", "Arcadeon Games", "G", "Normal", 96, 0.1, "Azubi"), (26, "STMR", "Streamora", "G", "Normal", 143, 0.0, "Trader"),
	(27, "PLVO", "Playverso VR", "G", "Wild", 38, 0.0, "Fonds"), (28, "MEMT", "Memetastic Media", "G", "Wild", 12, 0.0, "Fonds"),
	(29, "ESPV", "Esportiva Arena", "G", "Normal", 54, 0.2, "Trader"), (30, "NNBT", "Neonbeat Records", "G", "Stabil", 66, 0.5, "Azubi"),
	(31, "TWBK", "Towerbank", "F", "Stabil", 118, 1.0, "Azubi"), (32, "SKLA", "Skylinea", "F", "Stabil", 84, 1.1, "Azubi"),
	(33, "GLDR", "Goldader Mining", "F", "Normal", 71, 0.4, "Trader"), (34, "SCHF", "Sicherhafen", "F", "Stabil", 102, 1.2, "Trader"),
	(35, "KLPY", "Klickpay", "F", "Normal", 89, 0.0, "Fonds"), (36, "BKRZ", "Baukranz", "F", "Normal", 49, 0.5, "Fonds"),
]


def smooth(x):
	x = np.clip(x, 0.0, 1.0)
	return x * x * (3 - 2 * x)


# ---------------------------------------------------------------- Markt bauen
class Market:
	"""Log-Kurse aller Instrumente über T Ticks + Nachrichtenliste + Dividenden (wie Server: Plan je Börsentag)."""

	def __init__(self, seed, days, firms, crash=False):
		self.seed, self.days, self.firms = seed, days, firms
		T = days * DAY
		self.T = T
		ts = np.arange(T, dtype=np.int64)
		rng = np.random.default_rng(seed)
		n = len(firms)
		self.cls = [CLASSES[f[4]] for f in firms]
		self.half_spread = np.array([c[1] / 2 / 10000 for c in self.cls])
		M = field(seed, 1, ts)
		V = field(seed, 2, ts, *REGIME_OCT)
		S = {s: field(seed, 10 + i + 1, ts) for i, s in enumerate(SECTORS)}
		self.R = np.exp(REGIME_K * V)
		q = rng.uniform(-1, 1, n)
		self.q = q
		steps = np.zeros((n, T + 1))  # dauerhafte Sprünge (kumuliert später)
		bumps = np.zeros((n, T))  # Rampen/Übertreibungen (nur im aktiven Fenster)
		drift = np.zeros((n, T))
		val = np.zeros(n)  # Bewertung C (ohne Rauschen)
		drift_sum = np.zeros(n)
		news = []  # (t_a, i, Ton, Band, Art, Sterne)
		divs = []  # (tick, i, Rendite)
		sens_rng = np.random.default_rng(seed + 7)

		def ramp(i, t1, J):
			a = max(0, t1)
			b = min(T, t1 + TAU)
			if a < b:
				x = np.arange(a, b) - t1
				bumps[i, a:b] += J * smooth(x / TAU)
			if t1 + TAU < T:
				steps[i, max(0, t1 + TAU)] += J

		def fact(i, t1, J, o):
			ramp(i, t1, J * (1 + o))
			a = t1 + TAU
			if a < T:
				b = min(T, a + 3600)
				x = np.arange(a, b) - a
				bumps[i, a:b] += -J * o * (1 - np.exp(-x / OVERSHOOT_DECAY))
				if b < T:
					steps[i, b] += -J * o

		for d in range(days):
			d0 = d * DAY
			# Fundament-Drift mit Bewertungsanker (wie EventDirector BuildDay Schritt 0)
			rate = np.clip(DRIFT_BASE + DRIFT_Q * q - DRIFT_REVERT * (val + drift_sum), -DRIFT_MAX, DRIFT_MAX)
			drift[:, d0:d0 + DAY] = (drift_sum[:, None] + rate[:, None] * (np.arange(DAY)[None, :] / DAY))
			drift_sum += rate
			C = val + drift_sum
			pos = np.full(n, POS_BASE)
			for above, p in BRAKE:
				pos = np.where(C > above, p, pos)
				pos = np.where(C < -above, 1 - p, pos)
			F_day = np.zeros(n)
			# Quartalszahlen (+ Dividende der Zahler um :19)
			reporters = [i for i, f in enumerate(firms) if (d + f[0]) % 3 == 0]
			for idx, i in enumerate(reporters):
				te = d0 + EARN_SLOTS[(idx // 3) % 4] * 60
				s = EARN_Q * q[i] + EARN_Z * rng.normal()
				J = float(np.clip(EARN_J * s * self.cls[i][2], -EARN_MAX, EARN_MAX))
				ramp(i, te + DELAY, J)
				F_day[i] += J
				news.append((te, i, 1 if J >= 0 else -1, 0, "earn", 3))
				if firms[i][6] > 0:
					tx = d0 + DIV_MINUTE * 60
					y = firms[i][6] / 100.0
					steps[i, tx] += math.log(1 - y)
					F_day[i] += math.log(1 - y)
					divs.append((tx, i, y))
			# Makro :10
			sm = float(np.clip(rng.normal(), -2, 2))
			kind = MACROS[int(rng.integers(3))]
			if abs(sm) >= MACRO_FLAT:
				for i, f in enumerate(firms):
					J = MACRO_JUMP * MATRIX[kind][SECTORS.index(f[3])] * sm * self.cls[i][2]
					if J != 0:
						ramp(i, d0 + MACRO_MINUTE * 60 + DELAY, J)
						F_day[i] += J
			# Firmen-News (Poisson je Firma)
			for i in range(n):
				t = rng.exponential(NEWS_MEAN_GAP)
				while t < DAY:
					ta = d0 + int(t)
					u, acc = rng.random(), 0.0
					for bi, (p, lo, hi) in enumerate(BANDS):
						acc += p
						if u <= acc:
							mag, band = rng.uniform(lo, hi), bi + 1
							break
					sign = 1 if rng.random() < pos[i] else -1
					J = sign * mag * self.cls[i][2]
					kind_n = rng.choice(list(KIND_P), p=list(KIND_P.values()))
					stars = int(rng.choice([1, 2, 3], p=STARS_MIX)) if kind_n == "rumor" else 3
					if kind_n == "fact":
						fact(i, ta + DELAY, J, rng.uniform(0, OVERSHOOT_MAX))
						F_day[i] += J
					elif kind_n == "rumor":
						conf = rng.random() < CONFIRM[stars]
						ramp(i, ta + DELAY, 0.5 * J)
						second = 0.5 * J if conf else -J
						ramp(i, ta + RESOLVE + DELAY, second)
						F_day[i] += 0.5 * J + second
					else:  # "wie erwartet" -> sell the news
						ramp(i, ta + DELAY, -J)
						F_day[i] += -J
					news.append((ta, i, sign, band, kind_n, stars))
					t += rng.exponential(NEWS_MEAN_GAP)
			# Sektor-News & Themen
			t = rng.exponential(SECTOR_GAP)
			while t < DAY:
				ta = d0 + int(t)
				if rng.random() < THEME_SHARE:
					theme = THEMES[int(rng.integers(5))]
					lv = rng.random()
					mult = THEME_MULT[0 if lv < 0.5 else (1 if lv < 0.85 else 2)]
					for i, f in enumerate(firms):
						fac = MATRIX[theme][SECTORS.index(f[3])]
						if fac:
							J = MACRO_JUMP * fac * mult * self.cls[i][2] * sens_rng.uniform(*SENS)
							ramp(i, ta + DELAY, J)
							F_day[i] += J
				else:
					sec = SECTORS[int(rng.integers(6))]
					u, acc = rng.random(), 0.0
					for p, lo, hi in BANDS:
						acc += p
						if u <= acc:
							mag = rng.uniform(lo, hi)
							break
					sign = 1 if rng.random() < POS_BASE else -1
					for i, f in enumerate(firms):
						if f[3] == sec:
							J = sign * mag * self.cls[i][2] * sens_rng.uniform(*SENS)
							ramp(i, ta + DELAY, J)
							F_day[i] += J
				t += rng.exponential(SECTOR_GAP)
			# optional: Plan-Crashs/-Rallyes (Warnphase 180 s, Fall 60–120 s, Erholung 40–60 % über 10–20 min)
			if crash:
				t = rng.exponential(1 / CRASH_RATE)
				while t < DAY:
					tw = d0 + int(t)
					is_crash = rng.random() < CRASH_SHARE
					strength = rng.uniform(*(CRASH_DROP if is_crash else RALLY_RISE))
					fall, rec, share = int(rng.uniform(60, 120)), int(rng.uniform(600, 1200)), rng.uniform(0.4, 0.6)
					t1 = tw + 180 + DELAY
					for i in range(n):
						move = min(0.6, strength * self.cls[i][3])
						J = math.log(1 - move) if is_crash else math.log(1 + move)
						a, b = max(0, t1), min(T, t1 + fall)
						if a < b:
							bumps[i, a:b] += J * smooth((np.arange(a, b) - t1) / fall)
						a2, b2 = max(0, t1 + fall), min(T, t1 + fall + rec)
						if a2 < b2:
							bumps[i, a2:b2] += J - share * J * smooth((np.arange(a2, b2) - t1 - fall) / rec)
						if t1 + fall + rec < T:
							steps[i, t1 + fall + rec] += J * (1 - share)
						F_day[i] += J * (1 - share)
					t += rng.exponential(1 / CRASH_RATE)
			val += F_day
		E = np.cumsum(steps[:, :T], axis=1) + bumps
		lp = np.zeros((n, T))
		for i, f in enumerate(firms):
			sig = self.cls[i][0]
			I = field(seed, 100 + f[0], ts)
			w = white(seed, 200 + f[0], ts)
			noise = BETA * M + GAMMA * S[f[3]] + EPS * I
			noise -= noise[0]  # N0: stetiger Start
			lp[i] = math.log(f[5]) + drift[i] + E[i] + sig * (self.R * noise + MICRO * w)
		self.lp = lp
		self.P = np.exp(lp)
		self.news = sorted(news)
		self.divs = sorted(divs)


# ---------------------------------------------------------------- Strategien
STRATS = ["Zufall", "Spam", "Halten", "Naiv", "Ampel", "SmartLangsam", "SmartSchnell"]
READ_DELAY = {"Zufall": 0, "ZufallMax": 0, "Spam": 0, "Halten": 0, "Naiv": 4, "Ampel": 20, "SmartLangsam": 20, "SmartSchnell": 4}


class Depot:
	def __init__(self, mkt, cash, max_pos=MAX_POS, pct=TRADE_PCT):
		self.m, self.cash, self.pos, self.trades = mkt, cash, {}, 0
		self.max_pos, self.pct = max_pos, pct
		self.div_i = 0

	def nav(self, t):
		P, hs = self.m.P, self.m.half_spread
		return self.cash + sum(q * P[j, t] * (1 - hs[j] * self.m.R[t]) for j, (q, _) in self.pos.items())

	def buy(self, i, t, until, pct=None):
		if i in self.pos or len(self.pos) >= self.max_pos:
			return
		nav = self.nav(t)
		amt = min(self.cash, nav * min(pct or self.pct, MAX_WEIGHT))
		ask = self.m.P[i, t] * (1 + self.m.half_spread[i] * self.m.R[t])
		fee = max(MIN_FEE, amt * FEE)
		if amt - fee < ask:
			return
		self.pos[i] = ((amt - fee) / ask, until)
		self.cash -= amt
		self.trades += 1

	def sell(self, i, t):
		q, _ = self.pos.pop(i)
		gross = q * self.m.P[i, t] * (1 - self.m.half_spread[i] * self.m.R[t])
		self.cash += gross - min(gross, max(MIN_FEE, gross * FEE))

	def dividends(self, t):
		divs = self.m.divs
		while self.div_i < len(divs) and divs[self.div_i][0] <= t:
			tx, i, y = divs[self.div_i]
			self.div_i += 1
			if i in self.pos:
				# Anspruch = Bestand im Ex-Tick, Betrag = Kurs vor dem Abschlag · Rendite
				self.cash += self.pos[i][0] * self.m.P[i, tx - 1] * y


def run(mkt, strat, rng, depot=None, universe=None, transfer=False, refill=False):
	"""Tagesrenditen (Modified Dietz ohne Flüsse) + Trades; mit transfer/refill zusätzlich CR-Summe."""
	n, T = mkt.lp.shape
	uni_ids = list(range(n)) if universe is None else universe
	dep = depot or Depot(mkt, 1e5)
	rd = READ_DELAY[strat]
	ni = 0
	credits, last_transfer_day, last_refill_day = 0, -1, -10**9
	day_start_nav, rets = dep.nav(0), []
	if strat == "Halten":
		for i in uni_ids:
			dep.max_pos = len(uni_ids)
			dep.buy(i, 0, T + 1, 1.0 / len(uni_ids))
	for t in range(T):
		dep.dividends(t)
		for i in [k for k, (q, e) in dep.pos.items() if e <= t]:
			dep.sell(i, t)
		if strat == "Zufall":
			if t % 60 == 0 and rng.random() < 0.5:
				dep.buy(uni_ids[int(rng.integers(len(uni_ids)))], t, t + int(rng.integers(60, 300)))
		elif strat == "ZufallMax":  # aggressiver Zufall: volle Klumpen-Grenze, hält bis Tagesende
			if t % DAY == 5:
				for _ in range(3):
					dep.buy(uni_ids[int(rng.integers(len(uni_ids)))], t, (t // DAY + 1) * DAY - 1, MAX_WEIGHT)
		elif strat == "Spam":
			if t > 0 and t % 3 == 0:
				i = uni_ids[t % len(uni_ids)]
				if mkt.lp[i, t] > mkt.lp[i, t - 1]:
					dep.buy(i, t, t + 6)
		elif strat != "Halten":
			while ni < len(mkt.news) and mkt.news[ni][0] + rd <= t:
				ta, i, sign, band, kind, stars = mkt.news[ni]
				ni += 1
				if i not in uni_ids or kind == "earn":
					continue
				if strat == "Naiv":
					ok = sign > 0
				elif strat == "Ampel":  # Tiko-Ampel zeigt nur bei Fakten-News eine Richtung (nach 20 s)
					ok = sign > 0 and kind == "fact"
				else:
					ok = sign > 0 and kind != "priced" and (kind == "fact" or stars == 3)
				hold = ta + (RESOLVE + DELAY + TAU + 10 if kind == "rumor" else DELAY + TAU + 20)
				if ok:
					dep.buy(i, t, hold)
				elif sign < 0 and i in dep.pos and kind != "priced":
					dep.sell(i, t)
		if t % DAY == DAY - 1:  # Glocke: Tagesschluss, Gewinn-Transfer (§B8.2), Starthilfe (§B8.4)
			day = t // DAY
			nav = dep.nav(t)
			flow = 0.0
			if transfer and day != last_transfer_day and nav >= TRANSFER_THRESHOLD * BASIS:
				amount = max(0.0, min(dep.cash, nav - BASIS, TRANSFER_CAP * BASIS))
				if amount > 0:
					dep.cash -= amount
					credits += math.floor(amount * 100 * BAU_KURS / 100)
					last_transfer_day = day
					flow -= amount
			nav_after = dep.nav(t)
			if refill and not dep.pos and nav_after < REFILL_BELOW * BASIS and day - last_refill_day >= REFILL_EVERY:
				add = REFILL_TO * BASIS - nav_after
				dep.cash += add
				flow += add
				last_refill_day = day
			rets.append((nav - day_start_nav) / max(1e-9, day_start_nav))
			day_start_nav = dep.nav(t)
	return np.array(rets), dep.trades, credits


# ---------------------------------------------------------------- Ausgaben
def vol_table(seed):
	T = 86400
	ts = np.arange(T, dtype=np.int64)
	M, S, I, I2 = (field(seed, f, ts) for f in (1, 11, 101, 102))
	S2, I3 = field(seed, 12, ts), field(seed, 107, ts)
	w = white(seed, 209, ts)
	print("Einheits-Check Std(M,S,I) (Soll ≈ 1, eine Tagesstichprobe):", round(M.std(), 2), round(S.std(), 2), round(I.std(), 2))
	hz = [(1, "1s"), (5, "5s"), (60, "1m"), (300, "5m"), (1200, "Tag"), (7200, "2h"), (28800, "8h")]
	print(f"{'Klasse':7s} " + " ".join(f"{lab:>6s}" for _, lab in hz) + "  AC1(1m) AC1(1s)  Std(Niveau)")
	for cls, (sig, _, _, _) in CLASSES.items():
		lp = sig * (BETA * M + GAMMA * S + EPS * I) + MICRO * sig * w
		cells = [(lp[h:] - lp[:-h]).std() * 100 for h, _ in hz]
		r1m = lp[60::60] - lp[:-60:60]
		r1s = lp[1:] - lp[:-1]
		ac1m = np.corrcoef(r1m[:-1], r1m[1:])[0, 1]
		ac1s = np.corrcoef(r1s[:-1], r1s[1:])[0, 1]
		print(f"{cls:7s} " + " ".join(f"{c:5.2f}%" for c in cells) + f"  {ac1m:+.3f}  {ac1s:+.3f}   {lp.std() * 100:5.1f}%")
	sig = CLASSES["Normal"][0]
	a = sig * (BETA * M + GAMMA * S + EPS * I)
	b = sig * (BETA * M + GAMMA * S + EPS * I2)
	c = sig * (BETA * M + GAMMA * S2 + EPS * I3)

	def r(x):
		return x[60::60] - x[:-60:60]

	print(f"Korrelation 1m-Renditen: gleicher Sektor {np.corrcoef(r(a), r(b))[0, 1]:.2f}, anderer Sektor {np.corrcoef(r(a), r(c))[0, 1]:.2f}")


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--quick", action="store_true", help="2 Seeds × 20 Börsentage")
	ap.add_argument("--crash", action="store_true", help="Plan-Crashs/-Rallyes mitsimulieren")
	ap.add_argument("--days", type=int, default=0)
	args = ap.parse_args()
	for parts, expected in VECTORS:
		assert hcomb(*parts) == expected, f"Testvektor {parts} falsch"
	assert abs(univ(123456, 1, 0, np.array([0]))[0] - 0.432637066114694) < 1e-12, "vektorisierter Hash falsch"

	seeds = [11, 22] if args.quick else [11, 22, 33]
	days = args.days or (20 if args.quick else 50)
	print("=== 1) Volatilität ===")
	vol_table(123456)

	print(f"\n=== 2) Strategie-Backtest (G6): alle 36 Firmen, {len(seeds)} Seeds × {days} Börsentage, Start 100k, 20 % je Trade, max. 5 ===")
	res = {}
	g5 = {"Zufall": [], "ZufallMax": [], "Ampel": []}
	azubi = [i for i, f in enumerate(FIRMS) if f[7] == "Azubi"]
	for seed in seeds:
		mkt = Market(seed, days, FIRMS, crash=args.crash)
		for s in STRATS:
			r, tr, _ = run(mkt, s, np.random.default_rng(seed))
			res.setdefault(s, []).append((r, tr))
		# G5: Depot nach Lizenz Azubi I (Basis 25.000 AKY, 12 Azubi-Werte), Gewinn-Transfer an jeder Glocke + Starthilfe
		for s in g5:
			_, _, cr = run(mkt, s, np.random.default_rng(seed + 1000), depot=Depot(mkt, BASIS), universe=azubi,
			               transfer=True, refill=True)
			g5[s].append(cr)
	print(f"{'Strategie':13s} {'Ø/Tag':>8s} {'Median':>8s} {'Tage>0':>7s} {'Std':>7s} {'Trades/Tag':>10s}")
	summary = {}
	for s, lst in res.items():
		r = np.concatenate([x for x, _ in lst])
		tr = sum(t for _, t in lst) / (len(lst) * days)
		summary[s] = (r.mean() * 100, np.mean(r > 0) * 100)
		print(f"{s:13s} {r.mean() * 100:7.2f}% {np.median(r) * 100:7.2f}% {np.mean(r > 0) * 100:6.0f}% {r.std() * 100:6.2f}% {tr:10.1f}")

	ok_all = True
	print("\n=== 3) Gate G6 (Skill-Gate, MARKET §19.6) ===")
	checks = [
		("Zufall ≤ +0,2 %/Tag", summary["Zufall"][0] <= 0.2, f"{summary['Zufall'][0]:+.2f} %"),
		("Spam < −2 %/Tag", summary["Spam"][0] < -2.0, f"{summary['Spam'][0]:+.2f} %"),
		("Tiko-Ampel ≥ +0,5 %/Tag", summary["Ampel"][0] >= 0.5, f"{summary['Ampel'][0]:+.2f} %"),
		("Smart ≥ +1,5 %/Tag (langsam)", summary["SmartLangsam"][0] >= 1.5, f"{summary['SmartLangsam'][0]:+.2f} %"),
		("Smart ≥ +1,5 %/Tag (schnell)", summary["SmartSchnell"][0] >= 1.5, f"{summary['SmartSchnell'][0]:+.2f} %"),
		("positive Tage Smart ≥ 75 %", min(summary["SmartLangsam"][1], summary["SmartSchnell"][1]) >= 75,
		 f"{min(summary['SmartLangsam'][1], summary['SmartSchnell'][1]):.0f} %"),
		("positive Tage Zufall ≤ 55 %", summary["Zufall"][1] <= 55, f"{summary['Zufall'][1]:.0f} %"),
	]
	for label, ok, value in checks:
		ok_all &= ok
		print(f"  {'OK  ' if ok else 'FAIL'} {label:32s} {value}")
	print("G6 OK" if all(ok for _, ok, _ in checks) else "G6 FAIL")

	print(f"\n=== 4) Gate G5 (Freie-Option-Gate, §B9.10): Lizenz Azubi I, Basis {BASIS:,.0f} AKY, Bau-Kurs {BAU_KURS}, "
	      f"Schwelle {TRANSFER_THRESHOLD:.2f} × Basis, Tageslimit {TRANSFER_CAP:.0%} ===")
	cr_ampel = sum(g5["Ampel"])
	for s in g5:
		share = sum(g5[s]) / max(1, cr_ampel)
		print(f"  {s:10s} CR gesamt {sum(g5[s]):>14,.0f}   Anteil vs. Tiko-Ampel {share * 100:6.1f} %")
	share = sum(g5["Zufall"]) / max(1, cr_ampel)
	share_max = sum(g5["ZufallMax"]) / max(1, cr_ampel)
	g5_ok = share <= 0.15
	ok_all &= g5_ok
	print(f"  {'OK  ' if g5_ok else 'FAIL'} Zufall + Gewinn-Transfer + Starthilfe ≤ 15 % der Tiko-Ampel: {share * 100:.1f} %")
	print(f"  (Info) aggressiver Zufall (volle Klumpen-Grenze, hält den Tag): {share_max * 100:.1f} %"
	      + ("" if share_max <= 0.15 else "  -> Varianz-Option der Tages-Abschöpfung (Schwelle/Deckel ändern sie kaum; "
	                                       "Regel-Vorschlag für WP4/Lead: nur realisierte Gewinne seit dem letzten Transfer)"))
	print("G5 OK" if g5_ok else "G5 FAIL")
	return 0 if ok_all else 1


if __name__ == "__main__":
	sys.exit(main())
