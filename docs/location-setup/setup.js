(() => {
  // The private link carries #traveler=tom&token=… ; it never reaches a server (fragment only).
  const parameters = new URLSearchParams(location.hash.slice(1));
  if (!location.hash) return;
  history.replaceState(null, '', location.pathname + location.search);
  const user = parameters.get('traveler');
  const token = parameters.get('token');
  if (!['jerry', 'tom'].includes(user) || !/^[A-Za-z0-9_-]{43}$/.test(token ?? '')) return;

  const link = document.getElementById('open');
  link.href = 'trip://pair?traveler=' + user + '&token=' + encodeURIComponent(token);
  link.hidden = false;
  document.getElementById('needs-link').hidden = true;
})();
