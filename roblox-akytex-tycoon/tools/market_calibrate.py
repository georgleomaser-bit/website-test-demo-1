#!/usr/bin/env python3
# =====================================================================
#  AKYTEX TYCOON – Kalibrier- und Balancing-Werkzeug für die Markt-Engine
#  Referenz-Implementierung des Preis-Modells aus docs/MARKET.md (Abschnitt 4–6).
#
#  Aufruf:  python3 tools/market_calibrate.py            (≈ 30–60 s, braucht numpy)
#           python3 tools/market_calibrate.py --quick    (weniger Seeds/Instrumente)
#
#  Gibt aus:
#    1) Volatilität je Risikoklasse und Zeitraum (1s … 8h), Autokorrelation, Korrelationen
#    2) Strategie-Backtest: Ø-Rendite je Spieltag (20 min) für Zufall, Naiv, Ampel, Smart …
#  Ziel (Akzeptanz, MARKET.md §17): Zufall ≈ 0 oder leicht negativ, Spam-Klicken klar negativ,
#  informierte Spieler deutlich positiv mit hoher Quote positiver Tage  ->  Skill statt Glück.
#
#  Die Hash-/Noise-Funktionen sind 1:1 so gebaut, wie sie in Luau umgesetzt werden
#  (32-Bit-Hash "lowbias32", Value-Noise mit linearer Interpolation, Oktaven 2 s … 4,5 h;
#  Oktaven-Index im Hash 0-basiert – in Luau also k - 1 bei 1-basierten Schleifen).
# =====================================================================
import argparse
import math

import numpy as np

M32 = 0xFFFFFFFF


def h32(x):
	# lowbias32 (Chris Wellons). In Luau: Multiplikation per 16-Bit-Split (siehe MARKET.md §4.2)
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


# ---------------------------------------------------------------- Noise-Felder
P0, K = 2, 14  # kleinste Periode 2 s, 14 Oktaven -> größte 16 384 s (≈ 4,5 h)
AMPS = [math.sqrt(P0 * 2**k) for k in range(K)]
AMPS[K - 1] *= 0.6  # oberste Oktaven dämpfen -> Mean-Reversion über Stunden
AMPS[K - 2] *= 0.36 ** 0.5
NORM = math.sqrt(sum(a * a for a in AMPS) * (2 / 3) * (1 / 3))  # Var(uni)=1/3, Lerp-Mittel 2/3


def field(seed, fid, ts):
	out = np.zeros(len(ts))
	for k in range(K):
		P = P0 * 2**k
		ph = hcomb(seed, fid, k, 777) % P
		u = (ts + ph) / P
		n = np.floor(u).astype(np.int64)
		f = u - n
		lo, hi = int(n.min()), int(n.max()) + 1
		lut = np.array([uni(seed, fid, k, v) for v in range(lo, hi + 1)])
		v0 = lut[n - lo]
		v1 = lut[n + 1 - lo]
		out += AMPS[k] * (v0 + (v1 - v0) * f)
	return out / NORM


def white(seed, fid, ts):
	return np.array([uni(seed, fid, 9001, int(t)) + uni(seed, fid, 9002, int(t)) + uni(seed, fid, 9003, int(t)) for t in ts])


# ---------------------------------------------------------------- Parameter (= Config/Market.luau)
SIG = {"Stabil": 0.03, "Normal": 0.055, "Wild": 0.10}
BETA, GAMMA, EPS = 0.45, 0.55, 0.70  # Markt / Sektor / Firma (Gewichte, Quadratsumme ≈ 1)
MICRO_K = 0.010  # Mikrostruktur-Rauschen je Sekunde = MICRO_K * Sigma (Bid/Ask-Bounce)
DAY = 1200  # 1 Spieltag = 20 min = 1200 Ticks (1 Hz)
DRIFT_DAY = 0.004  # Ø-Fundament-Drift je Spieltag
COST_SIDE = 0.0005 + 0.001  # halber Spread (Normal) + Gebühr Azubi je Seite
BANDS = [(0.50, 0.01, 0.03), (0.30, 0.03, 0.06), (0.15, 0.06, 0.12), (0.05, 0.12, 0.25)]  # leicht/deutlich/massiv/historisch
NEWS_MEAN_GAP = 1500  # s zwischen zwei Firmen-News je Firma (Ø)
KIND_P = {"fact": 0.55, "rumor": 0.25, "priced": 0.20}
TRUST_P = {1: 0.35, 2: 0.60, 3: 0.85}  # Bestätigungs-Quote eines Gerüchts je Quellen-Sterne
TRUST_MIX = [0.45, 0.35, 0.20]
DELAY, TAU = 8, 45  # Lesefenster und Reaktions-Rampe (s)


def smooth(x):
	x = np.clip(x, 0, 1)
	return x * x * (3 - 2 * x)


def build(seed, T, classes):
	ts = np.arange(T, dtype=np.int64)
	rng = np.random.default_rng(seed)
	M = field(seed, 1, ts)
	nsec = max(1, len(classes) // 6)
	sectors = [field(seed, 10 + s, ts) for s in range(nsec)]
	lp = np.zeros((len(classes), T))
	news = []
	for i, cls in enumerate(classes):
		I = field(seed, 100 + i, ts)
		w = white(seed, 200 + i, ts)
		base = SIG[cls] * (BETA * M + GAMMA * sectors[i % nsec] + EPS * I) + MICRO_K * SIG[cls] * w + DRIFT_DAY * ts / DAY
		ev = np.zeros(T)
		t = rng.exponential(NEWS_MEAN_GAP)
		while t < T - 400:
			u, acc = rng.random(), 0.0
			for p, lo, hi in BANDS:
				acc += p
				if u <= acc:
					mag, band = rng.uniform(lo, hi), lo
					break
			sign = 1 if rng.random() < 0.52 else -1
			J = sign * mag * (SIG[cls] / SIG["Normal"]) ** 0.5
			ta = int(t)
			x = ts - ta - DELAY
			kind = rng.choice(list(KIND_P), p=list(KIND_P.values()))
			trust = int(rng.choice([1, 2, 3], p=TRUST_MIX)) if kind == "rumor" else 3
			if kind == "fact":
				o = rng.uniform(0, 0.3)  # Übertreibung, die sich in ~5 min halb zurückbildet
				ev += np.where(x >= 0, smooth(x / TAU) * J * (1 + o) + np.where(x > TAU, -J * o * (1 - np.exp(-(x - TAU) / 300.0)), 0), 0)
			elif kind == "rumor":
				conf = rng.random() < TRUST_P[trust]
				x2 = ts - ta - 120  # Bestätigung/Dementi nach 2 min
				ev += np.where(x >= 0, smooth(x / TAU) * 0.5 * J, 0)
				ev += np.where(x2 >= 0, smooth(x2 / TAU) * (0.5 * J if conf else -1.0 * J), 0)
			else:  # "wie erwartet" -> sell the news
				ev += np.where(x >= 0, smooth(x / TAU) * (-1.0 * abs(J)) * sign, 0)
			news.append((ta, i, sign, band, kind, trust))
			t += rng.exponential(NEWS_MEAN_GAP)
		lp[i] = base + ev
	return lp, sorted(news)


def run(lp, news, strat, rng):
	n, T = lp.shape
	P = np.exp(lp)
	eq = np.zeros(T)
	cash, pos, ni, trades = 1e5, {}, 0, 0

	def buy(i, t, ex, frac=0.2, cap=5):
		nonlocal cash, trades
		if i in pos or len(pos) >= cap:
			return
		e = cash + sum(q * P[j, t] for j, (q, _) in pos.items())
		amt = min(cash, e * frac)
		if amt >= 1:
			pos[i] = (amt / (P[i, t] * (1 + COST_SIDE)), ex)
			cash -= amt
			trades += 1

	def sell(i, t):
		nonlocal cash
		q, _ = pos.pop(i)
		cash += q * P[i, t] * (1 - COST_SIDE)

	rd = {"Zufall": 0, "Spam": 0, "Halten": 0, "Naiv": 4, "Ampel": 20, "SmartLangsam": 20, "SmartSchnell": 4}[strat]
	if strat == "Halten":
		for i in range(n):
			buy(i, 0, T + 1, 1.0 / n, cap=n)
	for t in range(T):
		for i in [k for k, (q, e) in pos.items() if e <= t]:
			sell(i, t)
		if strat == "Zufall":
			if t % 60 == 0 and rng.random() < 0.5:
				buy(int(rng.integers(n)), t, t + int(rng.integers(60, 300)))
		elif strat == "Spam":
			if t > 0 and t % 3 == 0:
				i = t % n
				if lp[i, t] > lp[i, t - 1]:
					buy(i, t, t + 6)
		elif strat != "Halten":
			while ni < len(news) and news[ni][0] + rd <= t:
				ta, i, sign, band, kind, trust = news[ni]
				ni += 1
				if strat == "Naiv":
					ok = sign > 0
				elif strat == "Ampel":  # NOVA-Ampel zeigt nur bei Fakten-News eine Richtung (nach 20 s)
					ok = sign > 0 and kind == "fact"
				else:
					ok = sign > 0 and kind != "priced" and (kind == "fact" or trust == 3)
				hold = ta + (130 + TAU if kind == "rumor" else DELAY + TAU + 20)
				if ok:
					buy(i, t, hold)
				elif sign < 0 and i in pos and kind != "priced":
					sell(i, t)
		eq[t] = cash + sum(q * P[j, t] * (1 - COST_SIDE) for j, (q, _) in pos.items())
	d = eq[DAY - 1 :: DAY]
	prev = np.concatenate([[1e5], d[:-1]])
	return d / prev - 1, trades


def vol_table(seed):
	T = 86400
	ts = np.arange(T, dtype=np.int64)
	M, S, I, I2 = (field(seed, f, ts) for f in (1, 2, 3, 4))
	S2, I3 = field(seed, 5, ts), field(seed, 6, ts)
	w = white(seed, 9, ts)
	print("Einheits-Check Std(M,S,I) (Soll ≈ 1, eine Tagesstichprobe):", round(M.std(), 2), round(S.std(), 2), round(I.std(), 2))
	hz = [(1, "1s"), (5, "5s"), (60, "1m"), (300, "5m"), (1200, "Tag"), (7200, "2h"), (28800, "8h")]
	print(f"{'Klasse':7s} " + " ".join(f"{lab:>6s}" for _, lab in hz) + "  AC1(1m) AC1(1s)  Std(Niveau)")
	for cls, sig in SIG.items():
		lp = sig * (BETA * M + GAMMA * S + EPS * I) + MICRO_K * sig * w
		cells = [(lp[h:] - lp[:-h]).std() * 100 for h, _ in hz]
		r1m = lp[60::60] - lp[:-60:60]
		r1s = lp[1:] - lp[:-1]
		ac1m = np.corrcoef(r1m[:-1], r1m[1:])[0, 1]
		ac1s = np.corrcoef(r1s[:-1], r1s[1:])[0, 1]
		print(f"{cls:7s} " + " ".join(f"{c:5.2f}%" for c in cells) + f"  {ac1m:+.3f}  {ac1s:+.3f}   {lp.std() * 100:5.1f}%")
	sig = SIG["Normal"]
	a = sig * (BETA * M + GAMMA * S + EPS * I)
	b = sig * (BETA * M + GAMMA * S + EPS * I2)
	c = sig * (BETA * M + GAMMA * S2 + EPS * I3)

	def r(x):
		return x[60::60] - x[:-60:60]

	print(f"Korrelation 1m-Renditen: gleicher Sektor {np.corrcoef(r(a), r(b))[0, 1]:.2f}, anderer Sektor {np.corrcoef(r(a), r(c))[0, 1]:.2f}")


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--quick", action="store_true")
	args = ap.parse_args()
	print("=== 1) Volatilität ===")
	vol_table(123456)
	print("\n=== 2) Strategie-Backtest (Startkapital 100k, 20 % je Trade, max. 5 Positionen) ===")
	pattern = ["Stabil", "Stabil", "Normal", "Normal", "Normal", "Wild"]
	classes = pattern * (2 if args.quick else 6)
	seeds = [11, 22] if args.quick else [11, 22, 33]
	T = 4 * 3600
	res = {}
	for seed in seeds:
		lp, news = build(seed, T, classes)
		for s in ["Zufall", "Spam", "Halten", "Naiv", "Ampel", "SmartLangsam", "SmartSchnell"]:
			r, tr = run(lp, news, s, np.random.default_rng(seed))
			res.setdefault(s, []).append((r, tr))
	print(f"Instrumente: {len(classes)}, Seeds: {len(seeds)}, je {T // DAY} Spieltage")
	print(f"{'Strategie':13s} {'Ø/Tag':>8s} {'Median':>8s} {'Tage>0':>7s} {'Std':>7s} {'Trades/Tag':>10s}")
	for s, lst in res.items():
		r = np.concatenate([x for x, _ in lst])
		tr = sum(t for _, t in lst) / (len(lst) * T / DAY)
		print(f"{s:13s} {r.mean() * 100:7.2f}% {np.median(r) * 100:7.2f}% {np.mean(r > 0) * 100:6.0f}% {r.std() * 100:6.2f}% {tr:10.1f}")


if __name__ == "__main__":
	main()
