// Web-Studio: Branchen-Vorlagen und der Generator für die Kundenwebseite
window.WS = (() => {
  const PRESETS = {
    friseur: {
      label: 'Friseur', name: 'Salon Schnittpunkt', claim: 'Dein Haar. Unser Handwerk.', color: '#8a3ffc', style: 'modern',
      about: 'Seit über 10 Jahren schneiden, färben und stylen wir im Herzen der Stadt. Mit Termin oder einfach vorbeikommen.',
      services: 'Damenschnitt | ab 39 €\nHerrenschnitt | 24 €\nFärben | ab 55 €\nKinderschnitt | 15 €',
      hours: 'Di–Fr 9–18 Uhr\nSa 8–14 Uhr\nSo–Mo geschlossen'
    },
    cafe: {
      label: 'Café / Bäckerei', name: 'Café Morgenrot', claim: 'Frisch gebacken, mit Liebe gebrüht.', color: '#b4531c', style: 'warm',
      about: 'Hausgemachter Kuchen, Frühstück bis 14 Uhr und Kaffee von einer kleinen Rösterei aus der Region.',
      services: 'Cappuccino | 3,20 €\nFrühstück „Klassik“ | 8,90 €\nKuchen | ab 3,50 €\nTorten auf Bestellung | ab 29 €',
      hours: 'Mo–Fr 7–18 Uhr\nSa–So 8–17 Uhr'
    },
    handwerk: {
      label: 'Handwerker', name: 'Malerbetrieb Kaya', claim: 'Sauber. Pünktlich. Fair.', color: '#0a7d4f', style: 'bold',
      about: 'Meisterbetrieb für Innen- und Außenanstrich, Tapezieren und Fassaden. Kostenlose Besichtigung vor Ort.',
      services: 'Wände streichen | ab 8 €/m²\nTapezieren | ab 12 €/m²\nFassade | nach Angebot\nBesichtigung | kostenlos',
      hours: 'Mo–Fr 7–17 Uhr\nTermine nach Absprache'
    },
    praxis: {
      label: 'Praxis / Studio', name: 'Physio Bewegt', claim: 'Wieder schmerzfrei bewegen.', color: '#0a66ff', style: 'modern',
      about: 'Physiotherapie, manuelle Therapie und Rückenkurse. Alle Kassen und Privat.',
      services: 'Krankengymnastik | Kasse\nManuelle Therapie | Kasse\nMassage 30 Min. | 35 €\nRückenkurs 8×  | 96 €',
      hours: 'Mo–Do 8–19 Uhr\nFr 8–15 Uhr'
    },
    laden: {
      label: 'Laden / Kiosk', name: 'Blumen Lenz', claim: 'Blumen für jeden Anlass.', color: '#d6336c', style: 'warm',
      about: 'Sträuße, Pflanzen und Trauerfloristik. Lieferung im Stadtgebiet am selben Tag.',
      services: 'Strauß klein | ab 15 €\nStrauß groß | ab 35 €\nHochzeitsfloristik | nach Absprache\nLieferung | 5 €',
      hours: 'Mo–Fr 9–18 Uhr\nSa 9–13 Uhr'
    }
  };
  const BASE = { phone: '030 1234567', mail: 'info@beispiel.de', addr: 'Hauptstraße 1, 10115 Berlin', owner: 'Max Mustermann' };

  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const lines = (s) => String(s || '').split('\n').map((l) => l.trim()).filter(Boolean);
  const hex = (c) => (/^#[0-9a-f]{6}$/i.test(c) ? c : '#0a66ff');

  function contrastInk(c) {
    const n = parseInt(c.slice(1), 16);
    const [r, g, b] = [n >> 16, (n >> 8) & 255, n & 255].map((v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; });
    return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.4 ? '#111' : '#fff';
  }

  const STYLES = {
    modern: { font: '-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif', bg: '#fafafa', radius: '14px', hero: (c) => `linear-gradient(135deg, ${c}, #111)` },
    warm: { font: 'Georgia,"Times New Roman",serif', bg: '#fbf6ef', radius: '6px', hero: (c) => `linear-gradient(160deg, ${c}, #3b2414)` },
    bold: { font: '"Arial Black",Arial,sans-serif', bg: '#f2f2f2', radius: '0', hero: (c) => c }
  };

  function render(d) {
    const c = hex(d.color);
    const st = STYLES[d.style] || STYLES.modern;
    const ink = contrastInk(c);
    const heroInk = d.style === 'bold' ? ink : '#fff';
    const svc = lines(d.services).map((l) => {
      const [n, p] = l.split('|').map((x) => x.trim());
      return `<li><span>${esc(n)}</span><b>${esc(p || '')}</b></li>`;
    }).join('');
    const hours = lines(d.hours).map((l) => `<li>${esc(l)}</li>`).join('');
    const tel = String(d.phone || '').replace(/[^\d+]/g, '');
    const maps = 'https://www.google.com/maps/search/?api=1&query=' + encodeURIComponent(d.addr || '');
    const year = new Date().getFullYear();
    return `<!doctype html>
<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(d.name)}</title>${d.draft ? '<meta name="robots" content="noindex, nofollow">' : ''}<meta name="description" content="${esc(d.claim)} – ${esc(d.addr)}">
<style>
*{box-sizing:border-box}body{margin:0;font:17px/1.6 ${st.font};color:#1a1a1a;background:${st.bg}}
a{color:${c}}.w{max-width:960px;margin:0 auto;padding:0 20px}
nav{display:flex;justify-content:space-between;align-items:center;padding:16px 0;gap:12px;flex-wrap:wrap}
nav strong{font-size:20px}nav a{margin-left:14px;text-decoration:none;color:#1a1a1a}
.hero{background:${st.hero(c)};color:${heroInk};padding:72px 0 80px}
.hero h1{font-size:clamp(32px,7vw,56px);line-height:1.1;margin:0 0 12px}.hero p{font-size:20px;opacity:.9;margin:0 0 24px}
.btn{display:inline-block;background:${d.style === 'bold' ? '#111' : c};color:${d.style === 'bold' ? '#fff' : ink};padding:14px 24px;border-radius:${st.radius};text-decoration:none;font-weight:700;border:2px solid ${d.style === 'bold' ? '#111' : '#fff'}}
section{padding:56px 0}h2{font-size:30px;margin:0 0 20px}
.grid{display:grid;gap:24px;grid-template-columns:repeat(auto-fit,minmax(260px,1fr))}
.box{background:#fff;border-radius:${st.radius};padding:24px;box-shadow:0 1px 3px rgba(0,0,0,.08)}
ul.p{list-style:none;padding:0;margin:0}ul.p li{display:flex;justify-content:space-between;gap:12px;padding:12px 0;border-bottom:1px solid #eee}
ul.h{padding-left:18px;margin:0}
footer{background:#111;color:#bbb;padding:32px 0;font-size:14px}footer a{color:#fff}
.call{position:fixed;right:16px;bottom:16px;background:${c};color:${ink};border-radius:99px;padding:14px 20px;font-weight:700;text-decoration:none;box-shadow:0 4px 14px rgba(0,0,0,.25)}
@media(min-width:900px){.call{display:none}}
</style></head><body>
${d.draft ? `<div style="background:#ffd43b;color:#111;text-align:center;padding:8px 12px;font:600 14px/1.4 sans-serif">Unverbindlicher Entwurf – nicht die offizielle Seite von ${esc(d.name)}. Texte und Preise sind Platzhalter.</div>` : ''}
<div class="w"><nav><strong>${esc(d.name)}</strong><div><a href="#leistungen">Leistungen</a><a href="#kontakt">Kontakt</a></div></nav></div>
<div class="hero"><div class="w"><h1>${esc(d.name)}</h1><p>${esc(d.claim)}</p>${tel ? `<a class="btn" href="tel:${esc(tel)}">Jetzt anrufen</a>` : ''}</div></div>
<section><div class="w"><h2>Über uns</h2><p>${esc(d.about)}</p></div></section>
<section id="leistungen" style="background:#fff"><div class="w"><h2>Leistungen &amp; Preise</h2><ul class="p">${svc}</ul></div></section>
<section id="kontakt"><div class="w grid">
<div class="box"><h2>Öffnungszeiten</h2><ul class="h">${hours}</ul></div>
<div class="box"><h2>Kontakt</h2><p>${esc(d.addr)}<br><a href="${esc(maps)}" rel="noopener" target="_blank">Route planen</a></p>
<p>${tel ? `Tel. <a href="tel:${esc(tel)}">${esc(d.phone)}</a><br>` : ''}${d.mail ? `<a href="mailto:${esc(d.mail)}">${esc(d.mail)}</a>` : ''}</p></div>
</div></section>
<footer><div class="w" id="impressum"><p><strong>Impressum</strong><br>Angaben gemäß § 5 DDG<br>${esc(d.name)}, Inhaber: ${esc(d.owner)}<br>${esc(d.addr)}<br>${tel ? `Telefon: ${esc(d.phone)}<br>` : ''}${d.mail ? `E-Mail: ${esc(d.mail)}` : ''}</p>
<p><strong>Datenschutz</strong><br>Diese Seite setzt keine Cookies und lädt keine externen Inhalte. Beim Aufruf verarbeitet der Hoster technisch notwendige Server-Logs.</p>
<p>© ${year} ${esc(d.name)}</p></div></footer>
${tel ? `<a class="call" href="tel:${esc(tel)}">📞 Anrufen</a>` : ''}
</body></html>`;
  }

  function check(d) {
    const out = [];
    const add = (ok, t) => out.push({ ok, t });
    add(String(d.name || '').trim().length > 1, 'Name des Ladens');
    add(lines(d.services).length >= 3, 'Mindestens 3 Leistungen');
    add(lines(d.hours).length >= 1, 'Öffnungszeiten');
    add(/\d{5}/.test(d.addr || ''), 'Adresse mit PLZ (für Google)');
    add(/\d{6,}/.test(String(d.phone || '').replace(/\D/g, '')), 'Telefonnummer (Anruf-Knopf auf dem Handy)');
    add(/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(d.mail || ''), 'Gültige E-Mail');
    add(String(d.owner || '').trim().split(/\s+/).length >= 2, 'Inhaber mit Vor- und Nachname (Impressumspflicht)');
    return out;
  }

  return { PRESETS, BASE, render, check, esc };
})();
