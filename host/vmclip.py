#!/usr/bin/env python3
# vmclip.py: share the host clipboard with a QEMU guest.
# The guest reaches it at http://10.0.2.2:8765/ (QEMU user-mode networking).
#   GET  -> returns the host clipboard
#   POST -> sets the host clipboard to the request body
# Needs xclip (X11) or wl-clipboard (Wayland).
import http.server, os, subprocess

WAYLAND = bool(os.environ.get("WAYLAND_DISPLAY"))

def get_clip():
    cmd = ["wl-paste", "--no-newline"] if WAYLAND else ["xclip", "-o", "-selection", "clipboard"]
    return subprocess.run(cmd, capture_output=True).stdout

def set_clip(data):
    cmd = ["wl-copy"] if WAYLAND else ["xclip", "-i", "-selection", "clipboard"]
    subprocess.run(cmd, input=data)

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):                      # guest reads host clipboard
        data = get_clip()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):                     # guest sends text to host clipboard
        n = int(self.headers.get("Content-Length", 0))
        set_clip(self.rfile.read(n))
        self.send_response(204)
        self.end_headers()

    def log_message(self, *args):
        pass

# Loopback only: QEMU user networking still lets the guest in via 10.0.2.2
http.server.ThreadingHTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
