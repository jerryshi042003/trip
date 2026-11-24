(() => {
  const base = new URL('./', document.currentScript.src);
  document.body.insertAdjacentHTML('afterbegin', `
<div class="wrap">
  <header class="top">
    <h1><img class="trip-mark" src="${new URL('icon-180.png?v=2', base)}" width="32" height="32" alt="">Trip</h1>
    <button class="lock" id="share-trip" type="button">Share Trip</button>
  </header>
  <nav class="seg" aria-label="Trip sections">
    <button data-v="plan" aria-pressed="true">Plan</button>
    <button data-v="places" aria-pressed="false">Places</button>
    <button data-v="people" aria-pressed="false">People</button>
    <button data-v="where" aria-pressed="false">Where</button>
  </nav>
  <div class="who" role="group" aria-label="Traveler">
    <button data-who="jerry" aria-pressed="true">Jerry</button>
    <button data-who="tom" aria-pressed="false">Tom</button>
  </div>
  <main id="out"><p class="state" role="status">Loading trip…</p></main>
</div>
<div class="toast" id="toast" role="status"></div>
  `);
  const I = {
    map:'<svg viewBox="0 0 24 24"><path d="M12 21s-7-6.2-7-11.5A7 7 0 0 1 19 9.5C19 14.8 12 21 12 21z"/><circle cx="12" cy="9.5" r="2.5"/></svg>',
    call:'<svg viewBox="0 0 24 24"><path d="M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2"/></svg>',
    mail:'<svg viewBox="0 0 24 24"><rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 7 9 6 9-6"/></svg>',
    msg:'<svg viewBox="0 0 24 24"><path d="M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.6A8 8 0 1 1 21 12z"/></svg>',
    web:'<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/></svg>',
    copy:'<svg viewBox="0 0 24 24"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/></svg>'
  };
  const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
  const store = { get(k){ try { return localStorage.getItem(k); } catch(e) { return null; } }, set(k,v){ try { localStorage.setItem(k,v); } catch(e) {} } };
  const toast = m => { const t = document.getElementById('toast'); t.textContent = m; t.classList.add('on'); clearTimeout(t._h); t._h = setTimeout(() => t.classList.remove('on'), 1300); };
  const gmap = q => 'https://www.google.com/maps/search/?api=1&query=' + encodeURIComponent(q);
  const tomPlan = 'https://jerryshi042003.github.io/trip/tom/';
  const edit = 'https://github.com/jerryshi042003/trip/edit/main/docs/';
  const showInstall = !navigator.standalone && !matchMedia('(display-mode: standalone)').matches;
  const travelerKeys = ['jerry', 'tom'];
  const viewKeys = ['plan', 'places', 'people', 'where'];
  const requestedTraveler = new URLSearchParams(location.search).get('who') ?? document.body.dataset.traveler;
  const linkedTraveler = travelerKeys.includes(requestedTraveler);
  const savedView = store.get('view');
  const savedTraveler = store.get('who');
  let D = null;
  let region = '';
  let category = '';
  let tripText = '';
  let tomNotes = [];
  let refreshing = false;
  const requestedView = new URLSearchParams(location.search).get('view');
  let view = viewKeys.includes(requestedView) ? requestedView : !linkedTraveler && viewKeys.includes(savedView) ? savedView : 'plan';
  let whereView;
  let who = linkedTraveler ? requestedTraveler : travelerKeys.includes(savedTraveler) ? savedTraveler : 'jerry';
  if (linkedTraveler) store.set('who', who);

  const placeRow = p => `<div class="row">${p.photo ? `<img class="ph" src="${esc(p.photo)}" alt="" loading="lazy">` : ''}<div class="main"><div class="t">${esc(p.name)}${p.been ? ' <span class="been">Been</span>' : ''}</div><div class="s">${esc(p.addr)}</div>${p.ja ? `<div class="ja">${esc(p.ja)}</div>` : ''}</div><div class="acts">${p.ja ? `<button class="a" data-copy="${esc(p.ja)}" aria-label="Copy">${I.copy}</button>` : ''}<a class="a" href="${gmap(p.ja || p.addr)}" aria-label="Map">${I.map}</a></div></div>`;
  const personRow = p => {
    const a = [];
    if (p.phone) a.push(`<a class="a" href="tel:${esc(p.phone)}" aria-label="Call">${I.call}</a>`);
    if (p.whatsapp) a.push(`<a class="a" href="https://wa.me/${esc(p.whatsapp)}" aria-label="WhatsApp">${I.msg}</a>`);
    else if (p.phone && p.phone.length > 6) a.push(`<a class="a" href="sms:${esc(p.phone)}" aria-label="Message">${I.msg}</a>`);
    if (p.email) a.push(`<a class="a" href="mailto:${esc(p.email)}" aria-label="Email">${I.mail}</a>`);
    if (p.ig) a.push(`<a class="a" href="https://ig.me/m/${esc(p.ig)}" aria-label="Instagram">IG</a>`);
    if (p.fb) a.push(`<a class="a" href="${esc(p.fb)}" aria-label="Facebook">FB</a>`);
    if (p.web) a.push(`<a class="a" href="${esc(p.web)}" aria-label="Website">${I.web}</a>`);
    const sub = [p.role, p.phoneLabel || p.phone, p.email].filter(Boolean).join(' · ');
    return `<div class="row person"><div class="main"><div class="t">${esc(p.name)}</div><div class="s">${esc(sub)}</div></div><div class="acts">${a.join('')}</div></div>`;
  };
  const taskRow = task => `<div class="row task"><div class="main"><div class="t">${esc(task.title)}</div><div class="s">${esc(task.detail)}</div>${task.draft ? `<details><summary>Draft message</summary><p>${esc(task.draft)}</p><button class="lock" data-copy="${esc(task.draft)}">Copy draft</button></details>` : ''}</div>${task.link ? `<a class="a" href="${esc(task.link)}" aria-label="Open link for ${esc(task.title)}">${I.web}</a>` : ''}</div>`;
  const mediaURL = path => esc(new URL(path, base).href);
  const directions = (p, origin) => origin
    ? `https://www.google.com/maps/dir/?api=1&origin=${encodeURIComponent(origin.addr)}&destination=${encodeURIComponent(p.name + ', ' + p.addr)}&travelmode=two-wheeler`
    : gmap(p.ja || p.name + ', ' + p.addr);

  function dashboardItem(item, byId) {
    if (item.icon && item.link) {
      return `<article class="trip-entry"><a class="trip-entry-copy trip-app-link" href="${esc(item.link)}">
        <img class="trip-app-icon" src="${mediaURL(item.icon)}" alt="" width="48" height="48">
        <div class="main"><h3>${esc(item.title)} <span class="trip-app-store">App Store</span></h3><p>${esc(item.detail)}</p></div>
      </a></article>`;
    }
    const place = byId[item.place];
    const photos = item.photos ?? [];
    const gallery = photos.length ? `<div class="trip-gallery" ${photos.length > 1 ? 'tabindex="0"' : ''} role="group" aria-label="${esc(item.title)} photos">${photos.map(photo => `
      <figure><img src="${mediaURL(photo.url)}" alt="${esc(photo.caption)}" loading="lazy" decoding="async"><figcaption>${esc(photo.caption)}</figcaption></figure>`).join('')}</div>` : '';
    return `<article class="trip-entry">
      ${gallery}
      <div class="trip-entry-copy">
        <div class="main">
          ${item.meta ? `<div class="trip-meta">${esc(item.meta)}</div>` : ''}
          <h3>${esc(item.title)}</h3>
          <p>${esc(item.detail)}</p>
          ${item.link || place ? `<div class="trip-actions">
            ${item.link ? `<a href="${esc(item.link)}">${esc(item.linkLabel ?? 'Details')}</a>` : ''}
            ${place ? `<a href="${esc(directions(place, byId[item.from]))}" aria-label="Directions to ${esc(place.name)}">${I.map} Maps</a>` : ''}
          </div>` : ''}
        </div>
      </div>
    </article>`;
  }

  function dashboard(sections, byId) {
    const regions = [...new Set(sections.map(section => section.region))];
    if (!regions.includes(region)) region = regions[0];
    const regional = sections.filter(section => section.region === region);
    const categories = [...new Set(regional.map(section => section.category).filter(Boolean))];
    if (!categories.includes(category)) category = categories[0];
    const picker = `<nav class="trip-regions" aria-label="Trip destinations">${regions.map(name => `<button type="button" data-region="${esc(name)}" aria-pressed="${region === name}">${esc(name)}</button>`).join('')}</nav>`;
    const filters = categories.length > 1 ? `<nav class="trip-categories" aria-label="${esc(region)} topics">${categories.map(name => `<button type="button" data-category="${esc(name)}" aria-pressed="${category === name}">${esc(name)}</button>`).join('')}</nav>` : '';
    const content = regional.filter(section => !section.category || section.category === category).map(section => `<section class="trip-section"><h2>${esc(section.title)}</h2>${section.items.map(item => dashboardItem(item, byId)).join('')}</section>`).join('');
    return picker + filters + content;
  }

  // Calendar: reads the free-text plan dates. "Nov 30 – Dec 4", "Fri Nov 20", "Dec 15 – 19" are exact;
  // anything else that names a day ("By Dec 20", "Dec 14 or ~Dec 5") is shown dashed as tentative.
  const MON = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'];
  const MONTH_NAMES = ['January','February','March','April','May','June','July','August','September','October','November','December'];
  const DAY = 864e5;
  let selDay = null;
  // Dates carry no year: pick the year that keeps them near when trip.json was last updated.
  const mkDate = (mon, day) => {
    const u = D && Date.parse(D.updated), ref = Number.isFinite(u) ? new Date(u) : new Date();
    let y = ref.getFullYear();
    if (mon - ref.getMonth() < -5) y++; else if (mon - ref.getMonth() > 6) y--;
    return new Date(y, mon, day);
  };
  const mi = s => MON.indexOf(String(s).slice(0, 3).toLowerCase());
  function parseWhen(s) {
    s = String(s || '').trim();
    const tentative = /^Maybe\s+/i.test(s) || /\s+target$/i.test(s);
    if (tentative) s = s.replace(/^Maybe\s+|\s+target$/gi, '');
    const m = s.match(/^(?:[A-Za-z]{3,9}\.?,?\s+)?([A-Za-z]{3,9})\.?\s+(\d{1,2})(?:\s*[–—-]\s*(?:([A-Za-z]{3,9})\.?\s+)?(\d{1,2}))?$/);
    if (m && mi(m[1]) >= 0 && (!m[3] || mi(m[3]) >= 0)) {
      const start = mkDate(mi(m[1]), +m[2]);
      let end = m[4] ? mkDate(m[3] ? mi(m[3]) : mi(m[1]), +m[4]) : start;
      if (end < start) end = start;
      return { start, end, tent: tentative };
    }
    for (const f of s.matchAll(/([A-Za-z]{3,9})\.?\s+(\d{1,2})\b/g)) {
      if (mi(f[1]) >= 0) { const d = mkDate(mi(f[1]), +f[2]); return { start: d, end: d, tent: true }; }
    }
    return null;
  }
  const cityVar = c => ({ manila: '--c-manila', cebu: '--c-cebu', siargao: '--c-siargao', tokyo: '--c-tokyo' })[String(c || '').toLowerCase()] || '--c-other';
  const key = d => `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
  const fmt = d => d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });

  function calendar(T, byId) {
    const all = Object.values(D.travelers).flatMap(t => t.plan.map(x => parseWhen(x.date)).filter(Boolean));
    if (!all.length) return '';
    const items = T.plan.map(x => ({ x, w: parseWhen(x.date), city: byId[x.place]?.city })).filter(i => i.w).sort((a, b) => a.w.start - b.w.start);
    const lanes = [];
    for (const i of items) { let l = 0; while (lanes[l] && lanes[l] >= i.w.start) l++; lanes[l] = i.w.end; i.lane = l; }
    const nLanes = Math.max(1, lanes.length);
    const first = new Date(Math.min(...all.map(w => w.start))), last = new Date(Math.max(...all.map(w => w.end)));
    const today = new Date(); today.setHours(0, 0, 0, 0);
    const sd = selDay ? new Date(...selDay.split('-').map(Number)) : null;
    const sel = sd ? items.filter(i => sd >= i.w.start && sd <= i.w.end) : [];
    let h = '';
    for (let mo = new Date(first.getFullYear(), first.getMonth(), 1); mo <= last; mo = new Date(mo.getFullYear(), mo.getMonth() + 1, 1)) {
      h += `<section class="cal" aria-label="${MONTH_NAMES[mo.getMonth()]} ${mo.getFullYear()}"><div class="cal-m">${MONTH_NAMES[mo.getMonth()]} ${mo.getFullYear()}</div><div class="cal-g">`;
      h += ['S','M','T','W','T','F','S'].map(w => `<div class="cal-w" aria-hidden="true">${w}</div>`).join('');
      for (let i = 0; i < mo.getDay(); i++) h += '<div></div>';
      const days = new Date(mo.getFullYear(), mo.getMonth() + 1, 0).getDate();
      for (let n = 1; n <= days; n++) {
        const d = new Date(mo.getFullYear(), mo.getMonth(), n), wd = d.getDay();
        const on = items.filter(i => d >= i.w.start && d <= i.w.end);
        let bars = '';
        for (let l = 0; l < nLanes; l++) {
          const i = on.find(o => o.lane === l);
          if (!i) { bars += '<div class="bar gap"></div>'; continue; }
          const cls = ['bar', i.w.tent && 'tent', (+d === +i.w.start || wd === 0 || n === 1) && 'l', (+d === +i.w.end || wd === 6 || n === days) && 'r'].filter(Boolean).join(' ');
          bars += `<div class="${cls}" style="--cc:var(${cityVar(i.city)})"></div>`;
        }
        const label = `${fmt(d)}${on.length ? ': ' + on.map(o => o.x.title).join(', ') : ''}`;
        const cls = ['cal-d', on.length && 'has', +d === +today && 'today', d < today && 'past', selDay === key(d) && 'sel'].filter(Boolean).join(' ');
        h += `<button class="${cls}" data-day="${key(d)}" aria-label="${esc(label)}" ${on.length ? '' : 'tabindex="-1"'} aria-pressed="${selDay === key(d)}"><span class="cal-n">${n}</span>${bars}</button>`;
      }
      h += '</div>';
      if (sel.length && sd.getFullYear() === mo.getFullYear() && sd.getMonth() === mo.getMonth()) {
        h += `<div class="cal-x" role="status"><div class="s">${esc(fmt(sd))}</div>${sel.map(i => `<div class="row"><span class="sw${i.w.tent ? ' tent' : ''}" style="--cc:var(${cityVar(i.city)})"></span><div class="main"><div class="t">${esc(i.x.title)}</div><div class="s">${esc([i.x.date, i.x.sub].filter(Boolean).join(' · '))}</div></div></div>`).join('')}</div>`;
      }
      h += '</section>';
    }
    const cities = [...new Set(items.map(i => i.city).filter(Boolean))];
    h += `<div class="legend">${cities.map(c => `<span><span class="sw" style="--cc:var(${cityVar(c)})"></span>${esc(c)}</span>`).join('')}${items.some(i => i.w.tent) ? '<span><span class="sw tent" style="--cc:var(--c-other)"></span>Not firm</span>' : ''}</div>`;
    const undated = T.plan.filter(x => !parseWhen(x.date));
    if (undated.length) h += `<p class="undated">No date yet: ${undated.map(x => esc(x.title)).join(', ')}</p>`;
    return h;
  }

  function render() {
    document.querySelector('.who').hidden = view !== 'plan';
    document.querySelectorAll('.seg button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.v === view)));
    document.querySelectorAll('.who button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.who === who)));
    if (view === 'where') {
      whereView ??= window.mountTripWhere(document.getElementById('out'));
      whereView.setTravelers(D?.travelers);
      return;
    }
    whereView?.dispose();
    whereView = null;
    if (!D) {
      document.getElementById('out').innerHTML = '<p class="state" role="status">Loading trip…</p>';
      return;
    }
    const byId = Object.fromEntries(D.places.map(p => [p.id, p]));
    let h = '';
    const T = D.travelers[who];
    if (view === 'plan') {
      const tripSections = (T.todos ?? []).filter(section => section.region);
      if (tripSections.length) {
        document.getElementById('out').innerHTML = dashboard(tripSections, byId);
        return;
      }
      if (who === 'tom') {
        if (showInstall) h += `<details class="group install-guide"><summary>Install on iPhone</summary><p>Open this link in Safari. Tap Safari’s <strong>Share</strong> → <strong>Add to Home Screen</strong>. Keep <strong>Open as Web App</strong> on and tap <strong>Add</strong>.</p></details>`;
        h += `<h2 class="hdr">Tom’s updates</h2><div class="group">${tomNotes.map(note => `<div class="row"><div class="main">${esc(note)}</div></div>`).join('')}<div class="row update-actions"><a href="${edit}tom-notes.txt" target="_blank" rel="noopener">Edit updates</a><a href="${edit}trip.json" target="_blank" rel="noopener">Edit full plan</a></div></div>`;
      }
      for (const section of T.todos ?? []) {
        h += `<h2 class="hdr">${esc(section.title)}</h2><div class="group">${section.items.map(taskRow).join('')}</div>`;
      }
      const cal = calendar(T, byId);
      if (cal) h += `<h2 class="hdr">Calendar</h2>${cal}`;
      h += '<h2 class="hdr">Itinerary</h2>';
      h += `<div class="group">${T.plan.map(x => { const p = byId[x.place]; return `<a class="row" ${p ? `href="${gmap(p.ja || p.addr)}"` : ''}><div class="date">${esc(x.date)}</div><div class="main"><div class="t">${esc(x.title)}</div>${x.sub ? `<div class="s">${esc(x.sub)}</div>` : ''}</div>${p ? '<span class="chev">›</span>' : ''}</a>`; }).join('')}</div>`;
      if (T.bucket && T.bucket.length) h += `<h2 class="hdr">Bucket list</h2><div class="group">${T.bucket.map(b => `<div class="row"><div class="main"><div class="t">${esc(b)}</div></div></div>`).join('')}</div>`;
    } else if (view === 'places') {
      for (const city of [...new Set(D.places.map(p => p.city))]) h += `<h2 class="hdr">${esc(city)}</h2><div class="group">${D.places.filter(p => p.city === city).map(placeRow).join('')}</div>`;
    } else {
      const groups = new Map();
      for (const person of D.people) {
        const title = person.group || 'Contacts';
        if (!groups.has(title)) groups.set(title, []);
        groups.get(title).push(person);
      }
      for (const [title, contacts] of groups) {
        h += `<h2 class="hdr">${esc(title)}</h2><div class="group">${contacts.map(personRow).join('')}</div>`;
      }
      h += `<h2 class="hdr">Emergency</h2><div class="group">${D.emergency.map(personRow).join('')}</div>`;
    }
    document.getElementById('out').innerHTML = h;
  }

  document.getElementById('share-trip').addEventListener('click', async () => {
    const sharingWhere = view === 'where';
    const url = sharingWhere ? new URL('?view=where', base).href : tomPlan;
    if (navigator.share) {
      try { await navigator.share({ title: 'Trip', url }); return; }
      catch (error) { if (error.name === 'AbortError') return; }
    }
    try { await navigator.clipboard.writeText(url); toast(sharingWhere ? 'Map link copied' : 'Tom’s link copied'); }
    catch { window.location.assign(url); }
  });

  document.addEventListener('click', e => {
    const destination = e.target.closest('button[data-region]');
    if (destination) {
      region = destination.dataset.region;
      category = '';
      render();
      const selected = document.querySelector('.trip-regions [aria-pressed="true"]');
      selected?.focus({ preventScroll: true });
      return;
    }
    const topic = e.target.closest('button[data-category]');
    if (topic) {
      category = topic.dataset.category;
      render();
      document.querySelector('.trip-categories [aria-pressed="true"]')?.focus({ preventScroll: true });
      return;
    }
    const w = e.target.closest('.who button');
    if (w) {
      who = w.dataset.who;
      selDay = null;
      store.set('who', who);
      if (linkedTraveler) {
        const url = new URL(location.href);
        url.searchParams.set('who', who);
        history.replaceState(null, '', url);
      }
      render();
      return;
    }
    const cd = e.target.closest('.cal-d.has');
    if (cd) { selDay = selDay === cd.dataset.day ? null : cd.dataset.day; render(); document.querySelector(`[data-day="${selDay || cd.dataset.day}"]`)?.focus({ preventScroll: true }); return; }
    const stage = e.target.closest('.seg button');
    if (stage) {
      view = stage.dataset.v;
      const url = new URL(location.href);
      if (view === 'where') url.searchParams.set('view', view);
      else url.searchParams.delete('view');
      history.replaceState(null, '', url);
      store.set('view', view);
      render();
      window.scrollTo(0, 0);
      return;
    }
    const c = e.target.closest('[data-copy]');
    if (c) {
      const copy = navigator.clipboard?.writeText(c.dataset.copy);
      if (copy) copy.then(() => toast('Copied'), () => toast('Could not copy. Select the text to copy it.'));
      else toast('Could not copy. Select the text to copy it.');
    }
  });

  async function refreshTrip() {
    if (refreshing) return;
    refreshing = true;
    const read = async path => {
      const response = await fetch(new URL(path, base), { cache: 'no-store' });
      return response.ok ? response.text() : null;
    };
    try {
      const [data, notes] = await Promise.all([read('trip.json'), read('tom-notes.txt')].map(reading => reading.catch(() => null)));
      const nextNotes = notes === null ? tomNotes : notes.split(/\r?\n/).map(line => line.trim()).filter(line => line && !line.startsWith('#'));
      const notesChanged = JSON.stringify(nextNotes) !== JSON.stringify(tomNotes);
      if (data && data !== tripText) {
        try {
          const parsed = JSON.parse(data);
          if ([parsed.travelers?.tom?.plan, parsed.travelers?.jerry?.plan, parsed.places, parsed.people, parsed.emergency].every(Array.isArray)) {
            D = parsed;
            tripText = data;
            tomNotes = nextNotes;
            return render();
          }
        } catch { /* Keep the data already loaded if a GitHub edit has invalid JSON. */ }
      }
      if (D) {
        if (notesChanged) { tomNotes = nextNotes; render(); }
        return;
      }
      if (view === 'where') return;
      document.getElementById('out').innerHTML = '<p class="state" role="status">Trip could not load.</p><button class="lock" id="retry">Try again</button>';
      document.getElementById('retry').addEventListener('click', refreshTrip);
    } finally {
      refreshing = false;
    }
  }

  render();
  refreshTrip();
  document.addEventListener('visibilitychange', () => { if (!document.hidden) refreshTrip(); });
  window.addEventListener('online', refreshTrip);
  if ('serviceWorker' in navigator) navigator.serviceWorker.register(new URL('sw.js', base));
})();
