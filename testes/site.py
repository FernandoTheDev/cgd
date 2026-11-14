#!/usr/bin/env python3
"""Verifica links locais e, opcionalmente, o website em Chrome desktop/mobile."""
import argparse
import base64
from functools import partial
from html.parser import HTMLParser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import time
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / 'docs'
parser = argparse.ArgumentParser()
parser.add_argument('--static-only', action='store_true')
args = parser.parse_args()

class Markup(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()
        self.references = []
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            assert attrs['id'] not in self.ids, f'ID duplicado: {attrs["id"]}'
            self.ids.add(attrs['id'])
        for key in ('href', 'src'):
            if key in attrs:
                self.references.append(attrs[key])

markup = Markup()
markup.feed((DOCS / 'index.html').read_text())
for reference in markup.references:
    if reference.startswith('#'):
        assert reference[1:] in markup.ids, f'Âncora inexistente: {reference}'
    elif '://' not in reference and not reference.startswith(('mailto:', 'data:')):
        assert (DOCS / reference.split('#')[0].split('?')[0]).is_file(), f'Arquivo inexistente: {reference}'
print('HTML: IDs, âncoras e assets locais validados.')
if args.static_only:
    raise SystemExit(0)

try:
    import websocket
except ImportError:
    raise SystemExit('QA de navegador requer websocket-client; os checks estáticos passaram. Use --static-only ou instale requirements-site.txt.')
browser = next((shutil.which(name) for name in ['google-chrome', 'chromium', 'chromium-browser'] if shutil.which(name)), None)
if not browser:
    raise SystemExit('Chrome/Chromium não encontrado para QA visual.')

class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass

server = ThreadingHTTPServer(('127.0.0.1', 0), partial(QuietHandler, directory=str(DOCS)))
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
origin = f'http://127.0.0.1:{server.server_port}'
assert urlopen(origin, timeout=10).status == 200
out = ROOT / 'out/site'
out.mkdir(parents=True, exist_ok=True)

with tempfile.TemporaryDirectory(prefix='cgd chrome ') as profile:
    process = subprocess.Popen([browser, '--headless=new', '--no-sandbox', '--disable-dev-shm-usage', '--remote-debugging-port=0', '--remote-allow-origins=http://localhost', f'--user-data-dir={profile}', 'about:blank'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        active = Path(profile) / 'DevToolsActivePort'
        for _ in range(100):
            if active.exists():
                break
            assert process.poll() is None, 'Chrome encerrou antes de iniciar.'
            time.sleep(.1)
        port = int(active.read_text().splitlines()[0])
        target = json.load(urlopen(Request(f'http://127.0.0.1:{port}/json/new?about:blank', method='PUT'), timeout=10))
        ws = websocket.create_connection(target['webSocketDebuggerUrl'], origin='http://localhost', timeout=20)
        message_id = 0
        errors = []
        def rpc(method, params=None):
            global message_id
            message_id += 1
            current = message_id
            ws.send(json.dumps({'id': current, 'method': method, 'params': params or {}}))
            while True:
                reply = json.loads(ws.recv())
                if reply.get('method') == 'Runtime.exceptionThrown':
                    errors.append(reply['params'])
                if reply.get('id') == current:
                    assert 'error' not in reply, reply
                    return reply.get('result', {})
        def evaluate(expression):
            result = rpc('Runtime.evaluate', {'expression': expression, 'returnByValue': True, 'awaitPromise': True, 'userGesture': True})
            assert 'exceptionDetails' not in result, result
            return result.get('result', {}).get('value')
        rpc('Page.enable')
        rpc('Runtime.enable')
        rpc('Emulation.setDeviceMetricsOverride', {'width': 1440, 'height': 1000, 'deviceScaleFactor': 1, 'mobile': False})
        rpc('Page.navigate', {'url': origin})
        for _ in range(100):
            if evaluate('document.readyState') == 'complete':
                break
            time.sleep(.1)
        assert evaluate('document.title').startswith('CGD')
        assert evaluate('[...document.images].every(image => image.complete && image.naturalWidth > 0)')
        assert evaluate('document.documentElement.scrollWidth <= window.innerWidth')
        evaluate("document.querySelector('#feature-search').value='excecoes';document.querySelector('#feature-search').dispatchEvent(new Event('input'))")
        assert evaluate("[...document.querySelectorAll('.feature-row')].filter(row => !row.hidden).length") == 1
        evaluate("document.querySelector('#feature-search').value='inexistente_xyz';document.querySelector('#feature-search').dispatchEvent(new Event('input'))")
        assert evaluate("!document.querySelector('#features-empty').hidden")
        evaluate("document.querySelector('#feature-search').value='';document.querySelector('#feature-search').dispatchEvent(new Event('input'))")
        evaluate("document.querySelector('#distro').value='fedora';document.querySelector('#distro').dispatchEvent(new Event('change'))")
        assert 'dnf install' in evaluate("document.querySelector('#deps-code').textContent")
        evaluate("document.querySelector('#distro').value='debian';document.querySelector('#distro').dispatchEvent(new Event('change'))")
        evaluate("document.querySelector('[data-copy=build-code]').click()")
        time.sleep(.3)
        assert evaluate("document.querySelector('#copy-status').textContent.length > 0")
        evaluate('window.scrollTo(0,0)')
        screenshot = rpc('Page.captureScreenshot', {'format': 'png'})
        (out / 'desktop.png').write_bytes(base64.b64decode(screenshot['data']))
        rpc('Emulation.setDeviceMetricsOverride', {'width': 390, 'height': 844, 'deviceScaleFactor': 1, 'mobile': True})
        time.sleep(.3)
        assert evaluate('document.documentElement.scrollWidth <= window.innerWidth'), 'Overflow horizontal no mobile.'
        (out / 'mobile.png').write_bytes(base64.b64decode(rpc('Page.captureScreenshot', {'format': 'png'})['data']))
        evaluate("document.querySelector('a[href=\"#seguranca\"]').click()")
        assert evaluate("location.hash === '#seguranca'")
        assert not errors, errors
        report = {'passed': True, 'desktop': '1440x1000', 'mobile': '390x844', 'checks': ['assets', 'anchors', 'responsive overflow', 'accent-insensitive feature search', 'empty search', 'dependency selector', 'copy interaction', 'navigation', 'no JS exceptions']}
        (out / 'relatorio.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
        ws.close()
        print('Chrome: desktop/mobile, busca, seleção de dependências, cópia e navegação validados.')
    finally:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        server.shutdown()
        server.server_close()
