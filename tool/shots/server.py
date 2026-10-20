#!/usr/bin/env python3
"""Fixture server for the EduX mobile screenshot run (Python stdlib only).

    python3 tool/shots/server.py [--port 8000] [--fixtures tool/shots/fixtures] [--shots shots]

* POST /api/v1/auth/login {login, password}: answers with the recorded login of that phone; the token is
  "shots-<role>". Every later request is served from fixtures/<role>/ (then fixtures/_public/) by
  Authorization: Bearer shots-<role>.
* GET: exact method+path+query match, otherwise the recorded variant of the same path whose query is
  closest (dates differ from run to run). Unknown GETs -> 404 JSON and a "MISS" log line.
* Other POST/PUT/DELETE -> the recorded response of that method+path if any (e.g. billing/quote), else 200 {}.
* "__SERVER__" inside fixtures is replaced by this server's address as the client sees it (Host header).
* POST /__shot/<name>: the test asks for a screenshot. With a PNG body the body is saved; otherwise
  `adb exec-out screencap -p` is run (real device frame incl. status bar). Files go to --shots/<name>.png.
* POST /__log: a line from the test is echoed to stdout (CI log).
"""
import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOCK = threading.Lock()


def log(*parts):
    with LOCK:
        print(*parts, flush=True)


def canonical(path, query):
    items = sorted((k, v) for k, v in query.items() if v != '')
    return path.strip('/') + ('?' + urllib.parse.urlencode(items) if items else '')


class Store:
    def __init__(self, root):
        self.root = root
        self.roles = {}
        for folder in sorted(glob.glob(os.path.join(root, '*'))):
            if not os.path.isdir(folder):
                continue
            table = {}
            for name in glob.glob(os.path.join(folder, '*.json')):
                with open(name, encoding='utf-8') as fh:
                    rec = json.load(fh)
                table.setdefault((rec['method'], rec['path']), []).append(rec)
            self.roles[os.path.basename(folder)] = table
        with open(os.path.join(root, 'logins.json'), encoding='utf-8') as fh:
            meta = json.load(fh)
        self.password = meta.get('password', 'password')
        self.logins = {}
        for phone, entry in meta['logins'].items():
            self.logins[re.sub(r'\D', '', phone)[-9:]] = entry
        log(f'fixtures: {sum(len(v) for t in self.roles.values() for v in t.values())} responses, roles: {", ".join(self.roles)}')

    def find(self, role, method, path, query):
        for name in (role, '_public'):
            table = self.roles.get(name) or {}
            candidates = table.get((method, path))
            if not candidates:
                continue
            exact = [c for c in candidates if c.get('query', {}) == query]
            if exact:
                return exact[0], 'exact'

            def score(c):
                q = c.get('query', {})
                same = sum(1 for k, v in query.items() if q.get(k) == v)
                keys = sum(1 for k in query if k in q)
                extra = sum(1 for k in q if k not in query)
                ok = c.get('status', 200) < 400
                return (ok, same, keys, -extra)
            return max(candidates, key=score), 'near'
        return None, None


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    store = None
    shots = 'shots'

    def log_message(self, fmt, *args):
        pass

    def _body(self):
        length = int(self.headers.get('Content-Length') or 0)
        return self.rfile.read(length) if length else b''

    def _send(self, status, payload, content_type='application/json'):
        if isinstance(payload, (bytes, bytearray)):
            data = bytes(payload)
        else:
            text = json.dumps(payload, ensure_ascii=False)
            host = self.headers.get('Host') or 'localhost:8000'
            text = text.replace('__SERVER__', f'http://{host}')
            data = text.encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', content_type + ('; charset=utf-8' if content_type.endswith('json') else ''))
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _role(self):
        auth = self.headers.get('Authorization') or ''
        m = re.match(r'Bearer\s+shots-(\w+)', auth)
        return m.group(1) if m else None

    @staticmethod
    def _focus(adb):
        out = subprocess.run([adb, 'shell', 'dumpsys', 'window', 'displays'], capture_output=True, timeout=20).stdout.decode('utf-8', 'replace')
        lines = [line.strip() for line in out.splitlines() if 'mCurrentFocus' in line or 'mFocusedApp' in line]
        return ' '.join(lines)

    def _dismiss_system_dialogs(self, adb):
        """A slow CI emulator sometimes shows «… isn't responding» (ANR) over the app: close it before capturing."""
        for _ in range(4):
            focus = self._focus(adb)
            if 'Not Responding' not in focus and 'Application Error' not in focus and 'uz.edux' in focus:
                return
            if 'Not Responding' not in focus and 'Application Error' not in focus:
                return
            log(f'  system dialog over the app ({focus[:160]}) -> closing')
            subprocess.run([adb, 'shell', 'am', 'broadcast', '-a', 'android.intent.action.CLOSE_SYSTEM_DIALOGS'], capture_output=True, timeout=20)
            subprocess.run([adb, 'shell', 'input', 'keyevent', 'KEYCODE_ESCAPE'], capture_output=True, timeout=20)
            import time
            time.sleep(1.5)

    def _shot(self, name, body):
        name = re.sub(r'[^A-Za-z0-9._-]+', '_', name)
        os.makedirs(self.shots, exist_ok=True)
        target = os.path.join(self.shots, name + '.png')
        if body[:8] == b'\x89PNG\r\n\x1a\n':
            with open(target, 'wb') as fh:
                fh.write(body)
            log(f'SHOT {name} (uploaded, {len(body)} bytes)')
            return self._send(200, {'ok': True, 'source': 'upload', 'bytes': len(body)})
        adb = shutil.which('adb') or os.path.join(os.environ.get('ANDROID_HOME', os.environ.get('ANDROID_SDK_ROOT', '')), 'platform-tools', 'adb')
        try:
            self._dismiss_system_dialogs(adb)
            png = subprocess.run([adb, 'exec-out', 'screencap', '-p'], capture_output=True, timeout=40).stdout
        except Exception as error:  # noqa: BLE001
            log(f'SHOT {name} FAILED: {error}')
            return self._send(500, {'ok': False, 'message': str(error)})
        if png[:8] != b'\x89PNG\r\n\x1a\n':
            log(f'SHOT {name} FAILED: not a png ({len(png)} bytes)')
            return self._send(500, {'ok': False, 'message': 'screencap failed'})
        with open(target, 'wb') as fh:
            fh.write(png)
        log(f'SHOT {name} (adb, {len(png)} bytes)')
        return self._send(200, {'ok': True, 'source': 'adb', 'bytes': len(png)})

    def _handle(self, method):
        parsed = urllib.parse.urlsplit(self.path)
        path = parsed.path
        body = self._body()
        if path.startswith('/__shot/'):
            return self._shot(path[len('/__shot/'):], body)
        if path == '/__log':
            log('TEST', body.decode('utf-8', 'replace'))
            return self._send(200, {'ok': True})
        if path in ('/', '/health'):
            return self._send(200, {'ok': True})
        if not path.startswith('/api/v1/'):
            log(f'MISS {method} {path} (not api)')
            return self._send(404, {'message': 'Topilmadi.'})
        api_path = path[len('/api/v1/'):].strip('/')
        query = dict(urllib.parse.parse_qsl(parsed.query, keep_blank_values=False))
        role = self._role()
        if method == 'POST' and api_path == 'auth/login':
            try:
                data = json.loads(body or b'{}')
            except ValueError:
                data = {}
            entry = self.store.logins.get(re.sub(r'\D', '', str(data.get('login', '')))[-9:])
            if not entry or data.get('password') != self.store.password:
                log(f'LOGIN rejected {data.get("login")}')
                return self._send(422, {'message': "Login yoki parol noto'g'ri.", 'errors': {'login': ["Login yoki parol noto'g'ri."]}})
            log(f'LOGIN {entry["role"]}')
            return self._send(200, entry['response'])
        if method != 'GET':
            record, _ = self.store.find(role or '_public', method, api_path, query)
            log(f'WRITE {method} {api_path} role={role}{" (recorded)" if record else ""}')
            if record is not None:
                return self._send(record.get('status', 200), record.get('body') if record.get('body') is not None else {})
            return self._send(200, {})
        record, how = self.store.find(role or '_public', 'GET', api_path, query)
        key = canonical(api_path, query)
        if record is None:
            log(f'MISS GET {key} role={role}')
            return self._send(404, {'message': 'Topilmadi.'})
        if how != 'exact':
            log(f'NEAR GET {key} role={role} -> {canonical(record["path"], record.get("query", {}))}')
        return self._send(record.get('status', 200), record.get('body') if record.get('body') is not None else {})

    def do_GET(self):
        self._handle('GET')

    def do_POST(self):
        self._handle('POST')

    def do_PUT(self):
        self._handle('PUT')

    def do_DELETE(self):
        self._handle('DELETE')

    def do_PATCH(self):
        self._handle('PATCH')


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', default='0.0.0.0')
    parser.add_argument('--port', type=int, default=8000)
    parser.add_argument('--fixtures', default=os.path.join(here, 'fixtures'))
    parser.add_argument('--shots', default='shots')
    args = parser.parse_args()
    Handler.store = Store(args.fixtures)
    Handler.shots = args.shots
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    log(f'EduX fixture server on http://{args.host}:{args.port} (shots -> {os.path.abspath(args.shots)})')
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    sys.exit(main())
