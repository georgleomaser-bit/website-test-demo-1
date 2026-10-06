// Arbeitstaschen – eigene Inline-SVG-Symbole im Stil von SF Symbols (Linie 1.8, runde Enden)

// ---------- Zahnrad (einmal berechnet) ----------
function gearPath() {
  const n = 8, R = 9.6, r = 7.4, cx = 12, cy = 12;
  const pt = (rad, deg) => {
    const a = (deg * Math.PI) / 180;
    return `${(cx + rad * Math.cos(a)).toFixed(2)} ${(cy + rad * Math.sin(a)).toFixed(2)}`;
  };
  let d = "";
  for (let i = 0; i < n; i++) {
    const b = (i * 360) / n - 90;
    d += `${i ? "L" : "M"}${pt(r, b - 13)} L${pt(R, b - 8)} L${pt(R, b + 8)} L${pt(r, b + 13)} A${r} ${r} 0 0 1 ${pt(r, b + 360 / n - 13)} `;
  }
  return d + "Z";
}

// ---------- Pfade ----------
const dot = (x, y, r = 1.15) => `<circle cx="${x}" cy="${y}" r="${r}" fill="currentColor" stroke="none"/>`;

const P = {
  sun: `<circle cx="12" cy="12" r="4"/><path d="M12 2.6v2.1M12 19.3v2.1M4.7 4.7l1.5 1.5M17.8 17.8l1.5 1.5M2.6 12h2.1M19.3 12h2.1M4.7 19.3l1.5-1.5M17.8 6.2l1.5-1.5"/>`,
  star: `<path d="M12 3.4l2.55 5.36 5.88.78-4.3 4.08 1.08 5.83L12 16.62l-5.21 2.83 1.08-5.83-4.3-4.08 5.88-.78z"/>`,
  starFill: `<path fill="currentColor" d="M12 3.4l2.55 5.36 5.88.78-4.3 4.08 1.08 5.83L12 16.62l-5.21 2.83 1.08-5.83-4.3-4.08 5.88-.78z"/>`,
  calendar: `<rect x="3.5" y="5" width="17" height="15.5" rx="3.6"/><path d="M3.5 10h17M8 3v4M16 3v4"/>${dot(8, 14)}${dot(12, 14)}${dot(16, 14)}${dot(8, 17.3)}${dot(12, 17.3)}`,
  calendarPlus: `<rect x="3.5" y="5" width="17" height="15.5" rx="3.6"/><path d="M3.5 10h17M8 3v4M16 3v4M12 12.6v5.2M9.4 15.2h5.2"/>`,
  calendarCheck: `<rect x="3.5" y="5" width="17" height="15.5" rx="3.6"/><path d="M3.5 10h17M8 3v4M16 3v4M9 15.2l2.1 2.1 4-4.2"/>`,
  tray: `<path d="M3.5 13.5l2.6-7.2A2 2 0 0 1 8 5h8a2 2 0 0 1 1.9 1.3l2.6 7.2V18a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"/><path d="M3.5 13.5H8l1.2 2.2h5.6l1.2-2.2h4.5"/>`,
  bag: `<rect x="3" y="7.2" width="18" height="12.8" rx="3.4"/><path d="M8.6 7.2V5.7A1.7 1.7 0 0 1 10.3 4h3.4a1.7 1.7 0 0 1 1.7 1.7v1.5M3 12.6h18"/><path d="M10.6 11.6h2.8v2.2h-2.8z"/>`,
  chart: `<path d="M3.8 20.2h16.4"/><rect x="5.2" y="11.5" width="3.2" height="6.2" rx="1.1"/><rect x="10.4" y="7.5" width="3.2" height="10.2" rx="1.1"/><rect x="15.6" y="4.2" width="3.2" height="13.5" rx="1.1"/>`,
  gear: `<path d="${gearPath()}"/><circle cx="12" cy="12" r="3.1"/>`,
  plus: `<path d="M12 5v14M5 12h14"/>`,
  minus: `<path d="M5 12h14"/>`,
  search: `<circle cx="10.8" cy="10.8" r="6.4"/><path d="M15.6 15.6l4.6 4.6"/>`,
  check: `<path d="M5 12.6l4.3 4.3L19.2 7"/>`,
  checkCircle: `<circle cx="12" cy="12" r="8.6"/><path d="M8.2 12.3l2.6 2.6 5-5.3"/>`,
  checklist: `<path d="M3.8 7.2l1.6 1.6 2.9-3M3.8 15.2l1.6 1.6 2.9-3M11.5 7.5h8.7M11.5 15.5h8.7"/>`,
  bell: `<path d="M6 16.6V11a6 6 0 0 1 12 0v5.6l1.6 1.9H4.4z"/><path d="M9.9 20.6a2.3 2.3 0 0 0 4.2 0"/>`,
  bellOff: `<path d="M8.3 5.7A6 6 0 0 1 18 11v4.2M18 18.5H4.4L6 16.6V11c0-.8.2-1.6.4-2.3M9.9 20.6a2.3 2.3 0 0 0 4.2 0M4 4l16 16"/>`,
  sync: `<path d="M7.4 18.6H17a4 4 0 0 0 .55-7.96 5.6 5.6 0 0 0-10.75 1.4A3.3 3.3 0 0 0 7.4 18.6z"/><path d="M10 13.4l2-2 2 2M12 11.5v4.6"/>`,
  cloud: `<path d="M7.4 18.6H17a4 4 0 0 0 .55-7.96 5.6 5.6 0 0 0-10.75 1.4A3.3 3.3 0 0 0 7.4 18.6z"/>`,
  cloudOff: `<path d="M9.2 7a5.6 5.6 0 0 1 8.35 3.64A4 4 0 0 1 19.6 17.8M16 18.6H7.4a3.3 3.3 0 0 1-.6-6.56M4 4l16 16"/>`,
  share: `<path d="M12 3.6v11M8.2 7.3L12 3.6l3.8 3.7"/><path d="M8.6 10.4H7a2 2 0 0 0-2 2V18.4a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6a2 2 0 0 0-2-2h-1.6"/>`,
  trash: `<path d="M4.5 6.6h15M9.5 6.6V5.1a1.5 1.5 0 0 1 1.5-1.5h2a1.5 1.5 0 0 1 1.5 1.5v1.5M6.5 6.6l.8 12a2 2 0 0 0 2 1.9h5.4a2 2 0 0 0 2-1.9l.8-12M10 10.6v6M14 10.6v6"/>`,
  ellipsis: `${dot(5.5, 12, 1.6)}${dot(12, 12, 1.6)}${dot(18.5, 12, 1.6)}`,
  chevronRight: `<path d="M9.5 5.5L16 12l-6.5 6.5"/>`,
  chevronLeft: `<path d="M14.5 5.5L8 12l6.5 6.5"/>`,
  chevronDown: `<path d="M5.5 9.5L12 16l6.5-6.5"/>`,
  chevronUp: `<path d="M5.5 14.5L12 8l6.5 6.5"/>`,
  arrowRight: `<path d="M4.8 12h14.4M13.4 6.2l5.8 5.8-5.8 5.8"/>`,
  arrowUpRight: `<path d="M7 17L17 7M8.6 7H17v8.4"/>`,
  link: `<path d="M10 14a4.2 4.2 0 0 0 6 0l2.8-2.8a4.2 4.2 0 0 0-6-6L11.6 6.4"/><path d="M14 10a4.2 4.2 0 0 0-6 0l-2.8 2.8a4.2 4.2 0 0 0 6 6l1.2-1.2"/>`,
  clip: `<path d="M19.6 11.6l-7.7 7.7a5 5 0 0 1-7.1-7.1l8.1-8.1a3.4 3.4 0 0 1 4.8 4.8l-8 8.1a1.7 1.7 0 0 1-2.5-2.4l7.4-7.4"/>`,
  note: `<path d="M6.5 3.5h7.6l4.4 4.4v10.6a2 2 0 0 1-2 2h-10a2 2 0 0 1-2-2v-13a2 2 0 0 1 2-2z"/><path d="M13.6 3.6v4.8h4.8M8.4 12.6h7.2M8.4 16.2h4.6"/>`,
  flag: `<path d="M5.6 21V4.4"/><path d="M5.6 4.6c4.6-2.3 7.6 2.3 13 0v9.2c-5.4 2.3-8.4-2.3-13 0"/>`,
  repeat: `<path d="M17 3.4l2.6 2.6L17 8.6"/><path d="M4.4 11.6V10a4 4 0 0 1 4-4h11.2"/><path d="M7 20.6L4.4 18 7 15.4"/><path d="M19.6 12.4V14a4 4 0 0 1-4 4H4.4"/>`,
  clock: `<circle cx="12" cy="12" r="8.6"/><path d="M12 7.4V12l3.1 2"/>`,
  sparkle: `<path d="M11 3.2c.6 4.4 2.8 6.6 7.2 7.2-4.4.6-6.6 2.8-7.2 7.2-.6-4.4-2.8-6.6-7.2-7.2 4.4-.6 6.6-2.8 7.2-7.2z"/><path d="M18.6 15.4c.25 1.5.95 2.2 2.4 2.4-1.45.2-2.15.9-2.4 2.4-.25-1.5-.95-2.2-2.4-2.4 1.45-.2 2.15-.9 2.4-2.4z"/>`,
  play: `<path fill="currentColor" d="M8 5.2v13.6a.8.8 0 0 0 1.2.7l10.6-6.8a.8.8 0 0 0 0-1.4L9.2 4.5a.8.8 0 0 0-1.2.7z"/>`,
  pause: `<rect x="6.6" y="5" width="3.6" height="14" rx="1.2" fill="currentColor" stroke="none"/><rect x="13.8" y="5" width="3.6" height="14" rx="1.2" fill="currentColor" stroke="none"/>`,
  stop: `<rect x="6.5" y="6.5" width="11" height="11" rx="2.4" fill="currentColor" stroke="none"/>`,
  x: `<path d="M6.4 6.4l11.2 11.2M17.6 6.4L6.4 17.6"/>`,
  list: `<path d="M9.2 6.6h11M9.2 12h11M9.2 17.4h11"/>${dot(4.6, 6.6, 1.3)}${dot(4.6, 12, 1.3)}${dot(4.6, 17.4, 1.3)}`,
  board: `<rect x="3.4" y="4" width="5.2" height="16" rx="1.7"/><rect x="9.4" y="4" width="5.2" height="10.6" rx="1.7"/><rect x="15.4" y="4" width="5.2" height="13.4" rx="1.7"/>`,
  overview: `<rect x="3.6" y="3.6" width="7.2" height="7.2" rx="2"/><rect x="13.2" y="3.6" width="7.2" height="7.2" rx="2"/><rect x="3.6" y="13.2" width="7.2" height="7.2" rx="2"/><rect x="13.2" y="13.2" width="7.2" height="7.2" rx="2"/>`,
  folder: `<path d="M3.5 7.4a2 2 0 0 1 2-2h4.1l2 2.2h6.9a2 2 0 0 1 2 2v7.9a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"/>`,
  file: `<path d="M7 3.5h6.5L18.4 8.4V19a1.5 1.5 0 0 1-1.5 1.5H7A1.5 1.5 0 0 1 5.5 19V5A1.5 1.5 0 0 1 7 3.5z"/><path d="M13.4 3.6v4.9h4.9"/>`,
  image: `<rect x="3.5" y="4.5" width="17" height="15" rx="3.2"/><circle cx="9" cy="10" r="1.8"/><path d="M20.4 15.6l-4.7-4.7-9.4 8.6"/>`,
  diamond: `<path d="M12 3.4l8.6 8.6-8.6 8.6L3.4 12z"/>`,
  diamondFill: `<path fill="currentColor" d="M12 3.4l8.6 8.6-8.6 8.6L3.4 12z"/>`,
  history: `<path d="M3.9 12a8.2 8.2 0 1 0 2.4-5.8"/><path d="M3.6 3.9v4.3h4.3"/><path d="M12 7.8v4.4l2.9 1.8"/>`,
  target: `<circle cx="12" cy="12" r="8.6"/><circle cx="12" cy="12" r="4.6"/>${dot(12, 12, 1.4)}`,
  moon: `<path d="M19.6 14.6A8 8 0 0 1 9.4 4.4a8.1 8.1 0 1 0 10.2 10.2z"/>`,
  sunrise: `<path d="M3 17.8h18M6.4 17.8a5.6 5.6 0 0 1 11.2 0M12 4.4v3.2M4.9 9.2l1.7 1.5M19.1 9.2l-1.7 1.5M8.6 21h6.8"/>`,
  sunset: `<path d="M3 17.8h18M6.4 17.8a5.6 5.6 0 0 1 11.2 0M12 9.6V4.4M9.6 6.8L12 9.4l2.4-2.6M8.6 21h6.8"/>`,
  hourglass: `<path d="M6.4 3.5h11.2M6.4 20.5h11.2M7.6 3.5v2.4a4.5 4.5 0 0 0 1.9 3.7L12 11.4l2.5-1.8a4.5 4.5 0 0 0 1.9-3.7V3.5M7.6 20.5v-2.4a4.5 4.5 0 0 1 1.9-3.7l2.5-1.8 2.5 1.8a4.5 4.5 0 0 1 1.9 3.7v2.4"/>`,
  person: `<circle cx="12" cy="8.1" r="3.8"/><path d="M4.6 20.4a7.4 7.4 0 0 1 14.8 0"/>`,
  undo: `<path d="M9 14.4L4.6 10 9 5.6"/><path d="M4.6 10h10a5 5 0 0 1 0 10H11"/>`,
  download: `<path d="M12 4v11M7.6 10.8l4.4 4.4 4.4-4.4M5 19.6h14"/>`,
  upload: `<path d="M12 15.4V4.4M7.6 8.8L12 4.4l4.4 4.4M5 19.6h14"/>`,
  copy: `<rect x="8.6" y="8.6" width="11.4" height="11.4" rx="2.6"/><path d="M15.4 8.6V6.1a2 2 0 0 0-2-2H6.1a2 2 0 0 0-2 2v7.3a2 2 0 0 0 2 2h2.5"/>`,
  lock: `<rect x="5" y="10.4" width="14" height="10.1" rx="2.6"/><path d="M8 10.4V7.6a4 4 0 0 1 8 0v2.8"/>`,
  shield: `<path d="M12 3.2l7.4 2.9v5.5c0 4.4-3.1 7.9-7.4 9.3-4.3-1.4-7.4-4.9-7.4-9.3V6.1z"/><path d="M8.9 12l2.2 2.2 4.1-4.3"/>`,
  devices: `<rect x="2.6" y="4.6" width="13.4" height="9.8" rx="1.9"/><path d="M1.6 17.6h14"/><rect x="17.2" y="8.2" width="5" height="11.4" rx="1.4"/>`,
  phone: `<rect x="6.6" y="2.6" width="10.8" height="18.8" rx="2.8"/><path d="M10.6 18.4h2.8"/>`,
  laptop: `<rect x="4.6" y="5" width="14.8" height="10.6" rx="1.8"/><path d="M2.6 19h18.8"/>`,
  tag: `<path d="M3.5 12.2V5a1.5 1.5 0 0 1 1.5-1.5h7.2l8.3 8.3a1.6 1.6 0 0 1 0 2.3l-6.9 6.9a1.6 1.6 0 0 1-2.3 0z"/>${dot(8, 8, 1.4)}`,
  info: `<circle cx="12" cy="12" r="8.6"/><path d="M12 11v5.4"/>${dot(12, 7.9, 1.2)}`,
  pin: `<path d="M9 3.6h6l-1 5 3.4 3.4v1.6H6.6V12L10 8.6z"/><path d="M12 13.6v7"/>`,
  archive: `<rect x="3" y="4" width="18" height="5" rx="1.6"/><path d="M5 9v9a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V9M10 13h4"/>`,
  pencil: `<path d="M4 20l1-4.5L15.8 4.7a2 2 0 0 1 2.8 0l.7.7a2 2 0 0 1 0 2.8L8.5 19z"/><path d="M14 6.5l3.5 3.5"/>`,
  grip: `${dot(9, 6, 1.3)}${dot(15, 6, 1.3)}${dot(9, 12, 1.3)}${dot(15, 12, 1.3)}${dot(9, 18, 1.3)}${dot(15, 18, 1.3)}`,
  bolt: `<path d="M13 2.6L5.2 13.4h6l-1 8 7.8-10.8h-6z"/>`,
  key: `<circle cx="8" cy="15.4" r="4"/><path d="M10.9 12.5L19.6 3.8M16.2 7.2l2.4 2.4M13.8 9.6l1.9 1.9"/>`,
  refresh: `<path d="M19.6 12a7.6 7.6 0 1 1-2.2-5.4"/><path d="M19.6 4.4v4.2h-4.2"/>`,
  sidebar: `<rect x="3" y="4.6" width="18" height="14.8" rx="3.2"/><path d="M9.4 4.6v14.8"/>`,
  trophy: `<path d="M7.6 4h8.8v5a4.4 4.4 0 0 1-8.8 0z"/><path d="M7.6 6H4.6v1.4a3 3 0 0 0 3 3M16.4 6h3v1.4a3 3 0 0 1-3 3M12 13.4V17M9.4 17h5.2l.8 3.4H8.6z"/>`,
  palette: `<path d="M12 3.6a8.4 8.4 0 0 0 0 16.8c1.2 0 1.8-.8 1.8-1.7 0-1.2-1-1.6-1-2.7 0-1 .8-1.7 1.8-1.7h2.2a3.6 3.6 0 0 0 3.6-3.6c0-3.9-3.8-7.1-8.4-7.1z"/>${dot(7.6, 11.4, 1.3)}${dot(10, 7.6, 1.3)}${dot(14.4, 7.6, 1.3)}`,
  wand: `<path d="M4 20L14.6 9.4M13 6.6l1.4-3 1.4 3 3 1.4-3 1.4-1.4 3-1.4-3-3-1.4z"/>`,
  inboxIn: `<path d="M3.5 13.5V18a2 2 0 0 0 2 2h13a2 2 0 0 0 2-2v-4.5M3.5 13.5H8l1.2 2.2h5.6l1.2-2.2h4.5M12 3.6v8M8.8 8.6L12 11.8l3.2-3.2"/>`,
  sort: `<path d="M7 4.6v14.8M3.8 16.2L7 19.4l3.2-3.2M17 19.4V4.6M13.8 7.8L17 4.6l3.2 3.2"/>`,
  layers: `<path d="M12 3.8l8.6 4.6L12 13 3.4 8.4z"/><path d="M3.4 12.6L12 17.2l8.6-4.6M3.4 16.6L12 21.2l8.6-4.6" opacity=".55"/>`,
  keyboard: `<rect x="2.8" y="6" width="18.4" height="12" rx="2.4"/><path d="M8 14.8h8"/>${dot(6.6, 9.6, 1)}${dot(10, 9.6, 1)}${dot(13.4, 9.6, 1)}${dot(16.8, 9.6, 1)}`,
  heart: `<path d="M12 20s-7.6-4.6-7.6-10a4.3 4.3 0 0 1 7.6-2.8A4.3 4.3 0 0 1 19.6 10c0 5.4-7.6 10-7.6 10z"/>`,
  eye: `<path d="M2.6 12S6 5.6 12 5.6 21.4 12 21.4 12 18 18.4 12 18.4 2.6 12 2.6 12z"/><circle cx="12" cy="12" r="3"/>`,
  edit: `<path d="M12.6 5.4H6.4a2 2 0 0 0-2 2v10.2a2 2 0 0 0 2 2h10.2a2 2 0 0 0 2-2v-6.2"/><path d="M17.4 3.8a1.9 1.9 0 0 1 2.7 2.7l-7.5 7.6-3.4.8.8-3.4z"/>`,
  dot: `${dot(12, 12, 3.4)}`,
  circle: `<circle cx="12" cy="12" r="8.6"/>`,
  home: `<path d="M4 10.6L12 4l8 6.6V19a1.6 1.6 0 0 1-1.6 1.6H5.6A1.6 1.6 0 0 1 4 19z"/><path d="M9.8 20.6v-5.4h4.4v5.4"/>`,
  dock: `<rect x="3" y="4" width="18" height="12.4" rx="2.4"/><path d="M8 20.2h8M6.6 13.2h10.8"/>`,
  squarePlus: `<rect x="4" y="4" width="16" height="16" rx="4"/><path d="M12 8.4v7.2M8.4 12h7.2"/>`,
  arrowUturn: `<path d="M9 10.6L4.6 15 9 19.4"/><path d="M4.6 15h10.2a4.6 4.6 0 0 0 0-9.2H9.6"/>`,
  zzz: `<path d="M4.6 9.4h5l-5 6.2h5M13 4.6h6.4L13 12.4h6.4"/>`,
  mail: `<rect x="3" y="5.4" width="18" height="13.2" rx="3.2"/><path d="M3.9 7.6l7 5.1a1.9 1.9 0 0 0 2.2 0l7-5.1"/>`,
  call: `<path d="M7 3.6h2.4a1 1 0 0 1 .95.7l1.1 3.4a1 1 0 0 1-.3 1.05L9.6 10.1a11.4 11.4 0 0 0 4.3 4.3l1.35-1.55a1 1 0 0 1 1.05-.3l3.4 1.1a1 1 0 0 1 .7.95V17a2.4 2.4 0 0 1-2.6 2.4A15.8 15.8 0 0 1 4.6 6.2 2.4 2.4 0 0 1 7 3.6z"/>`,
  message: `<path d="M12 4.2c-4.9 0-8.6 3.2-8.6 7.2 0 2.2 1.1 4.1 2.9 5.4l-.8 3.2 3.5-1.9c.9.3 1.9.4 3 .4 4.9 0 8.6-3.2 8.6-7.2S16.9 4.2 12 4.2z"/>`,
  msgDots: `<path d="M12 4.2c-4.9 0-8.6 3.2-8.6 7.2 0 2.2 1.1 4.1 2.9 5.4l-.8 3.2 3.5-1.9c.9.3 1.9.4 3 .4 4.9 0 8.6-3.2 8.6-7.2S16.9 4.2 12 4.2z"/>${dot(8.3, 11.4, 1.1)}${dot(12, 11.4, 1.1)}${dot(15.7, 11.4, 1.1)}`,
  chat: `<path d="M9 15.2c-.9 0-1.7-.1-2.5-.4l-2.8 1.5.7-2.5a5.3 5.3 0 0 1-1.6-3.8C2.8 6.8 5.6 4.3 9 4.3s6.2 2.5 6.2 5.6"/><path d="M15.4 9.8c3.2 0 5.8 2.3 5.8 5.1 0 1.5-.7 2.8-1.8 3.8l.5 2.2-2.4-1.3c-.7.2-1.4.3-2.1.3-3.2 0-5.8-2.3-5.8-5s2.6-5.1 5.8-5.1z"/>`,
  map: `<path d="M9 4.4L3.6 6.6v13l5.4-2.2 6 2.2 5.4-2.2v-13L15 6.6z"/><path d="M9 4.4v13M15 6.6v13"/>`,
  route: `<circle cx="6" cy="18" r="2.2"/><circle cx="18" cy="6" r="2.2"/><path d="M8.2 18h6.3a3.2 3.2 0 0 0 0-6.4h-5a3.2 3.2 0 0 1 0-6.4h6.3"/>`,
  at: `<circle cx="12" cy="12" r="3.6"/><path d="M15.6 12v1.4a2.6 2.6 0 0 0 5.2 0V12a8.8 8.8 0 1 0-3.4 6.9"/>`,
  table: `<rect x="3.4" y="4.4" width="17.2" height="15.2" rx="2.8"/><path d="M3.4 9.6h17.2M3.4 14.6h17.2M9.4 9.6v10"/>`,
  mic: `<rect x="9" y="3.2" width="6" height="11" rx="3"/><path d="M5.6 11.4a6.4 6.4 0 0 0 12.8 0M12 17.8v3"/>`,
  waveform: `<path d="M4 10.2v3.6M7.4 7.4v9.2M10.8 4.6v14.8M14.2 8.2v7.6M17.6 6v12M21 10.4v3.2"/>`,
  plug: `<path d="M9 3.4v4.2M15 3.4v4.2M6.2 7.6h11.6v3.6a5.8 5.8 0 0 1-11.6 0z"/><path d="M12 17v3.6"/>`,
  people: `<circle cx="9" cy="8.4" r="3.2"/><path d="M3.2 19.6a5.8 5.8 0 0 1 11.6 0"/><circle cx="16.8" cy="9.2" r="2.6"/><path d="M15.6 14.1a4.8 4.8 0 0 1 5.6 4.7"/>`,
  send: `<path d="M20.6 3.6L10.4 13.8M20.6 3.6l-6.2 17-4-7.2-7.2-4z"/>`,
  globe: `<circle cx="12" cy="12" r="8.6"/><path d="M3.4 12h17.2M12 3.4c2.4 2.4 3.6 5.3 3.6 8.6s-1.2 6.2-3.6 8.6c-2.4-2.4-3.6-5.3-3.6-8.6S9.6 5.8 12 3.4z"/>`,
  phoneOut: `<path d="M7 3.6h2.4a1 1 0 0 1 .95.7l1.1 3.4a1 1 0 0 1-.3 1.05L9.6 10.1a11.4 11.4 0 0 0 4.3 4.3l1.35-1.55a1 1 0 0 1 1.05-.3l3.4 1.1a1 1 0 0 1 .7.95V17a2.4 2.4 0 0 1-2.6 2.4A15.8 15.8 0 0 1 4.6 6.2 2.4 2.4 0 0 1 7 3.6z"/><path d="M15 3.4h5.6V9M20.4 3.6l-5.6 5.6"/>`,
  video: `<rect x="2.8" y="6.2" width="12.8" height="11.6" rx="3.2"/><path d="M15.6 10.5l4.3-2.7a.7.7 0 0 1 1.1.6v7.2a.7.7 0 0 1-1.1.6l-4.3-2.7"/>`,
  location: `<path d="M12 21s-6.6-5.7-6.6-11.2a6.6 6.6 0 0 1 13.2 0C18.6 15.3 12 21 12 21z"/><circle cx="12" cy="9.9" r="2.5"/>`,
  rocket: `<path d="M12.2 15.6l-3.8-3.8C10 7.2 13.6 4.2 19.8 4.2c0 6.2-3 9.8-7.6 11.4z"/><path d="M8.4 11.8L5 11.6l2.6-3.2 3.6-.2M12.2 15.6l.2 3.4 3.2-2.6.2-3.6M6.2 17.8c-.8.8-1.6 2.6-1.6 2.6s1.8-.8 2.6-1.6"/>${dot(15.4, 8.6, 1.3)}`,
};

// ---------- Ausgabe ----------
// icon("sun") → <svg …>; Größe über CSS (.ic = 1em) oder Parameter
export function icon(name, size = 0, cls = "") {
  const body = P[name] || P.dot;
  const s = size ? ` width="${size}" height="${size}"` : "";
  return `<svg class="ic${cls ? " " + cls : ""}" viewBox="0 0 24 24"${s} fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">${body}</svg>`;
}

export const ICONS = Object.keys(P);

// Abhak-Ring (Kreis + Häkchen, das sich per CSS zeichnet)
export const CHECK = `<svg class="ck" viewBox="0 0 26 26" aria-hidden="true" focusable="false"><circle class="ck-ring" cx="13" cy="13" r="11"/><circle class="ck-fill" cx="13" cy="13" r="11"/><path class="ck-mark" d="M8 13.4l3.4 3.4 6.8-7.2"/></svg>`;

// App-Symbol (Tasche mit Häkchen) für Kopf, Onboarding und Leerzustände – eindeutige Verlaufs-IDs je Aufruf
let logoSeq = 0;
export function logo(cls = "") {
  const a = "lga" + ++logoSeq, b = "lgb" + logoSeq;
  return `<svg class="logo${cls ? " " + cls : ""}" viewBox="0 0 64 64" aria-hidden="true" focusable="false"><defs><linearGradient id="${a}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#7B6CFF"/><stop offset=".55" stop-color="#3D7BFF"/><stop offset="1" stop-color="#2EC5E6"/></linearGradient><linearGradient id="${b}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".5"/><stop offset=".5" stop-color="#fff" stop-opacity="0"/></linearGradient></defs><rect width="64" height="64" rx="15" fill="url(#${a})"/><rect width="64" height="64" rx="15" fill="url(#${b})"/><path d="M24.5 21v-3.2a3.3 3.3 0 0 1 3.3-3.3h8.4a3.3 3.3 0 0 1 3.3 3.3V21" fill="none" stroke="#fff" stroke-width="3.6" stroke-linecap="round"/><rect x="13" y="21" width="38" height="28.5" rx="7" fill="#fff"/><path d="M24.6 35.4l5.2 5.2 10-10.6" fill="none" stroke="#3D7BFF" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
}
