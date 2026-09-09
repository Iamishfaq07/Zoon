#!/usr/bin/env python3
"""Free an Apple signing-certificate slot so CI can mint a new one.

Every TestFlight run that cannot import a cached identity has to create a
certificate. The private key lives only on that runner. Once the runner is
gone the certificate is still counted against the account's cap -- 3 Apple
Development, 3 Apple Distribution -- and the next Archive dies with
"Choose a certificate to revoke."

This talks to App Store Connect with the same API key Archive already uses
and deletes DEVELOPMENT / DISTRIBUTION certificates. Those private keys are
already gone; the public halves occupying slots are not useful to anyone.
Already-installed TestFlight builds keep working -- Apple does not pull a
build because the cert that signed it was later revoked.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1/certificates"

# Automatic signing for an App Store archive mints Apple Development and/or
# Apple Distribution (and the older iOS-prefixed names on some accounts).
# Developer ID, Pass Type, and Mac Installer certs are not ours to touch.
REVOKE_TYPES = frozenset({
    "DEVELOPMENT",
    "IOS_DEVELOPMENT",
    "DISTRIBUTION",
    "IOS_DISTRIBUTION",
})


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def der_ecdsa_to_jose(der: bytes) -> bytes:
    """Convert OpenSSL's DER ECDSA signature to JWT's raw R||S (P-256)."""
    i = 0

    def fail(msg: str) -> None:
        raise ValueError(f"{msg} at byte {i} of {der.hex()}")

    if i >= len(der) or der[i] != 0x30:
        fail("expected SEQUENCE")
    i += 1
    seq_len = der[i]
    i += 1
    if seq_len & 0x80:
        n = seq_len & 0x7F
        seq_len = int.from_bytes(der[i : i + n], "big")
        i += n
    end = i + seq_len
    if end > len(der):
        fail("SEQUENCE overruns buffer")

    def integer() -> bytes:
        nonlocal i
        if i >= end or der[i] != 0x02:
            fail("expected INTEGER")
        i += 1
        length = der[i]
        i += 1
        if length & 0x80:
            n = length & 0x7F
            length = int.from_bytes(der[i : i + n], "big")
            i += n
        value = der[i : i + length]
        i += length
        if not value:
            fail("empty INTEGER")
        # DER integers are signed; a leading 0x00 is padding when the high bit
        # of R or S is set. Strip it, then left-pad to 32 bytes.
        if value[0] == 0x00:
            value = value[1:]
        if len(value) > 32:
            fail(f"INTEGER longer than P-256 ({len(value)} bytes)")
        return value.rjust(32, b"\x00")

    raw = integer() + integer()
    if i != end:
        fail("trailing bytes in SEQUENCE")
    if end != len(der):
        fail("trailing bytes after SEQUENCE")
    return raw


def make_token(key_path: str, key_id: str, issuer_id: str) -> str:
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    now = int(time.time())
    payload = b64url(
        json.dumps(
            {
                "iss": issuer_id,
                "iat": now,
                "exp": now + 12 * 60,
                "aud": "appstoreconnect-v1",
            }
        ).encode()
    )
    signing_input = f"{header}.{payload}".encode()
    der = subprocess.check_output(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input,
    )
    return f"{header}.{payload}.{b64url(der_ecdsa_to_jose(der))}"


def request(method: str, url: str, token: str) -> tuple[int, object]:
    req = urllib.request.Request(url, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/json")
    try:
        with urllib.request.urlopen(req, context=ssl.create_default_context()) as resp:
            body = resp.read()
            return resp.status, json.loads(body) if body else {}
    except urllib.error.HTTPError as exc:
        body = exc.read()
        try:
            parsed = json.loads(body) if body else {}
        except json.JSONDecodeError:
            parsed = {"raw": body.decode("utf-8", "replace")}
        return exc.code, parsed


def list_certificates(token: str) -> list[dict]:
    certs: list[dict] = []
    url: str | None = API + "?" + urllib.parse.urlencode({"limit": "200"})
    while url:
        status, payload = request("GET", url, token)
        if status != 200:
            raise SystemExit(
                f"Listing certificates failed ({status}): {json.dumps(payload)[:800]}"
            )
        certs.extend(payload.get("data") or [])
        url = (payload.get("links") or {}).get("next")
    return certs


def revoke(token: str, cert: dict, dry_run: bool) -> bool:
    attrs = cert.get("attributes") or {}
    label = (
        f"{attrs.get('certificateType')} "
        f"{attrs.get('name') or attrs.get('displayName') or cert.get('id')} "
        f"exp {attrs.get('expirationDate')}"
    )
    if dry_run:
        print(f"dry-run: would revoke {label}")
        return True
    status, payload = request("DELETE", f"{API}/{cert['id']}", token)
    # 204 no content is the success Apple documents.
    if status in (200, 204):
        print(f"revoked {label}")
        return True
    print(f"failed to revoke {label} ({status}): {json.dumps(payload)[:400]}")
    return False


def run(key_path: str, key_id: str, issuer_id: str, dry_run: bool) -> int:
    if not os.path.isfile(key_path):
        raise SystemExit(f"API key not found at {key_path}")
    token = make_token(key_path, key_id, issuer_id)
    certs = list_certificates(token)
    targets = [
        c
        for c in certs
        if (c.get("attributes") or {}).get("certificateType") in REVOKE_TYPES
    ]
    others = len(certs) - len(targets)
    print(
        f"account has {len(certs)} certificates; "
        f"{len(targets)} are Development/Distribution (will revoke); "
        f"{others} of other types left alone."
    )
    if not targets:
        print("nothing to revoke -- Archive will mint into an empty slot, or fail for a different reason.")
        return 0
    targets.sort(key=lambda c: (c.get("attributes") or {}).get("expirationDate") or "")
    failed = 0
    for cert in targets:
        if not revoke(token, cert, dry_run):
            failed += 1
    if failed:
        print(f"::error::{failed} certificate(s) could not be revoked")
        return 1
    return 0


def self_test() -> None:
    # r = 1, s = 1. Shortest legal P-256 DER.
    short = bytes.fromhex("3006020101020101")
    got = der_ecdsa_to_jose(short)
    assert got == (b"\x00" * 31 + b"\x01") * 2, got.hex()

    # High-bit R (0x80..01) needs a leading 0x00 in DER; S = 2.
    r = b"\x80" + b"\x00" * 30 + b"\x01"
    s = b"\x00" * 31 + b"\x02"
    r_der = b"\x02\x21\x00" + r
    s_der = b"\x02\x01\x02"
    der = b"\x30" + bytes([len(r_der) + len(s_der)]) + r_der + s_der
    got = der_ecdsa_to_jose(der)
    assert got == r + s, got.hex()

    # Trailing junk is rejected.
    try:
        der_ecdsa_to_jose(short + b"\x00")
    except ValueError:
        pass
    else:
        raise AssertionError("trailing bytes should fail")

    print("self-test passed")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--key-path")
    parser.add_argument("--key-id")
    parser.add_argument("--issuer-id")
    args = parser.parse_args(argv)
    if args.self_test:
        self_test()
        return 0
    missing = [name for name in ("key_path", "key_id", "issuer_id") if not getattr(args, name)]
    if missing:
        parser.error("live run requires --key-path, --key-id and --issuer-id")
    return run(args.key_path, args.key_id, args.issuer_id, args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
