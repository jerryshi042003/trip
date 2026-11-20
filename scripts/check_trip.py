#!/usr/bin/env python3
"""Check docs/trip.json against what the iPhone app (ios/Trip/Model.swift) can decode.

If the app can't decode the file it silently keeps the old copy, so run this
before every push:  python3 scripts/check_trip.py
"""
import json, sys
from urllib.parse import urlparse

path = sys.argv[1] if len(sys.argv) > 1 else 'docs/trip.json'
errs = []
def need(obj, key, typ, where):
    if not isinstance(obj, dict) or key not in obj or not isinstance(obj[key], typ):
        errs.append(f'{where}: "{key}" must be a {typ.__name__ if isinstance(typ, type) else "/".join(t.__name__ for t in typ)}')
        return False
    return True
def opt(obj, key, typ, where):
    if isinstance(obj, dict) and key in obj and obj[key] is not None and not isinstance(obj[key], typ):
        errs.append(f'{where}: "{key}" must be a {typ.__name__ if isinstance(typ, type) else "number"} or left out')

try:
    d = json.load(open(path, encoding='utf-8'))
except Exception as e:
    print(f'NOT VALID JSON: {e}'); sys.exit(1)

opt(d, 'updated', str, 'top')
for k in ('places', 'people', 'emergency'): need(d, k, list, 'top')
if need(d, 'travelers', dict, 'top'):
    for who, t in d['travelers'].items():
        w = f'travelers.{who}'
        need(t, 'name', str, w)
        if need(t, 'plan', list, w):
            for i, p in enumerate(t['plan']):
                need(p, 'date', str, f'{w}.plan[{i}]'); need(p, 'title', str, f'{w}.plan[{i}]')
                opt(p, 'sub', str, f'{w}.plan[{i}]'); opt(p, 'place', str, f'{w}.plan[{i}]')
        opt(t, 'bucket', list, w); opt(t, 'where', str, w)
        for si, s in enumerate(t.get('todos') or []):
            sw = f'{w}.todos[{si}]'
            need(s, 'title', str, sw)
            titles = set()
            if need(s, 'items', list, sw):
                for ii, it in enumerate(s['items']):
                    iw = f'{sw} "{s.get("title")}" item {ii}'
                    need(it, 'title', str, iw); need(it, 'detail', str, iw); opt(it, 'draft', str, iw)
                    if it.get('link') is not None:
                        u = it['link']
                        if not isinstance(u, str) or not urlparse(u).scheme or ' ' in u:
                            errs.append(f'{iw}: "link" must be a full URL without spaces')
                    if it.get('title') in titles: errs.append(f'{iw}: duplicate item title "{it.get("title")}" in one section')
                    titles.add(it.get('title'))
for i, p in enumerate(d.get('places') or []):
    for k in ('id', 'city', 'name', 'addr'): need(p, k, str, f'places[{i}]')
    opt(p, 'ja', str, f'places[{i}]'); opt(p, 'lat', (int, float), f'places[{i}]'); opt(p, 'lon', (int, float), f'places[{i}]')
for key in ('people', 'emergency'):
    for i, p in enumerate(d.get(key) or []):
        need(p, 'name', str, f'{key}[{i}]')
        for k in ('role', 'group', 'phone', 'phoneLabel', 'whatsapp', 'email', 'ig', 'fb', 'web'): opt(p, k, str, f'{key}[{i}] {p.get("name")}')
for i, m in enumerate(d.get('media') or []):
    need(m, 'title', str, f'media[{i}]'); need(m, 'url', str, f'media[{i}]')

if errs:
    print(f'{len(errs)} problem(s); the iPhone app would ignore this file:')
    for e in errs[:40]: print(' -', e)
    sys.exit(1)
print(f'OK: {len(d["people"])} people, ' + ', '.join(f'{w} {len(t.get("todos") or [])} sections' for w, t in d['travelers'].items()))
