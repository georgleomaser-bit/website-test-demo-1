// Web-Studio Autopilot: aus einer Liste von Läden Entwürfe, Briefe, ZIP und Nachfass-Termine erzeugen
(() => {
  const KINDS = [
    [/fris|salon|barber|haar|kosmetik|nagel|beauty/i, 'friseur'],
    [/schneid|änderung|aenderung|reinigung|nähe|naehe/i, 'schneiderei'],
    [/imbiss|imbiß|grill|döner|doener|pizz|restaurant|gyros|burger/i, 'imbiss'],
    [/caf|bäck|baeck|konditor|bistro|eis/i, 'cafe'],
    [/maler|elektr|sanit|tischler|schreiner|dach|bau|handwerk|fliesen|garten|kfz|werkstatt/i, 'handwerk'],
    [/physio|praxis|massage|yoga|fitness|studio|therap|tattoo/i, 'praxis']
  ];
  const kindOf = (b) => (KINDS.find(([re]) => re.test(b || '')) || [null, 'laden'])[1];
  const addDays = (n) => { const d = new Date(); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); };

  state.auto = { me: '', contact: '', base: '', list: '', ...(state.auto || {}) };
  const A = state.auto;
  ['me', 'contact', 'base', 'list'].forEach((f) => {
    const el = $('a-' + f);
    el.value = A[f];
    el.addEventListener('input', () => { A[f] = el.value.trim(); save(); if (f !== 'list') renderAuto(); });
  });

  const drafts = () => state.leads.filter((l) => l.site && l.auto);
  const link = (l) => (A.base ? A.base.replace(/\/+$/, '') + '/' + slug(l.site.name) + '.html' : '[Link zur Vorschau – erst hochladen]');

  function letter(l) {
    return `Hallo ${l.site.name}-Team,

mir ist aufgefallen, dass ${l.site.name} noch keine eigene Webseite hat. Viele Kunden suchen heute zuerst auf dem Handy nach Öffnungszeiten, Preisen und der Telefonnummer.

Deshalb habe ich Ihnen schon einen Entwurf gebaut – unverbindlich und kostenlos zum Anschauen:
${link(l)}

Texte und Preise darin sind noch Platzhalter. Gefällt Ihnen die Seite, passe ich alles an Ihren Laden an und stelle sie fertig online – für einmalig 290 €. Gefällt sie Ihnen nicht, ist das völlig in Ordnung, dann lösche ich den Entwurf.

Ich melde mich in ein paar Tagen kurz bei Ihnen${A.contact ? `. Sie erreichen mich auch unter ${A.contact}` : ''}.

Viele Grüße
${A.me || '[Dein Name]'}`;
  }

  $('a-run').addEventListener('click', () => {
    const rows = A.list.split('\n').map((r) => r.split(/[;\t]/).map((x) => x.trim())).filter((r) => r[0]);
    if (!rows.length) { $('a-msg').textContent = 'Füg zuerst mindestens einen Laden ein.'; return; }
    let added = 0;
    rows.forEach(([name, branch = '', addr = '', phone = '']) => {
      if (state.leads.some((l) => l.auto && l.name.toLowerCase() === name.toLowerCase())) return;
      const kind = kindOf(branch + ' ' + name);
      const site = { ...fresh(kind), name, addr, phone, mail: '', owner: '(wird ergänzt)', draft: true };
      state.leads.push({ id: Date.now() + Math.random(), name, contact: phone, value: 290, stage: 'lead', auto: true, site, next: addDays(3) });
      added += 1;
    });
    save();
    $('a-msg').textContent = `${added} neue Entwürfe erzeugt${rows.length - added ? `, ${rows.length - added} gab es schon` : ''}. Nächster Schritt: „Alle Webseiten als ZIP“.`;
    renderAuto(); renderStats();
  });

  /* ---- ZIP ohne Bibliothek (Methode „stored“) ---- */
  const CRC = (() => { const t = new Uint32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } return t; })();
  const crc32 = (b) => { let c = 0xffffffff; for (let i = 0; i < b.length; i++) c = CRC[(c ^ b[i]) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
  function zip(files) {
    const enc = new TextEncoder();
    const parts = []; const central = []; let offset = 0;
    files.forEach(({ name, text }) => {
      const nm = enc.encode(name); const data = enc.encode(text); const crc = crc32(data);
      const h = new DataView(new ArrayBuffer(30));
      h.setUint32(0, 0x04034b50, true); h.setUint16(4, 20, true); h.setUint16(6, 0x0800, true);
      h.setUint32(14, crc, true); h.setUint32(18, data.length, true); h.setUint32(22, data.length, true); h.setUint16(26, nm.length, true);
      parts.push(h, nm, data);
      const c = new DataView(new ArrayBuffer(46));
      c.setUint32(0, 0x02014b50, true); c.setUint16(4, 20, true); c.setUint16(6, 20, true); c.setUint16(8, 0x0800, true);
      c.setUint32(16, crc, true); c.setUint32(20, data.length, true); c.setUint32(24, data.length, true); c.setUint16(28, nm.length, true);
      c.setUint32(42, offset, true);
      central.push(c, nm);
      offset += 30 + nm.length + data.length;
    });
    const size = central.reduce((a, p) => a + p.byteLength, 0);
    const e = new DataView(new ArrayBuffer(22));
    e.setUint32(0, 0x06054b50, true); e.setUint16(8, files.length, true); e.setUint16(10, files.length, true);
    e.setUint32(12, size, true); e.setUint32(16, offset, true);
    return new Blob([...parts, ...central, e], { type: 'application/zip' });
  }
  function download(blob, name) {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob); a.download = name;
    document.body.append(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }
  $('a-zip').addEventListener('click', () => {
    const list = drafts();
    if (!list.length) { $('a-msg').textContent = 'Noch keine Entwürfe – erst „Alles erzeugen“.'; return; }
    const files = list.map((l) => ({ name: slug(l.site.name) + '.html', text: render(l.site) }));
    files.push({ name: 'index.html', text: `<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="robots" content="noindex"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Entwürfe</title></head><body style="font:16px/1.6 sans-serif;max-width:600px;margin:40px auto;padding:0 16px"><h1>Webseiten-Entwürfe</h1><ul>${list.map((l) => `<li><a href="${slug(l.site.name)}.html">${esc(l.site.name)}</a></li>`).join('')}</ul></body></html>` });
    download(zip(files), 'webseiten-entwuerfe.zip');
    $('a-msg').textContent = 'ZIP geladen. Entpacken, den Ordner auf app.netlify.com/drop ziehen und die Adresse oben bei „Vorschau-Adresse“ eintragen.';
  });

  $('a-letters').addEventListener('click', () => {
    if (!drafts().length) { $('a-msg').textContent = 'Noch keine Entwürfe – erst „Alles erzeugen“.'; return; }
    const sec = $('tab-auto');
    sec.classList.add('printing');
    window.print();
    sec.classList.remove('printing');
  });

  window.renderAuto = function renderAuto() {
    const list = drafts();
    const today = todayISO();
    const due = state.leads.filter((l) => l.next && l.next <= today && (l.stage === 'lead' || l.stage === 'offer'));
    const steps = [
      [list.length > 0, 'Läden aus Google Maps einfügen und „Alles erzeugen“'],
      [!!A.base, 'ZIP herunterladen, entpacken, auf Netlify Drop hochladen, Adresse eintragen'],
      [!!A.me && !!A.contact, 'Deinen Namen und deine Nummer eintragen'],
      [false, 'Briefe drucken und persönlich abgeben (oder einwerfen, wenn kein „Keine Werbung“ dran steht)'],
      [false, 'Nach 3 Tagen anrufen – die fälligen Anrufe stehen hier']
    ];
    $('a-todo').innerHTML = `<h2>Deine Aufgaben</h2><ul class="checks">${steps.map(([ok, t]) => `<li class="${ok ? '' : 'bad'}">${esc(t)}</li>`).join('')}</ul>`
      + (due.length ? `<h3>Heute anrufen (${due.length})</h3><ul>${due.map((l) => `<li><b>${esc(l.name)}</b> · ${esc(l.contact || 'keine Nummer')} – „Haben Sie sich den Entwurf angeschaut?“</li>`).join('')}</ul>` : '<p class="small muted" style="margin-top:8px">Heute keine Anrufe fällig.</p>');

    const res = $('a-results');
    res.textContent = '';
    list.forEach((l) => {
      const box = document.createElement('div');
      box.className = 'letter';
      box.textContent = letter(l);
      const acts = document.createElement('div');
      acts.className = 'acts';
      const btn = (t, fn, ghost = true) => { const b = document.createElement('button'); b.type = 'button'; b.textContent = t; if (ghost) b.className = 'ghost'; b.addEventListener('click', fn); acts.append(b); };
      btn('Im Editor öffnen', () => { state.site = l.site; fillForm(); updatePreview(); showTab('build'); }, false);
      btn('Brief kopieren', () => { navigator.clipboard?.writeText(letter(l)).then(() => { $('a-msg').textContent = `Brief für ${l.name} kopiert.`; }, () => {}); });
      btn('Angebot', () => { state.offer.client = l.name; $('o-client').value = l.name; save(); showTab('offer'); });
      btn('Erledigt – nicht interessiert', () => { state.leads = state.leads.filter((x) => x.id !== l.id); save(); renderAuto(); renderStats(); });
      box.append(acts);
      res.append(box);
    });
  };

  // Autopilot ist der Start-Tab
  showTab('auto');
})();
