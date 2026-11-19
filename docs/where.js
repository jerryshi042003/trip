(() => {
  const endpoint = 'https://jerry-trip.vercel.app/api/location';
  const travelers = [['jerry', 'Jerry'], ['tom', 'Tom']];
  const maxAge = 86_400;
  const tileURL = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  const ageInMinutes = point => Math.max(0, Math.floor((Date.now() / 1000 - point.tst) / 60));
  const googlePin = point => 'https://www.google.com/maps/search/?api=1&query=' + encodeURIComponent(point.lat + ',' + point.lon);

  function fallbackURL(value) {
    try {
      const url = new URL(value);
      return url.protocol === 'https:' && (
        url.hostname === 'maps.app.goo.gl' || url.hostname === 'maps.google.com' ||
        (['google.com', 'www.google.com'].includes(url.hostname) && url.pathname.startsWith('/maps'))
      ) ? url.href : null;
    } catch { return null; }
  }

  window.mountTripWhere = function (root) {
    root.innerHTML = `<section class="live-where" aria-label="Live locations">
      <div class="live-map" aria-label="Map of Jerry and Tom"></div>
      <p class="live-message" role="status">Checking locations…</p>
      <div class="group live-travelers">${travelers.map(([id, name]) => `
        <div class="row" data-location="${id}">
          <div class="main"><div class="t">${name}</div><div class="s live-age"></div></div>
          <div class="live-actions"><a class="live-pin-link" hidden>Open pin</a><a class="live-sharing-link" hidden>Google Maps share</a></div>
        </div>`).join('')}</div>
    </section>`;
    const message = root.querySelector('.live-message');
    const rows = Object.fromEntries(travelers.map(([id]) => [id, root.querySelector('[data-location="' + id + '"]')]));
    const map = window.L?.map(root.querySelector('.live-map'), { scrollWheelZoom: false, attributionControl: false })
      .setView([23, 130], 3);
    if (map) {
      L.control.attribution({ prefix: false }).addTo(map);
      L.tileLayer(tileURL, {
        attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
        maxZoom: 19,
      }).addTo(map);
    }
    const markers = {};
    let latest = {};
    let fallbacks = {};
    let available = false;
    let initial = true;
    let timer;
    let request;
    let disposed = false;

    function render() {
      const previous = Object.keys(markers).sort().join(',');
      for (const [id, name] of travelers) {
        const row = rows[id];
        const point = latest[id];
        const age = point && ageInMinutes(point);
        const usable = point && Number.isFinite(point.lat) && Number.isFinite(point.lon) &&
          Number.isFinite(point.tst) && age < (point.test ? 10 : maxAge / 60);
        const pinLink = row.querySelector('.live-pin-link');
        const shareLink = row.querySelector('.live-sharing-link');
        row.querySelector('.live-age').textContent = usable ? [
          point.test ? 'Test location' : age >= 15 ? 'Last seen' : 'Updated',
          age < 1 ? 'just now' : age + ' min ago',
          Number.isInteger(point.batt) ? point.batt + '% battery' : '',
        ].filter(Boolean).join(' · ') : initial ? '' : available ? 'Not shared yet' : 'Location unavailable';
        pinLink.hidden = !usable;
        if (usable) pinLink.href = googlePin(point);
        else pinLink.removeAttribute('href');
        const link = fallbacks[id];
        shareLink.hidden = !link;
        if (link) shareLink.href = link;
        else shareLink.removeAttribute('href');
        if (!map) continue;
        if (!usable) {
          if (markers[id]) markers[id].remove();
          delete markers[id];
          continue;
        }
        if (!markers[id]) {
          const icon = L.divIcon({
            className: 'live-avatar live-avatar-' + id,
            html: '<span>' + name[0] + '</span>',
            iconSize: [32, 32],
          });
          const popupLink = document.createElement('a');
          popupLink.href = pinLink.href;
          popupLink.textContent = 'Open ' + name + ' in Google Maps';
          markers[id] = L.marker([point.lat, point.lon], { icon, title: name, alt: name })
            .bindTooltip(name, { permanent: true, direction: 'right', offset: [19, 0], className: 'live-map-label' })
            .bindPopup(popupLink).addTo(map);
        } else {
          markers[id].setLatLng([point.lat, point.lon]);
          markers[id].getPopup().getContent().href = pinLink.href;
        }
        markers[id].setOpacity(age >= 15 ? 0.65 : 1);
      }
      const active = Object.keys(markers).sort().join(',');
      if (previous !== active && active) {
        map.fitBounds(L.latLngBounds(Object.values(markers).map(marker => marker.getLatLng())),
          { padding: [45, 50], maxZoom: 13, animate: false });
      }
      const hasPoint = travelers.some(([id]) => !rows[id].querySelector('.live-pin-link').hidden);
      const status = !map ? 'Map could not load. You can still open a pin below.' :
        initial ? 'Checking locations…' :
        !available ? 'Live refresh unavailable. Check your connection.' :
        !hasPoint ? 'Pins appear when Jerry or Tom starts sharing.' : '';
      if (message.textContent !== status) message.textContent = status;
      message.hidden = !status;
    }

    async function refresh() {
      if (disposed || document.hidden || request) return;
      clearTimeout(timer);
      request = new AbortController();
      const timeout = setTimeout(() => request?.abort(), 8000);
      try {
        const response = await fetch(endpoint, { cache: 'no-store', signal: request.signal });
        if (!response.ok) throw new Error('Location feed unavailable');
        const data = await response.json();
        latest = data.locations ?? {};
        available = true;
      } catch { available = false; }
      finally {
        clearTimeout(timeout);
        request = null;
        initial = false;
        if (!disposed) {
          render();
          timer = setTimeout(refresh, 60_000);
        }
      }
    }
    document.addEventListener('visibilitychange', refresh);
    window.addEventListener('online', refresh);
    refresh();
    return {
      setTravelers(data) {
        fallbacks = Object.fromEntries(travelers.map(([id]) => [id, fallbackURL(data?.[id]?.where)]));
        render();
      },
      dispose() {
        disposed = true;
        request?.abort();
        clearTimeout(timer);
        document.removeEventListener('visibilitychange', refresh);
        window.removeEventListener('online', refresh);
        map?.remove();
      },
    };
  };
})();
