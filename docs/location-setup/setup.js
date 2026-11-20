(() => {
  const parameters = new URLSearchParams(location.hash.slice(1));
  if (!location.hash) return;
  history.replaceState(null, '', location.pathname + location.search);
  const user = parameters.get('traveler');
  const token = parameters.get('token');
  if (!['jerry', 'tom'].includes(user) || !/^[A-Za-z0-9_-]{43}$/.test(token ?? '')) return;

  const configuration = {
    _type: 'configuration',
    mode: 3,
    url: 'https://jerry-trip.vercel.app/api/location',
    auth: true,
    username: user,
    password: token,
    deviceid: 'iphone',
    tid: user === 'tom' ? 'TO' : 'JE',
    monitoring: 2,
    locatorInterval: 60,
    locatorDisplacement: 25,
    ignoreInaccurateLocations: 100,
    remoteConfiguration: false,
    extendedData: false,
  };
  const link = document.getElementById('configure');
  link.href = 'owntracks:///config?inline=' + encodeURIComponent(btoa(JSON.stringify(configuration)));
  link.hidden = false;
  document.getElementById('needs-link').hidden = true;
})();
