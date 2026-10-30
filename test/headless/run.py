#!/usr/bin/env python3
"""Run under dbus-run-session; all settings, quotes and screenshots use a fresh build/headless directory."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

REPO = Path(__file__).resolve().parents[2]
UUID = 'stockbar@quarkonrails.github.io'
PROBE = 'probe@stockbar.test'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--size', default='1920x1080')
    parser.add_argument('--scale', type=float, default=1)
    parser.add_argument('--rtl', action='store_true')
    parser.add_argument('--inside-session', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('--run-dir', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not args.inside_session:
        import sys
        output = REPO / 'build' / 'headless'
        output.mkdir(parents=True, exist_ok=True)
        run = Path(tempfile.mkdtemp(prefix=f'{args.size}-{args.scale}-', dir=output))
        env = dict(os.environ, XDG_DATA_HOME=str(run / 'data'), XDG_CONFIG_HOME=str(run / 'config'),
                   XDG_CACHE_HOME=str(run / 'cache'), GSETTINGS_BACKEND='keyfile',
                   STOCKBAR_PROBE_DIR=str(run), STOCKBAR_TEST_RTL=str(int(args.rtl)))
        env.pop('DISPLAY', None)
        env.pop('WAYLAND_DISPLAY', None)
        raise SystemExit(subprocess.call(['dbus-run-session', '--', sys.executable, __file__,
                                         *sys.argv[1:], '--inside-session', '--run-dir', str(run)], env=env))

    major = int(subprocess.check_output(['gnome-shell', '--version'], text=True).split()[2].split('.')[0])
    run = Path(args.run_dir)
    data, config, cache = (run / name for name in ('data', 'config', 'cache'))
    ext = data / 'gnome-shell' / 'extensions'
    settings = config / 'glib-2.0' / 'settings'
    settings.mkdir(parents=True)
    (cache / 'stockbar').mkdir(parents=True)
    (ext / PROBE).mkdir(parents=True)
    subprocess.run(['ruby', '-Ilib', '-rstockbar', '-rstockbar/extension', '-e',
                    'Stockbar::Extension.build(ARGV[0], major: Integer(ARGV[1]))',
                    str(ext / UUID), str(major)], cwd=REPO, check=True)
    source = (REPO / 'test/headless/probe.js').read_text()
    if major < 45:
        source = ('const {Clutter, GLib, Gio, Shell, St} = imports.gi;\n'
                  'const Main = imports.ui.main;\n' + source +
                  '\nfunction init() {}\nfunction enable() { enableProbe(); }\n'
                  'function disable() { disableProbe(); }\n')
    else:
        source = ''.join(f"import {name} from 'gi://{name}';\n" for name in
                         ['Clutter', 'GLib', 'Gio', 'Shell', 'St']) + (
            "import * as Main from 'resource:///org/gnome/shell/ui/main.js';\n"
            "import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';\n") + source + (
            '\nexport default class Probe extends Extension {\n'
            'enable() { enableProbe(); }\ndisable() { disableProbe(); }\n}\n')
    (ext / PROBE / 'extension.js').write_text(source)
    (ext / PROBE / 'metadata.json').write_text(json.dumps({
        'uuid': PROBE, 'name': 'Stockbar test probe', 'description': 'Isolated test probe',
        'shell-version': [str(major)],
    }))
    (settings / 'keyfile').write_text(
        f"[org/gnome/shell]\nenabled-extensions=['{PROBE}', '{UUID}']\n"
        f"[org/gnome/desktop/interface]\ntext-scaling-factor={args.scale}\n")
    counter = 0

    def request(action='snapshot', **options):
        nonlocal counter
        counter += 1
        name = f'{counter:02}-{action}'
        pending = run / 'request.tmp'
        pending.write_text(json.dumps(dict(id=name, action=action, quote=quote_id, **options)))
        pending.replace(run / 'request')
        result = run / f'{name}.json'
        deadline = time.monotonic() + 30 + options.get('duration', 0) / 1000
        while not result.exists() and time.monotonic() < deadline:
            if shell.poll() is not None:
                raise RuntimeError(f'Shell exited; see {run / "shell.log"}')
            time.sleep(0.1)
        if not result.exists():
            raise RuntimeError(f'Probe timed out; see {run / "shell.log"}')
        value = json.loads(result.read_text())
        assert 'error' not in value, value
        return value

    quote_id = int(time.time())

    def quotes(count, long=False, speed=None, total=9, price='$231.78', reverse=False):
        nonlocal quote_id
        quote_id += 1
        items = []
        for i in range(total):
            symbol = ['AAPL', 'MSFT', 'NVDA', 'TSLA', 'S&P 500', 'BTC', 'KO', 'SAP', 'EUR/USD'][i]
            text = ('An exceptionally long international stock index name ' * 5) if long and i == 0 else symbol
            items.append(dict(symbol=symbol, display_symbol=symbol, name=symbol, pinned=i < count,
                              direction='up', bar_text=f'{text} ▲ 1.23% {price}', price_text=price,
                              change_text='▲ +2.81 (+1.23%)', stale=False))
        if reverse:
            items.reverse()
        payload = dict(items=items, updated_at_epoch=quote_id, updated_at_text='12:00', refresh_interval=20)
        if speed is not None:
            payload['scroll_speed'] = speed
        pending = cache / 'stockbar/quotes.tmp'
        pending.write_text(json.dumps(payload))
        pending.replace(cache / 'stockbar/quotes.json')
        return quote_id

    def validate(value, clock=None):
        assert value['enabled'], value
        boxes = value['boxes']
        outer_left = boxes['right' if value['rtl'] else 'left']['span']
        outer_right = boxes['left' if value['rtl'] else 'right']['span']
        center = boxes['center']['span']
        left, right = value['halves']
        width = lambda span: span[1] - span[0]
        assert abs(width(left['slot']) - width(right['slot'])) < 1, value
        if value['fit']['shown'] or value['fit']['more']:
            assert center[0] >= outer_left[1] - 1, value
            assert center[1] <= outer_right[0] + 1, value
        else:
            # a crowded tray must not leave stockbar occupying any space
            assert width(left['slot']) == width(right['slot']) == 0, value
        if clock is not None:
            assert abs(sum(value['clock']) / 2 - clock) <= 1, value
        assert left['slot'][1] <= value['clock'][0] + 1, value
        assert right['slot'][0] >= value['clock'][1] - 1, value
        for half in [left, right]:
            positions = [label['span'][0] for label in half['labels']]
            assert positions == sorted(positions), value
        marker = [label for label in right['labels'] if label['text'] == '…']
        assert len(marker) == int(value['fit']['more']), value
        if marker:
            assert right['labels'][-1]['text'] == '…', value

    quotes(0)
    with (run / 'shell.log').open('w') as log:
        shell = subprocess.Popen(['gnome-shell', '--headless', '--wayland', '--no-x11',
                                  '--virtual-monitor', args.size, '--mode=ubuntu',
                                  f'--wayland-display=stockbar-test-{os.getpid()}'], stdout=log,
                                 stderr=subprocess.STDOUT)
        try:
            first = request(screenshot=True)
            validate(first)
            clock = sum(first['clock']) / 2
            for count in [0, 1, 3, 6, 9]:
                expected = quotes(count)
                value = request(screenshot=True)
                assert value['quote'] == expected, value
                validate(value, clock)
                assert value['fit']['shown'] > 0, value
                if count == 0:
                    assert value['halves'][1]['labels'][0]['text'] == 'Stocks', value
                print(f'{args.size} scale={args.scale} rtl={args.rtl}: {count} pinned -> {value["fit"]}', flush=True)

            quotes(9, long=True)
            value = request(screenshot=True)
            validate(value, clock)
            assert any(label['width'] < label['fullWidth'] for half in value['halves']
                       for label in half['labels']), value
            narrowed = request('tray', width=200)
            validate(narrowed, clock)
            restored_long = request('remove-tray')
            assert restored_long['fit'] == value['fit'], (restored_long, value)
            quotes(9)
            before = request()
            for tray_width in [200, 500, 700]:
                value = request('tray', width=tray_width, screenshot=True)
                validate(value, clock)
                assert value['quote'] == before['quote'], value
                assert value['fit']['shown'] <= before['fit']['shown'], value
            restored = request('remove-tray', screenshot=True)
            validate(restored, clock)
            assert restored['fit'] == before['fit'], (restored, before)
            settled = request()
            assert settled['fits'] - restored['fits'] <= 2, (restored, settled)
            larger = request('text-scale', scale=args.scale * 1.5, screenshot=True)
            validate(larger)
            assert larger['quote'] == before['quote'], larger
            assert larger['fit']['shown'] <= before['fit']['shown'], larger
            assert larger['halves'][1]['labels'][0]['fullWidth'] > before['halves'][1]['labels'][0]['fullWidth']
            original_scale = request('text-scale', scale=args.scale)
            validate(original_scale, clock)
            assert original_scale['fit'] == before['fit'], (original_scale, before)
            assert not request('disable')['enabled']
            enabled = request('enable', screenshot=True)
            validate(enabled, clock)
            assert enabled['fit'] == before['fit'], (enabled, before)

            # only pinned stocks scroll, unpinned ones stay in the dropdown
            quotes(6, speed=10)
            scrolling = request(screenshot=True)
            validate(scrolling, clock)
            assert scrolling['scroll']['playing'], scrolling
            assert scrolling['scroll']['width'] == scrolling['room'], scrolling
            assert scrolling['menuRows'] == 9, scrolling
            cycle = request('motion', duration=scrolling['scroll']['length'] / 80 * 1000 + 300)
            seen = {label['symbol'] for sample in cycle['samples'] for view in sample['views']
                    for label in view['labels']}
            assert seen == {'AAPL', 'MSFT', 'NVDA', 'TSLA', 'S&P 500', 'BTC'}, seen
            assert cycle['finalFits'] - cycle['fits'] <= 2, cycle
            for sample in cycle['samples']:
                assert sample['width'] == scrolling['scroll']['width'], sample
                assert all(view['clipped'] for view in sample['views']), sample
            motion = request('motion', duration=1000)
            start, end = motion['samples'][0], motion['samples'][-1]
            distance = (end['position'] - start['position']) % end['length']
            assert abs(distance - 80 * (end['time'] - start['time']) / 1000) < 5, motion
            validate(request(), clock)

            paused = request('menu-open')
            assert not paused['scroll']['playing'], paused
            motion = request('motion', duration=400)
            assert len({sample['position'] for sample in motion['samples']}) == 1, motion
            # cache refresh and a speed change keep the same stock and offset while paused
            quotes(6, speed=5, price='$12,345.67', reverse=True)
            refreshed = request()
            old_anchor, new_anchor = paused['scroll']['anchor'], refreshed['scroll']['anchor']
            assert new_anchor['symbol'] == old_anchor['symbol'], (new_anchor, old_anchor)
            assert abs(new_anchor['offset'] - old_anchor['offset']) < 0.001, (new_anchor, old_anchor)
            assert not refreshed['scroll']['playing'], refreshed
            request('menu-close')
            motion = request('motion', duration=1000)
            start, end = motion['samples'][0], motion['samples'][-1]
            distance = (end['position'] - start['position']) % end['length']
            assert abs(distance - 40 * (end['time'] - start['time']) / 1000) < 5, motion

            crowded = request('tray', width=2000)
            validate(crowded, clock)
            assert not crowded['scroll']['playing'], crowded
            recovered = request('remove-tray')
            validate(recovered, clock)
            assert recovered['scroll']['playing'], recovered
            enlarged = request('text-scale', scale=args.scale * 1.5)
            validate(enlarged)
            assert enlarged['scroll']['length'] > recovered['scroll']['length'], enlarged
            assert enlarged['scroll']['views'][0]['height'] > recovered['scroll']['views'][0]['height'], enlarged
            validate(request('text-scale', scale=args.scale), clock)
            assert not request('disable')['enabled']
            validate(request('enable'), clock)
            # nothing pinned shows the placeholder, even while scrolling is on
            quotes(0, speed=10)
            unpinned = request()
            validate(unpinned, clock)
            assert unpinned['scroll'] is None, unpinned
            assert unpinned['halves'][1]['labels'][0]['text'] == 'Stocks', unpinned
            assert unpinned['menuRows'] == 9, unpinned

            quotes(1, speed=10, total=1)
            single = request(screenshot=True)
            validate(single, clock)
            assert single['scroll']['playing'], single
            # a short loop repeats to fill both views
            assert single['scroll']['width'] == single['room'], single
            assert all(len(view['labels']) >= single['room'] // single['scroll']['length']
                       for view in single['scroll']['views']), single
            quotes(1, long=True, speed=10, total=1)
            long_scroll = request(screenshot=True)
            validate(long_scroll, clock)
            assert long_scroll['scroll']['length'] > 2 * long_scroll['scroll']['width'], long_scroll
            quotes(1, speed=0)
            stopped = request()
            validate(stopped, clock)
            assert stopped['scroll'] is None, stopped
            assert stopped['fit']['shown'] == 1, stopped
            assert stopped['halves'][1]['labels'][0]['text'] == 'AAPL ▲ 1.23% $231.78', stopped
            quotes(0, speed=10, total=0)
            empty = request()
            validate(empty, clock)
            assert empty['scroll'] is None, empty
            print(f'{args.size} scale={args.scale} rtl={args.rtl}: scrolling, pause, recovery and stop passed', flush=True)
            def notice():
                return subprocess.check_output(
                    ['ruby', '-Ilib', '-rstockbar', '-e', 'puts Stockbar::Setup.new.relogin_notice'],
                    cwd=REPO, env=dict(os.environ, XDG_CURRENT_DESKTOP='GNOME'), text=True).strip()

            assert notice() == ''
            installed = ext / UUID
            stylesheet = installed / 'stylesheet.css'
            stylesheet.write_text(stylesheet.read_text() + '\n')
            metadata_path = installed / 'metadata.json'
            metadata = json.loads(metadata_path.read_text())
            metadata['stockbar-fingerprint'] = hashlib.sha256(
                (installed / 'extension.js').read_bytes() + b'\0' + stylesheet.read_bytes()).hexdigest()
            metadata_path.write_text(json.dumps(metadata))
            assert 'extension has been updated' in notice()
            shell.terminate()
            shell.wait(timeout=10)
            shell = subprocess.Popen(shell.args, stdout=log, stderr=subprocess.STDOUT)
            validate(request())
            assert notice() == ''
            print('Extension update notice cleared after a fresh Shell session', flush=True)
        finally:
            shell.terminate()
            try:
                shell.wait(timeout=10)
            except subprocess.TimeoutExpired:
                shell.kill()
                shell.wait()
    print(f'Passed on GNOME {major}. Geometry, screenshots and Shell log: {run}', flush=True)


if __name__ == '__main__':
    main()
