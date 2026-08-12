import json
import urllib.error
import urllib.request
import uuid

BASE_URL = "http://127.0.0.1:3001"
PASSWORD = "Crystell-Test-Password-2026!"
UNIQUE = uuid.uuid4().hex[:12]
EMAIL = f"ci-{UNIQUE}@example.test"


def request(method, path, payload=None, token=None, expected=200):
    data = None
    headers = {"Content-Type": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
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
        "tenant_name": f"CI Tenant {UNIQUE}",
        "tenant_slug": f"ci-tenant-{UNIQUE}",
        "store_name": f"CI Store {UNIQUE}",
        "store_slug": f"ci-store-{UNIQUE}",
    },
    expected=201,
)
registration_token = registration["token"]

me = request("GET", "/v1/me", token=registration_token, expected=200)
assert me["email"] == EMAIL

request("DELETE", "/v1/auth/session", token=registration_token, expected=204)
request("GET", "/v1/me", token=registration_token, expected=401)

login = request(
    "POST",
    "/v1/auth/session",
    {"email": EMAIL, "password": PASSWORD},
    expected=201,
)
login_token = login["token"]
request("GET", "/v1/me", token=login_token, expected=200)

print("Identity smoke test passed")
