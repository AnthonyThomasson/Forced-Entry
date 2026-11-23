"""A stand-in Von home for the bootstrap and boot-script tests: a real venv (made from the Python running the tests)
with a fake `von-sdk` 1.3.1 installed from a wheel built here, and the weights folder the real one would have.

Not a test module (unittest discovery only loads test*.py). Nothing here touches the network: pip installs the local
wheel with --no-index --no-deps.

What the fake does, so the scripts can be driven end to end:
  von --version                           prints a version line and exits 0
  von serve --host H --port N --device D  writes served.json (its cwd and arguments) into its working directory, then
                                          answers every GET with 200 on H:N until it is ended (SIGTERM, Ctrl+C and Ctrl+Break end it cleanly, with no traceback); `--device crash` exits 7
  hf download REPO --revision R --local-dir DIR
                                          writes the weight files into DIR (what `hf download` would leave there); with
                                          FAKE_HF_FAIL set it fails with exit 1 instead (the network is down)

`von_home()` builds the venv once per test process (a venv is not relocatable: its launchers hold its own path) and
removes it at exit; callers get a `FakeHome` whose pieces they may break and must restore.
"""
from __future__ import annotations

import atexit
import hashlib
import base64
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

from tools.setup import fe_env

ROOT = Path(__file__).resolve().parents[2]
# The one list of weight files, from the manifest (the scripts read it from there too).
WEIGHT_FILES = tuple(fe_env.manifest()["VON_WEIGHT_FILES"].strip().split(","))
WINDOWS = sys.platform == "win32"

SOURCE = '''
import http.server, json, os, signal, sys, threading

def main():
    args = sys.argv[1:]
    if args[:1] == ["--version"]:
        print("von, version fake")
        return 0
    if args[:1] == ["serve"]:
        opts = dict(zip(args[1::2], args[2::2]))
        if opts.get("--device") == "crash":
            return 7
        print("fake von serving on", opts["--host"], opts["--port"], flush=True)
        with open("served.json", "w") as f:
            json.dump({"pid": os.getpid(), "cwd": os.getcwd(), "args": args, "pythonpath": os.environ.get("PYTHONPATH")}, f)
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200); self.send_header("Content-Length", "2"); self.end_headers(); self.wfile.write(b"ok")
            def log_message(self, *a): pass
        class Server(http.server.ThreadingHTTPServer):
            daemon_threads = True
            def process_request_thread(self, request, client_address):
                try:
                    super().process_request_thread(request, client_address)
                except OSError:
                    pass  # a client (or our own shutdown) closed the socket under the handler: not worth a traceback
            def handle_error(self, request, client_address): pass
        server = Server((opts["--host"], int(opts["--port"])), Handler)
        def stop(*_):
            # serve_forever runs in this thread and shutdown() waits for it to return: ask from another one.
            threading.Thread(target=server.shutdown, daemon=True).start()
        for name in ("SIGTERM", "SIGINT", "SIGBREAK"):
            if hasattr(signal, name):
                signal.signal(getattr(signal, name), stop)
        try:
            server.serve_forever()
        finally:
            server.server_close()
        return 0
    return 2

def hf_main():
    args = sys.argv[1:]
    if os.environ.get("FAKE_HF_FAIL"):
        print("fake hf: no network", file=sys.stderr)
        return 1
    target = args[args.index("--local-dir") + 1]
    os.makedirs(target, exist_ok=True)
    for name in %r:
        with open(os.path.join(target, name), "w") as f:
            f.write("fake " + name)
    print("fake hf: downloaded", args[1], "into", target)
    return 0
''' % (WEIGHT_FILES,)


def build_wheel(dest: Path, version: str = "1.3.1") -> Path:
    """A von-sdk wheel that provides the `von` and `hf` commands above."""
    info = f"von_sdk-{version}.dist-info"
    files = {
        "fakevon.py": SOURCE,
        f"{info}/METADATA": f"Metadata-Version: 2.1\nName: von-sdk\nVersion: {version}\n",
        f"{info}/WHEEL": "Wheel-Version: 1.0\nGenerator: fake_von\nRoot-Is-Purelib: true\nTag: py3-none-any\n",
        f"{info}/entry_points.txt": "[console_scripts]\nvon = fakevon:main\nhf = fakevon:hf_main\n",
    }
    record = []
    for name, text in files.items():
        digest = base64.urlsafe_b64encode(hashlib.sha256(text.encode()).digest()).rstrip(b"=").decode()
        record.append(f"{name},sha256={digest},{len(text.encode())}")
    files[f"{info}/RECORD"] = "\n".join(record + [f"{info}/RECORD,,"]) + "\n"
    wheel = dest / f"von_sdk-{version}-py3-none-any.whl"
    with zipfile.ZipFile(wheel, "w") as z:
        for name, text in files.items():
            z.writestr(name, text)
    return wheel


class FakeHome:
    """A per-user root (FORCED_ENTRY_HOME) with <von home>/venv holding the fake von-sdk. The weights are separate:
    `put_weights()` writes them (and the bootstrap's revision marker when `revision` is given), `clear_weights()`
    removes them."""

    def __init__(self, root: Path):
        self.root = root
        self.von_home = root / "von"
        self.venv = self.von_home / "venv"
        self.bin = self.venv / ("Scripts" if WINDOWS else "bin")
        self.python = self.bin / ("python.exe" if WINDOWS else "python")
        self.weights = self.von_home / "checkpoints" / "von-1.2"

    def put_weights(self, revision: str | None = None) -> None:
        self.clear_weights()
        self.weights.mkdir(parents=True)
        for name in WEIGHT_FILES:
            (self.weights / name).write_text("fake " + name)
        if revision:
            (self.weights / ".fe-revision").write_text(revision + "\n")

    def clear_weights(self) -> None:
        shutil.rmtree(self.von_home / "checkpoints", ignore_errors=True)

    def site_packages(self) -> Path:
        out = subprocess.run([str(self.python), "-c", "import sysconfig; print(sysconfig.get_paths()['purelib'])"],
                              capture_output=True, text=True, check=True).stdout.strip()
        return Path(out)


_HOME: FakeHome | None = None
_TMP: Path | None = None


def von_home() -> FakeHome:
    """The shared fake home, built on first use. Its weights start absent."""
    global _HOME, _TMP
    if _HOME is None:
        _TMP = Path(tempfile.mkdtemp(prefix="fake_von."))
        atexit.register(shutil.rmtree, _TMP, True)
        home = FakeHome(_TMP / "home")
        home.von_home.mkdir(parents=True)
        env = {k: v for k, v in os.environ.items() if k not in ("PYTHONPATH", "PYTHONHOME", "VIRTUAL_ENV")}
        subprocess.run([sys.executable, "-m", "venv", str(home.venv)], check=True, env=env, capture_output=True)
        wheel = build_wheel(_TMP)
        subprocess.run([str(home.python), "-m", "pip", "install", "--no-index", "--no-deps", "--disable-pip-version-check",
                        str(wheel)], check=True, env=env, capture_output=True)
        _HOME = home
    return _HOME
