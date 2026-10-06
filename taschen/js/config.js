// Arbeitstaschen – alle Einstellungen an einer Stelle (Name, Farben, Speicher, Server)

export const BRAND = {
  name: "Arbeitstaschen",
  short: "Taschen",
  tagline: "Dein persönlicher Projektmanager",
  version: "1.0.0",
};

// IndexedDB: dieselben Namen benutzt auch sw.js (dort von Hand gespiegelt)
export const DB = { name: "arbeitstaschen", version: 1, kv: "kv", files: "files" };

// Optionaler fester Server für Sync, Erinnerungen und KI (z. B. "https://taschen.1-2-3-4.sslip.io").
// Leer = automatisch: Läuft die App auf dem eigenen Server, wird er gefunden.
export const SERVER = { url: "" };

// Mail und Kalender: öffentliche App-Kennungen (Client-IDs) aus Google Cloud und Microsoft Entra.
// Leer = dieser Anbieter wird in der App nicht angeboten. Einrichtung: siehe TASCHEN.md, Abschnitt „Mail und Kalender“.
export const CONNECT = { google: "", microsoft: "" };

// Apple-Systemfarben [hell, dunkel]
export const COLORS = {
  blue: ["#007AFF", "#0A84FF"],
  indigo: ["#5856D6", "#5E5CE6"],
  purple: ["#AF52DE", "#BF5AF2"],
  pink: ["#FF2D55", "#FF375F"],
  red: ["#FF3B30", "#FF453A"],
  orange: ["#FF9500", "#FF9F0A"],
  yellow: ["#FFCC00", "#FFD60A"],
  green: ["#34C759", "#30D158"],
  mint: ["#00C7BE", "#63E6E2"],
  teal: ["#30B0C7", "#40C8E0"],
  cyan: ["#32ADE6", "#64D2FF"],
  brown: ["#A2845E", "#AC8E68"],
  gray: ["#8E8E93", "#98989D"],
};
export const COLOR_NAMES = {
  blue: "Blau", indigo: "Indigo", purple: "Lila", pink: "Pink", red: "Rot", orange: "Orange", yellow: "Gelb",
  green: "Grün", mint: "Mint", teal: "Türkis", cyan: "Cyan", brown: "Braun", gray: "Grau",
};

// Vorschläge beim Anlegen einer Tasche
export const EMOJIS = ["👜", "💼", "🎒", "📈", "🚀", "🤖", "🏢", "🤝", "📣", "🎬", "💳", "🖥️", "💡", "🎯", "📚", "🏠", "💪", "✈️", "🎨", "🧾", "⚖️", "🛠️", "🌱", "❤️"];

export const PRIOS = [
  { id: 0, label: "Keine", short: "", mark: "" },
  { id: 1, label: "Niedrig", short: "!", mark: "!" },
  { id: 2, label: "Mittel", short: "!!", mark: "!!" },
  { id: 3, label: "Hoch", short: "!!!", mark: "!!!" },
];

export const REPEATS = [
  { id: null, label: "Nie" },
  { id: "daily", label: "Täglich" },
  { id: "weekdays", label: "Werktags" },
  { id: "weekly", label: "Wöchentlich" },
  { id: "biweekly", label: "Alle 2 Wochen" },
  { id: "monthly", label: "Monatlich" },
  { id: "yearly", label: "Jährlich" },
];

export const DEFAULT_PROFILE = {
  name: "",
  updated: 0,
  dayStart: "08:00", // Tagesbriefing (Morgen-Erinnerung)
  dayEnd: "18:00", // Tagesabschluss
  focusCount: 3,
  weekStart: 1, // 1 = Montag
  reviewDay: 5, // 0 = Sonntag … 6 = Samstag
  workdays: [1, 2, 3, 4, 5],
  defaultRemind: 15, // Minuten vor Aufgaben mit Uhrzeit
  accent: "blue",
  theme: "auto", // auto | light | dark
  haptics: true,
  sounds: true,
  briefing: true,
  evening: true,
  onboarded: false,
};

export const LIMITS = {
  fileMax: 25 * 1024 * 1024, // 25 MB pro Datei
  syncFileMax: 10 * 1024 * 1024, // größere Dateien bleiben nur auf dem Gerät
  logMax: 400,
  undoMax: 30,
  tombstoneDays: 30,
};
