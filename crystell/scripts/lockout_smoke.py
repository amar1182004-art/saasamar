import json
import time
import urllib.error
import urllib.request
import uuid

BASE_URL = "http://127.0.0.1:3001"
PASSWORD = "Crystell-Lockout-Test-2026!"
UNIQUE = uuid.uuid4().hex[:12]
EMAIL = f"lockout-{UNIQUE}@example.test"


def request(method, path, payload=None, token=None, expected=200):
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"

    req = urllib.request.Request(BASE_URL + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            body = response.read().decode("utf-8")
            if response.status != expected:
                raise RuntimeError(f"{method} {path}: expected {expected}, got {response.status}")
            return json.loads(body) if body else None
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8")
        if error.code == expected:
            return json.loads(body) if body else None
        raise RuntimeError(f"{method} {path}: expected {expected}, got {error.code}: {body}") from error


registration = request(
    "POST",
    "/v1/auth/registration",
    {
        "email": EMAIL,
        "password": PASSWORD,
        "tenant_name": f"Lockout Tenant {UNIQUE}",
        "tenant_slug": f"lockout-tenant-{UNIQUE}",
        "store_name": f"Lockout Store {UNIQUE}",
        "store_slug": f"lockout-store-{UNIQUE}",
    },
    expected=201,
)
request("DELETE", "/v1/auth/session", token=registration["token"], expected=204)

for _ in range(5):
    request(
        "POST",
        "/v1/auth/session",
        {"email": EMAIL, "password": "Wrong-Password-For-Lockout!"},
        expected=401,
    )

locked = request(
    "POST",
    "/v1/auth/session",
    {"email": EMAIL, "password": PASSWORD},
    expected=423,
)
assert locked["error"] == "account_locked"

time.sleep(3)

unlocked = request(
    "POST",
    "/v1/auth/session",
    {"email": EMAIL, "password": PASSWORD},
    expected=201,
)
request("GET", "/v1/me", token=unlocked["token"], expected=200)
request("DELETE", "/v1/auth/session", token=unlocked["token"], expected=204)

print("Persistent account lockout smoke test passed")
