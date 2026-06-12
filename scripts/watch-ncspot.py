#!/usr/bin/env python3
"""Print ncspot playback mode/title changes as they happen (read-only).
Used to confirm, via the socket, when a media-key press reaches ncspot."""
import socket, time, json

PATH = "/tmp/ncspot-501/ncspot.sock"

def ts() -> str:
    return time.strftime("%H:%M:%S")

while True:
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(PATH)
    except Exception as e:
        print(f"{ts()} (no socket: {e})", flush=True)
        time.sleep(1.5)
        continue
    print(f"{ts()} connected — watching for changes…", flush=True)
    s.settimeout(120)
    buf, last = b"", None
    try:
        while True:
            chunk = s.recv(8192)
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                if not line.strip():
                    continue
                try:
                    obj = json.loads(line)
                    m = obj.get("mode")
                    mode = list(m.keys())[0] if isinstance(m, dict) else m
                    title = (obj.get("playable") or {}).get("title", "")
                    tag = f"{mode} | {title}"
                    if tag != last:
                        print(f"{ts()} {tag}", flush=True)
                        last = tag
                except Exception as ex:
                    print(f"{ts()} parse error: {ex}", flush=True)
    except Exception as e:
        print(f"{ts()} recv ended: {e}", flush=True)
    s.close()
