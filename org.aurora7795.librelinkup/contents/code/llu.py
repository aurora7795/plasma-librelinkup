#!/usr/bin/env python3
"""LibreLinkUp fetcher for the Plasma widget.

Reads the email from ~/.config/librelinkup-plasma/config.json and the password
from the system keyring (Secret Service, via `secret-tool`; KWallet provides
this on Plasma), falling back to a mode-600 password field in config.json when
no keyring is available. Caches the session token in
~/.cache/librelinkup-plasma/session.json and prints one JSON object to stdout.
Uses the unofficial LibreView follower API (can change without notice).

  llu.py            fetch the latest reading
  llu.py --signin   ask for email and password with kdialog, save, then fetch

Credentials are never taken from the command line or the environment: the
widget has no way to hand them over without exposing them in the process
list, so sign-in happens inside this helper.
"""
import calendar, hashlib, json, os, subprocess, sys, time, urllib.request, urllib.error

CONFIG = os.path.expanduser("~/.config/librelinkup-plasma/config.json")
CACHE = os.path.expanduser("~/.cache/librelinkup-plasma/session.json")
HEADERS = {
    "Content-Type": "application/json",
    "Accept": "application/json",
    "product": "llu.android",
    "version": "4.16.0",
    "User-Agent": "Mozilla/5.0",
    "cache-control": "no-cache",
}


class Err(Exception):
    pass


def out(obj):
    print(json.dumps(obj))
    sys.exit(0)


def read_config():
    try:
        with open(CONFIG) as f:
            c = json.load(f)
        return c if isinstance(c, dict) else {}
    except Exception:
        return {}


def write_config(cfg):
    os.makedirs(os.path.dirname(CONFIG), mode=0o700, exist_ok=True)
    fd = os.open(CONFIG, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(cfg, f, indent=2)


# --- password storage: system keyring first, mode-600 file as the fallback ---
KR_ATTRS = ["service", "plasma-librelinkup"]


def kr_store(password):
    try:
        r = subprocess.run(["secret-tool", "store", "--label=LibreLinkUp (Plasma widget)"] + KR_ATTRS,
                           input=password.encode(), capture_output=True, timeout=30)
        return r.returncode == 0
    except Exception:
        return False


def kr_lookup():
    try:
        r = subprocess.run(["secret-tool", "lookup"] + KR_ATTRS, capture_output=True, timeout=30)
        return r.stdout.decode() if r.returncode == 0 else ""
    except Exception:
        return ""


def migrate_password(cfg):
    """Move a plaintext password from config.json into the keyring, but only
    after reading it back successfully, so a failed store never loses it."""
    pw = cfg.get("password")
    if pw and kr_store(pw) and kr_lookup() == pw:
        del cfg["password"]
        write_config(cfg)


def request(host, path, body=None, token=None, account=None):
    h = dict(HEADERS)
    if token:
        h["Authorization"] = "Bearer " + token
    if account:
        h["account-id"] = account
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request("https://%s%s" % (host, path), data=data, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        if e.code == 401:
            raise Err("auth")
        if e.code == 430 or e.code == 429:
            raise Err("rate limited by LibreView, try again later")
        raise Err("HTTP %d" % e.code)
    except (urllib.error.URLError, TimeoutError, OSError):
        raise Err("network")


def load_cache():
    try:
        with open(CACHE) as f:
            c = json.load(f)
        if c.get("expires", 0) > time.time() + 300:
            return c
    except Exception:
        pass
    return None


def save_cache(c):
    os.makedirs(os.path.dirname(CACHE), mode=0o700, exist_ok=True)
    fd = os.open(CACHE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(c, f)


def login(cfg):
    host = cfg.get("host") or "api.libreview.io"
    password = cfg.get("password") or kr_lookup()
    if not password:
        raise Err("login failed: no saved password (keyring locked or empty), sign in again")
    body = {"email": cfg["email"], "password": password}
    for _ in range(3):
        r = request(host, "/llu/auth/login", body)
        data = r.get("data") or {}
        if data.get("redirect") and data.get("region"):
            host = "api-%s.libreview.io" % data["region"]
            continue
        if r.get("status") == 2 or "authTicket" not in data:
            if (data.get("step") or {}).get("type"):
                raise Err("accept the new terms in the LibreLinkUp phone app")
            raise Err("login failed: check your email and password")
        tok = data["authTicket"]["token"]
        uid = data["user"]["id"]
        c = {
            "host": host,
            "token": tok,
            "account": hashlib.sha256(uid.encode()).hexdigest(),
            "expires": data["authTicket"].get("expires", time.time() + 3600),
        }
        save_cache(c)
        return c
    raise Err("too many region redirects")


def parse_ts(s):
    # LibreView timestamps are "M/D/YYYY h:mm:ss AM" in UTC (FactoryTimestamp).
    try:
        return calendar.timegm(time.strptime(s, "%m/%d/%Y %I:%M:%S %p"))
    except Exception:
        return 0


def fetch(sess, cfg):
    h, t, a = sess["host"], sess["token"], sess["account"]
    conns = request(h, "/llu/connections", token=t, account=a).get("data") or []
    if not conns:
        raise Err("no LibreLinkUp connections: share from the Libre app first")
    want = cfg.get("patient")
    conn = next((c for c in conns if c["patientId"] == want), conns[0]) if want else conns[0]
    graph = request(h, "/llu/connections/%s/graph" % conn["patientId"], token=t, account=a)
    gd = (graph.get("data") or {})
    cur = gd.get("connection", conn).get("glucoseMeasurement") or conn.get("glucoseMeasurement")
    if not cur:
        raise Err("no reading yet")
    pts = []
    for p in gd.get("graphData") or []:
        pts.append({"t": parse_ts(p.get("FactoryTimestamp", "")), "mgdl": p.get("ValueInMgPerDl")})
    pts.append({"t": parse_ts(cur.get("FactoryTimestamp", "")), "mgdl": cur.get("ValueInMgPerDl")})
    pts = [p for p in pts if p["mgdl"]]
    tgt = gd.get("connection", conn)
    return {
        "ok": True,
        "storage": "file" if cfg.get("password") else "keyring",
        "mgdl": cur.get("ValueInMgPerDl"),
        "trend": cur.get("TrendArrow", 3),
        "t": parse_ts(cur.get("FactoryTimestamp", "")),
        "isHigh": bool(cur.get("isHigh")),
        "isLow": bool(cur.get("isLow")),
        "targetLow": tgt.get("targetLow", 70),
        "targetHigh": tgt.get("targetHigh", 180),
        "history": pts,
        "fetched": int(time.time()),
    }


def kdialog(*args):
    """Run kdialog and return its stdout, or None if cancelled."""
    try:
        r = subprocess.run(["kdialog", "--title", "LibreLinkUp"] + list(args),
                           capture_output=True, timeout=600)
    except FileNotFoundError:
        out({"ok": False, "error": "sign-in needs kdialog: install the kdialog package"})
    except subprocess.TimeoutExpired:
        return None
    if r.returncode != 0:
        return None
    return r.stdout.decode().rstrip("\n")


def signin():
    cfg = read_config()
    email = kdialog("--inputbox",
                    "LibreLinkUp follower email\n(the account the Libre app shares with, "
                    "not the sensor owner's login)", cfg.get("email", ""))
    if email is None:
        out({"ok": False, "cancelled": True})
    email = email.strip()
    password = kdialog("--password", "LibreLinkUp password for %s" % email) if email else None
    if password is None:
        out({"ok": False, "cancelled": True})
    if not email or not password:
        out({"ok": False, "setup": True, "error": "enter both email and password"})
    cfg["email"] = email
    if kr_store(password):
        cfg.pop("password", None)
    else:
        cfg["password"] = password  # no keyring available: mode-600 file fallback
    write_config(cfg)
    try:
        os.remove(CACHE)
    except FileNotFoundError:
        pass


def main():
    if "--signin" in sys.argv:
        signin()
    cfg = read_config()
    if not cfg.get("email"):
        out({"ok": False, "setup": True, "error": "Sign in with your LibreLinkUp follower account"})
    migrate_password(cfg)
    try:
        sess = load_cache() or login(cfg)
        try:
            out(fetch(sess, cfg))
        except Err as e:
            if str(e) != "auth":
                raise
            out(fetch(login(cfg), cfg))
    except Err as e:
        out({"ok": False, "setup": str(e).startswith("login failed"), "error": str(e)})
    except Exception as e:
        out({"ok": False, "error": "unexpected: %s" % type(e).__name__})


main()
