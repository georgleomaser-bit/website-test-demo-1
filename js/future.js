// Zukunfts-Ich: Wie sieht dein Geld mit 30, 40 oder 60 aus? Zinseszins in drei Szenarien, Kaufkraft,
// Meilensteine, Kauf-Rechner und eine teilbare Story-Karte. Reine Rechnung – Szenarien, keine Versprechen.
export const SCENARIOS = {
  safe: { label: "Vorsichtig", rate: 0.03, desc: "Tagesgeld & Anleihen" },
  balanced: { label: "Ausgewogen", rate: 0.06, desc: "Weltweiter Aktien-ETF" },
  bold: { label: "Mutig", rate: 0.08, desc: "Aktienlastig, schwankt stärker" },
};
export const INFLATION = 0.02;
export const TARGET_AGES = [30, 40, 50, 60, 67];

const KEY = "akytex-future";
export const DEFAULTS = { age: 18, start: 500, monthly: 50, scenario: "balanced", until: 40 };
export function loadPlan() {
  try {
    return sanitize({ ...DEFAULTS, ...JSON.parse(localStorage.getItem(KEY) || "{}") });
  } catch (_) {
    return { ...DEFAULTS };
  }
}
export function savePlan(p) {
  try {
    localStorage.setItem(KEY, JSON.stringify(sanitize(p)));
  } catch (_) {
    /* nur für diese Sitzung */
  }
}
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
export function sanitize(p) {
  const age = clamp(Math.round(+p.age || DEFAULTS.age), 10, 80);
  return {
    age,
    start: clamp(Math.round(+p.start || 0), 0, 10_000_000),
    monthly: clamp(Math.round(+p.monthly || 0), 0, 100_000),
    scenario: SCENARIOS[p.scenario] ? p.scenario : "balanced",
    until: clamp(Math.round(+p.until || DEFAULTS.until), age + 1, 100),
  };
}

// Monatlicher Sparplan mit Zinseszins (Rendite pro Jahr, monatlich verzinst)
export function project(plan, rate = SCENARIOS[plan.scenario].rate, monthly = plan.monthly) {
  const years = Math.max(1, plan.until - plan.age);
  const r = Math.pow(1 + rate, 1 / 12) - 1;
  let value = plan.start;
  let paid = plan.start;
  const series = [{ age: plan.age, value, paid }];
  for (let y = 1; y <= years; y++) {
    for (let m = 0; m < 12; m++) {
      value = value * (1 + r) + monthly;
      paid += monthly;
    }
    series.push({ age: plan.age + y, value, paid });
  }
  return { series, value, paid, gain: value - paid, years, real: realValue(value, years) };
}
export const realValue = (v, years) => v / Math.pow(1 + INFLATION, years);
// Was ein Kauf heute „wirklich“ kostet: das Geld, das bis zum Ziel-Alter daraus geworden wäre
export const futureCost = (price, years, rate = SCENARIOS.balanced.rate) => price * Math.pow(1 + rate, years);
// Wann knackst du 10.000 €, 100.000 €, 1 Mio.?
export function milestones(series) {
  return [10_000, 100_000, 1_000_000]
    .map((goal) => ({ goal, age: series.find((p) => p.value >= goal)?.age ?? null }))
    .filter((m) => m.age != null);
}

const eur0 = new Intl.NumberFormat("de-DE", { style: "currency", currency: "EUR", maximumFractionDigits: 0 });
export const money = (v) => eur0.format(Math.round(v));
// Für die Sprachausgabe: „212.000 Euro“ statt „212.345 €“
export function spoken(v) {
  if (v >= 1e6) return `${(v / 1e6).toLocaleString("de-DE", { maximumFractionDigits: 1 })} Millionen Euro`;
  const r = v >= 100_000 ? Math.round(v / 1000) * 1000 : v >= 10_000 ? Math.round(v / 100) * 100 : Math.round(v / 10) * 10;
  return `${r.toLocaleString("de-DE")} Euro`;
}

// Monolog für Aky: dein Zukunfts-Ich spricht zu dir
export function futureMonologue(plan, name) {
  const p = project(plan);
  const more = project(plan, undefined, plan.monthly + 25);
  const ms = milestones(p.series);
  const who = name ? `Hey ${name}.` : "Hey.";
  const first = ms[0] ? ` Die ersten ${ms[0].goal.toLocaleString("de-DE")} Euro hatten wir mit ${ms[0].age}.` : "";
  const big = ms.find((m) => m.goal >= 100_000);
  const bigLine = big && big !== ms[0] ? ` Mit ${big.age} waren es schon ${big.goal === 1e6 ? "eine Million" : "hunderttausend"}.` : "";
  const why = plan.monthly > 0 ? `Weil du ab heute ${plan.monthly} Euro im Monat anlegst` : "Weil du dein Geld angelegt hast";
  return `${who} Ich bin du – mit ${plan.until}. Ich wollte dir danke sagen. ${why}, habe ich jetzt rund ${spoken(p.value)}. Eingezahlt hast du davon nur ${spoken(p.paid)}, der Rest ist Zinseszins.${first}${bigLine} Kleiner Tipp von mir: Mit 25 Euro mehr im Monat wären es sogar ${spoken(more.value)}. Die Schwankungen unterwegs gehören dazu – bleib einfach dran. Wir sehen uns.`;
}

// ---------- Story-Karte (1080 × 1920) zum Teilen auf TikTok, Instagram & Co. ----------
async function fontsReady() {
  try {
    await Promise.all(["700 120px Unbounded", "800 60px Manrope", "700 40px Manrope", "600 36px Manrope"].map((f) => document.fonts.load(f)));
  } catch (_) {
    /* Systemschrift */
  }
}
function fit(g, text, font, max, start) {
  let size = start;
  do {
    g.font = font.replace("{s}", size);
    if (g.measureText(text).width <= max) break;
    size -= 4;
  } while (size > 20);
  return size;
}
function backdrop(g, W, H, rgb) {
  const bg = g.createLinearGradient(0, 0, 0, H);
  bg.addColorStop(0, "#04050b");
  bg.addColorStop(1, "#0a0714");
  g.fillStyle = bg;
  g.fillRect(0, 0, W, H);
  const glow = g.createRadialGradient(W / 2, H * 0.42, 0, W / 2, H * 0.42, W * 0.9);
  glow.addColorStop(0, `rgba(${rgb},0.42)`);
  glow.addColorStop(0.45, `rgba(${rgb},0.12)`);
  glow.addColorStop(1, "rgba(0,0,0,0)");
  g.fillStyle = glow;
  g.fillRect(0, 0, W, H);
  // Sterne (fester Zufall, damit jede Karte gleich edel aussieht)
  let s = 7;
  const rnd = () => ((s = (s * 16807) % 2147483647) / 2147483647);
  for (let i = 0; i < 260; i++) {
    const a = 0.15 + rnd() * 0.6;
    g.fillStyle = `rgba(255,255,255,${a})`;
    g.beginPath();
    g.arc(rnd() * W, rnd() * H, rnd() * 2.2 + 0.4, 0, Math.PI * 2);
    g.fill();
  }
  // Rahmen wie im HUD
  g.strokeStyle = `rgba(${rgb},0.55)`;
  g.lineWidth = 4;
  const c = 70;
  for (const [x, y, dx, dy] of [
    [48, 48, 1, 1],
    [W - 48, 48, -1, 1],
    [48, H - 48, 1, -1],
    [W - 48, H - 48, -1, -1],
  ]) {
    g.beginPath();
    g.moveTo(x + dx * c, y);
    g.lineTo(x, y);
    g.lineTo(x, y + dy * c);
    g.stroke();
  }
}
function brand(g, W, label, rgb) {
  g.textAlign = "center";
  g.fillStyle = "#ffffff";
  g.font = "700 64px Unbounded, Manrope, sans-serif";
  g.fillText("ΛKYTEX", W / 2, 190);
  g.fillStyle = `rgba(${rgb},0.95)`;
  g.font = "800 30px Manrope, sans-serif";
  g.letterSpacing = "12px";
  g.fillText(label, W / 2, 250);
  g.letterSpacing = "0px";
}
function footer(g, W, H, url, rgb, cta) {
  g.textAlign = "center";
  g.fillStyle = "#ffffff";
  g.font = "800 50px Manrope, sans-serif";
  g.fillText(cta, W / 2, H - 330);
  // Link-Pille
  const text = url.replace(/^https?:\/\//, "").replace(/\/$/, "");
  const size = fit(g, text, "700 {s}px Manrope, sans-serif", W - 260, 40);
  g.font = `700 ${size}px Manrope, sans-serif`;
  const w = Math.min(W - 160, g.measureText(text).width + 90);
  g.fillStyle = `rgba(${rgb},0.2)`;
  g.strokeStyle = `rgba(${rgb},0.8)`;
  g.lineWidth = 3;
  g.beginPath();
  if (g.roundRect) g.roundRect((W - w) / 2, H - 290, w, 92, 46);
  else g.rect((W - w) / 2, H - 290, w, 92);
  g.fill();
  g.stroke();
  g.fillStyle = "#ffffff";
  g.fillText(text, W / 2, H - 230);
  g.fillStyle = "rgba(255,255,255,0.45)";
  g.font = "600 26px Manrope, sans-serif";
  g.fillText("Szenario-Rechnung, keine Garantie · Übungsdepot · keine Anlageberatung", W / 2, H - 110);
}

export async function futureCard(plan, url, rgb = "120,200,255") {
  await fontsReady();
  const W = 1080;
  const H = 1920;
  const cv = document.createElement("canvas");
  cv.width = W;
  cv.height = H;
  const g = cv.getContext("2d");
  const p = project(plan);
  backdrop(g, W, H, rgb);
  brand(g, W, "MEIN ZUKUNFTS-ICH", rgb);
  g.fillStyle = "rgba(255,255,255,0.85)";
  g.font = "800 64px Manrope, sans-serif";
  g.fillText(`Ich mit ${plan.until}:`, W / 2, 470);
  const big = money(p.value);
  const size = fit(g, big, "700 {s}px Unbounded, Manrope, sans-serif", W - 140, 170);
  const grad = g.createLinearGradient(0, 520, 0, 700);
  grad.addColorStop(0, "#ffffff");
  grad.addColorStop(1, `rgb(${rgb})`);
  g.fillStyle = grad;
  g.font = `700 ${size}px Unbounded, Manrope, sans-serif`;
  g.fillText(big, W / 2, 650);
  g.fillStyle = "rgba(255,255,255,0.8)";
  g.font = "700 42px Manrope, sans-serif";
  g.fillText(`mit ${money(plan.monthly)} im Monat · ab ${plan.age}`, W / 2, 740);
  // Kurve: eingezahlt vs. Wert
  const X0 = 110;
  const X1 = W - 110;
  const Y0 = 1250;
  const Y1 = 830;
  const max = p.value || 1;
  const xy = (i, v) => [X0 + ((X1 - X0) * i) / (p.series.length - 1), Y0 - ((Y0 - Y1) * v) / max];
  const area = (key, fill) => {
    g.beginPath();
    g.moveTo(X0, Y0);
    p.series.forEach((pt, i) => g.lineTo(...xy(i, pt[key])));
    g.lineTo(X1, Y0);
    g.closePath();
    g.fillStyle = fill;
    g.fill();
  };
  const fillV = g.createLinearGradient(0, Y1, 0, Y0);
  fillV.addColorStop(0, `rgba(${rgb},0.55)`);
  fillV.addColorStop(1, `rgba(${rgb},0.04)`);
  area("value", fillV);
  area("paid", "rgba(255,255,255,0.14)");
  g.strokeStyle = `rgb(${rgb})`;
  g.lineWidth = 7;
  g.lineJoin = "round";
  g.beginPath();
  p.series.forEach((pt, i) => (i ? g.lineTo(...xy(i, pt.value)) : g.moveTo(...xy(i, pt.value))));
  g.stroke();
  g.fillStyle = "rgba(255,255,255,0.6)";
  g.font = "700 30px Manrope, sans-serif";
  g.textAlign = "left";
  g.fillText(`${plan.age}`, X0, Y0 + 50);
  g.textAlign = "right";
  g.fillText(`${plan.until}`, X1, Y0 + 50);
  g.textAlign = "center";
  // Kennzahlen
  const stats = [
    ["Eingezahlt", money(p.paid)],
    ["Zinseszins", "+" + money(p.gain)],
    ["Kaufkraft heute", money(p.real)],
  ];
  stats.forEach(([k, v], i) => {
    const cx = W / 2 + (i - 1) * 310;
    g.fillStyle = "rgba(255,255,255,0.55)";
    g.font = "700 28px Manrope, sans-serif";
    g.fillText(k.toUpperCase(), cx, 1400);
    g.fillStyle = "#ffffff";
    g.font = `800 ${fit(g, v, "800 {s}px Manrope, sans-serif", 290, 46)}px Manrope, sans-serif`;
    g.fillText(v, cx, 1462);
  });
  footer(g, W, H, url, rgb, "Und du? Triff dein Zukunfts-Ich:");
  return new Promise((r) => cv.toBlob(r, "image/png"));
}

export async function dnaCard(dna, url, rgb = "255,176,72") {
  await fontsReady();
  const W = 1080;
  const H = 1920;
  const cv = document.createElement("canvas");
  cv.width = W;
  cv.height = H;
  const g = cv.getContext("2d");
  backdrop(g, W, H, rgb);
  brand(g, W, "MEINE TRADER-DNA", rgb);
  g.fillStyle = "#ffffff";
  const t = dna.style || "Trader";
  g.font = `700 ${fit(g, t, "700 {s}px Unbounded, Manrope, sans-serif", W - 160, 110)}px Unbounded, Manrope, sans-serif`;
  g.fillText(t, W / 2, 470);
  // Score-Ring
  const cx = W / 2;
  const cy = 820;
  const R = 230;
  g.lineWidth = 34;
  g.strokeStyle = "rgba(255,255,255,0.1)";
  g.beginPath();
  g.arc(cx, cy, R, 0, Math.PI * 2);
  g.stroke();
  g.strokeStyle = `rgb(${rgb})`;
  g.lineCap = "round";
  g.beginPath();
  g.arc(cx, cy, R, -Math.PI / 2, -Math.PI / 2 + (Math.PI * 2 * (dna.score || 0)) / 100);
  g.stroke();
  g.lineCap = "butt";
  g.fillStyle = "#ffffff";
  g.font = "700 150px Unbounded, Manrope, sans-serif";
  g.fillText(String(dna.score ?? "–"), cx, cy + 40);
  g.fillStyle = "rgba(255,255,255,0.6)";
  g.font = "800 32px Manrope, sans-serif";
  g.fillText("DISZIPLIN-SCORE", cx, cy + 110);
  const stats = [
    ["Trefferquote", `${Math.round((dna.winRate || 0) * 100)} %`],
    ["Profit-Faktor", (dna.pf || 0).toLocaleString("de-DE", { maximumFractionDigits: 1 })],
    ["Trades", String(dna.n || 0)],
  ];
  stats.forEach(([k, v], i) => {
    const x = W / 2 + (i - 1) * 310;
    g.fillStyle = "rgba(255,255,255,0.55)";
    g.font = "700 28px Manrope, sans-serif";
    g.fillText(k.toUpperCase(), x, 1200);
    g.fillStyle = "#ffffff";
    g.font = "800 64px Manrope, sans-serif";
    g.fillText(v, x, 1275);
  });
  const line = dna.strengths?.[0] || dna.tips?.[0] || "";
  if (line) {
    g.fillStyle = "rgba(255,255,255,0.85)";
    g.font = "600 36px Manrope, sans-serif";
    // Zeilenumbruch
    const words = line.split(" ");
    let row = "";
    let y = 1380;
    for (const w of words) {
      const test = row ? row + " " + w : w;
      if (g.measureText(test).width > W - 200 && row) {
        g.fillText(row, W / 2, y);
        row = w;
        y += 50;
        if (y > 1500) break;
      } else row = test;
    }
    if (y <= 1500) g.fillText(row, W / 2, y);
  }
  footer(g, W, H, url, rgb, "Welcher Trader-Typ bist du?");
  return new Promise((r) => cv.toBlob(r, "image/png"));
}

// Teilen: auf dem Handy direkt in Story/Chat (Web Share), sonst als Bild speichern und Link kopieren
export async function shareImage(blob, name, text, url) {
  const file = new File([blob], name, { type: "image/png" });
  if (navigator.canShare?.({ files: [file] })) {
    try {
      await navigator.share({ files: [file], text: `${text} ${url}`, title: "AKYTEX" });
      return "shared";
    } catch (e) {
      if (e?.name === "AbortError") return "aborted";
    }
  }
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = name;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 4000);
  try {
    await navigator.clipboard.writeText(`${text} ${url}`);
    return "downloaded+copied";
  } catch (_) {
    return "downloaded";
  }
}
