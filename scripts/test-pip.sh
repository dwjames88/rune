#!/bin/bash
# Exercises the Picture-in-Picture logic in PageBridge against a stubbed DOM.
#
# The trickiest part of PiP isn't the Swift — it's which <video> gets chosen,
# and whether a player inside an iframe is reachable at all. That's pure
# JavaScript, so it can be tested without a window, a network, or your screen.
#
# Zero dependencies: `jsc` ships with macOS inside JavaScriptCore.framework.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JSC="/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc"
[ -x "$JSC" ] || { echo "jsc not found at $JSC"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Pull the injected script out of PageBridge.swift and fill in the Swift
# interpolations, so the tests run the same source the browser injects.
python3 - "$REPO_ROOT/Sources/Rune/PageBridge.swift" "$WORK/bridge.js" <<'PY'
import re, sys, pathlib
src = pathlib.Path(sys.argv[1]).read_text()
m = re.search(r'private static func source\(hoverDelayMs: Int, hoverEnabled: Bool\) -> String \{ """\n(.*?)\n    """ \}', src, re.S)
if not m:
    sys.exit("could not find the injected script in PageBridge.swift")
js = m.group(1)
js = js.replace('\\(hoverDelayMs)', '450')
js = js.replace('\\(hoverEnabled ? "false" : "true")', 'false')
js = re.sub(r'\\\((.*?)\)', 'null', js)          # any remaining interpolation
pathlib.Path(sys.argv[2]).write_text(js)
PY

cat > "$WORK/test.js" <<'JS'
const SRC = readFile(BRIDGE);

function makeEnv(videos, iframes) {
  iframes = iframes || [];
  const listeners = {};
  const doc = {
    pictureInPictureElement: null,
    pictureInPictureEnabled: false,
    addEventListener: function () {},
    querySelectorAll: function (sel) {
      if (sel === 'video') return videos;
      if (sel === 'iframe') return iframes;
      if (sel === 'video,audio') return videos;
      return [];
    },
  };
  const win = {
    addEventListener: function (t, fn) { listeners[t] = fn; },
    webkit: { messageHandlers: { rune: { postMessage: function () {} } } },
    __listeners: listeners,
  };
  win.document = doc; win.window = win;
  return win;
}

function video(o) {
  const v = {
    paused: false, ended: false, readyState: 4, muted: false, volume: 1,
    webkitPresentationMode: 'inline',
    webkitSupportsPresentationMode: function () { return true; },
    webkitSetPresentationMode: function (m) { this.webkitPresentationMode = m; },
  };
  for (const k in (o || {})) v[k] = o[k];
  return v;
}

function run(win) {
  const fn = new Function('window', 'document', 'setTimeout', 'clearTimeout', SRC);
  fn(win, win.document, function () {}, function () {});
  return win;
}

let pass = 0, fail = 0;
function check(name, got, want) {
  const ok = got === want;
  if (ok) { pass++; print('  ok   ' + name); }
  else { fail++; print('  FAIL ' + name + ' — got ' + JSON.stringify(got) + ', want ' + JSON.stringify(want)); }
}

let w, v;

w = run(makeEnv([]));
check('empty page reports no video', w.__runePiP('enter', true, false), 'no-playing-video');

v = video({}); w = run(makeEnv([v]));
check('a playing, audible video enters', w.__runePiP('enter', true, false), 'webkit');
check('  and it actually moved', v.webkitPresentationMode, 'picture-in-picture');

w = run(makeEnv([video({ muted: true })]));
check('a muted autoplay hero is left alone', w.__runePiP('enter', true, false), 'no-playing-video');

w = run(makeEnv([video({ muted: true })]));
check('unless sound is not required', w.__runePiP('enter', false, false), 'webkit');

w = run(makeEnv([video({ paused: true })]));
check('a paused video is not automatic', w.__runePiP('enter', false, false), 'no-playing-video');

w = run(makeEnv([video({ paused: true })]));
check('but a manual toggle takes it', w.__runePiP('enter', false, true), 'webkit');

w = run(makeEnv([video({ webkitPresentationMode: 'picture-in-picture' })]));
check('never double-enters', w.__runePiP('enter', true, false), 'already-pip');

const hero = video({ muted: true }), real = video({});
w = run(makeEnv([hero, real]));
w.__runePiP('enter', false, false);
check('sound breaks the tie', real.webkitPresentationMode, 'picture-in-picture');
check('  leaving the hero inline', hero.webkitPresentationMode, 'inline');

let posted = null;
const frame = { contentWindow: { postMessage: function (m) { posted = m; } } };
w = run(makeEnv([], [frame]));
check('a player in an iframe is delegated', w.__runePiP('enter', true, false), 'delegated');
check('  by asking the child frame', posted && posted.__rune, 'pip');

v = video({ webkitPresentationMode: 'picture-in-picture' });
w = run(makeEnv([v]));
check('exit returns the video', w.__runePiP('exit', true, false), 'webkit');
check('  to the page', v.webkitPresentationMode, 'inline');

w = run(makeEnv([video({})]));
check('exit with nothing to exit', w.__runePiP('exit', true, false), 'none');

v = video({});
w = run(makeEnv([v]));
w.__listeners['message']({ data: { __rune: 'pip', action: 'enter', audibleOnly: true, anyState: false } });
check('a child frame acts on the broadcast', v.webkitPresentationMode, 'picture-in-picture');

v = video({});
w = run(makeEnv([v]));
w.__listeners['message']({ data: { hello: 'world' } });
check('someone else’s postMessage is ignored', v.webkitPresentationMode, 'inline');

print('');
print(pass + ' passed, ' + fail + ' failed');
if (fail) { throw new Error(fail + ' test(s) failed'); }
JS

echo "› Picture in Picture"
"$JSC" -e "var BRIDGE='$WORK/bridge.js';" -f "$WORK/test.js"
