import base64
import hashlib
import hmac
import json
import struct
import time
import urllib.error
import urllib.request
import uuid

BASE_URL = "http://127.0.0.1:3001"
PASSWORD = "Crystell-Test-Password-2026!"
UNIQUE = uuid.uuid4().hex[:12]
EMAIL = f"ci-{UNIQUE}@example.test"


def request(method, path, payload=None, token=None, expected=200, extra_headers=None):
    data = None
    headers = {"Content-Type": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if extra_headers:
        headers.update(extra_headers)

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


def totp(secret, timestamp=None):
    timestamp = int(timestamp or time.time())
    counter = timestamp // 30
    padding = "=" * ((8 - len(secret) % 8) % 8)
    key = base64.b32decode(secret + padding, casefold=True)
    digest = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    value = struct.unpack(">I", digest[offset : offset + 4])[0] & 0x7FFFFFFF
    return f"{value % 1_000_000:06d}"


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
tenant_id = registration["tenant_id"]
store_id = registration["store_id"]

me = request("GET", "/v1/me", token=registration_token, expected=200)
assert me["email"] == EMAIL

stores = request(
    "GET",
    "/v1/stores",
    token=registration_token,
    extra_headers={"X-Crystell-Tenant": tenant_id},
    expected=200,
)
assert stores["tenant_id"] == tenant_id
assert stores["role"] == "owner"
assert [store["id"] for store in stores["stores"]] == [store_id]

request(
    "GET",
    "/v1/stores",
    token=registration_token,
    extra_headers={"X-Crystell-Tenant": str(uuid.uuid4())},
    expected=403,
)
request("GET", "/v1/stores", token=registration_token, expected=403)

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

mfa_setup = request("POST", "/v1/auth/mfa/setup", token=login_token, expected=201)
secret = mfa_setup["secret"]
confirmation = request(
    "POST",
    "/v1/auth/mfa/confirm",
    {"code": totp(secret)},
    token=login_token,
    expected=200,
)
recovery_codes = confirmation["recovery_codes"]
assert len(recovery_codes) == 10

request("DELETE", "/v1/auth/session", token=login_token, expected=204)

mfa_login = request(
    "POST",
    "/v1/auth/session",
    {"email": EMAIL, "password": PASSWORD},
    expected=428,
)
assert mfa_login["error"] == "mfa_required"
challenge_token = mfa_login["challenge_token"]

mfa_session = request(
    "POST",
    "/v1/auth/mfa/challenge",
    {
        "challenge_token": challenge_token,
        "recovery_code": recovery_codes[0],
    },
    expected=201,
)
mfa_session_token = mfa_session["token"]
request("GET", "/v1/me", token=mfa_session_token, expected=200)
request("DELETE", "/v1/auth/session", token=mfa_session_token, expected=204)

second_mfa_login = request(
    "POST",
    "/v1/auth/session",
    {"email": EMAIL, "password": PASSWORD},
    expected=428,
)
second_challenge = second_mfa_login["challenge_token"]
request(
    "POST",
    "/v1/auth/mfa/challenge",
    {
        "challenge_token": second_challenge,
        "recovery_code": recovery_codes[0],
    },
    expected=401,
)
second_session = request(
    "POST",
    "/v1/auth/mfa/challenge",
    {
        "challenge_token": second_challenge,
        "recovery_code": recovery_codes[1],
    },
    expected=201,
)
second_token = second_session["token"]
request("GET", "/v1/me", token=second_token, expected=200)

third_mfa_login = request(
    "POST",
    "/v1/auth/session",
    {"email": EMAIL, "password": PASSWORD},
    expected=428,
)
third_session = request(
    "POST",
    "/v1/auth/mfa/challenge",
    {
        "challenge_token": third_mfa_login["challenge_token"],
        "recovery_code": recovery_codes[2],
    },
    expected=201,
)
third_token = third_session["token"]

active_sessions = request(
    "GET",
    "/v1/security/sessions",
    token=third_token,
    expected=200,
)["sessions"]
assert len(active_sessions) >= 2
assert sum(1 for session in active_sessions if session["current"]) == 1

request(
    "DELETE",
    "/v1/security/sessions/others",
    token=third_token,
    expected=204,
)
request("GET", "/v1/me", token=second_token, expected=401)
request("GET", "/v1/me", token=third_token, expected=200)

throttle_email = f"missing-{UNIQUE}@example.test"
for _ in range(8):
    request(
        "POST",
        "/v1/auth/session",
        {"email": throttle_email, "password": "Definitely-Wrong-Password"},
        expected=401,
    )
request(
    "POST",
    "/v1/auth/session",
    {"email": throttle_email, "password": "Definitely-Wrong-Password"},
    expected=429,
)

print("Identity, tenant isolation, throttling, MFA and session management smoke test passed")
