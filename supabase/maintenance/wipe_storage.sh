#!/bin/bash
# ONE-OFF: delete every object in the app's Storage buckets via the Storage API (files + rows). Buckets stay.
# usage: SUPABASE_SERVICE_KEY=... ./wipe_storage.sh      (key from your own env / vault — never commit it)
set -euo pipefail
python3 - <<'PY'
import json, os, urllib.request
U = 'https://eisstodgncimypdawisy.supabase.co/storage/v1'
K = os.environ['SUPABASE_SERVICE_KEY']
def req(method, path, body):
    r = urllib.request.Request(U + path, data=json.dumps(body).encode(), method=method,
        headers={'apikey': K, 'Authorization': 'Bearer ' + K, 'Content-Type': 'application/json'})
    return json.load(urllib.request.urlopen(r))
def files(b, prefix=''):
    out = []
    for o in req('POST', f'/object/list/{b}', {'prefix': prefix, 'limit': 1000}):
        p = prefix + o['name']
        out += [p] if o.get('id') else files(b, p + '/')
    return out
for b in ('avatars', 'chat', 'nx-media'):
    f = files(b)
    for i in range(0, len(f), 500):
        req('DELETE', f'/object/{b}', {'prefixes': f[i:i + 500]})
    print(b, 'deleted', len(f), 'left', len(files(b)))
PY
