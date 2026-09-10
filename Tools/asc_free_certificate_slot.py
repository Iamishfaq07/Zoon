#!/usr/bin/env python3
"""Free ONE Apple signing-certificate slot so CI can mint a new one.

Every TestFlight run that cannot import a cached identity has to create a
certificate. The private key lives only on that runner. Once the runner is
gone the certificate is still counted against the account's cap and the next
Archive dies with "Choose a certificate to revoke."

This talks to App Store Connect with the same API key Archive already uses.
It is deliberately conservative:

* It is a DRY RUN unless ``--revoke`` is passed. The default output is a
  table of the certificates it looked at and what it *would* do.
* It only touches distribution certificates (``DISTRIBUTION`` and the legacy
  ``IOS_DISTRIBUTION``) unless ``--type`` says otherwise. A TestFlight archive
  needs a distribution certificate; Apple Development certificates belong to
  individual developers' Macs and are never touched by default.
* It only revokes when the slot family is actually at its cap. With
  ``--max-per-type N`` (default 2, Apple's distribution cap) it revokes the
  OLDEST certificates until ``N - 1`` remain, so that exactly one slot is
  free for the certificate Archive is about to mint. It never wipes a type.

Already-installed TestFlight builds keep working -- Apple does not pull a
build because the certificate that signed it was later revoked.
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

# Apple counts the modern "Apple Distribution" type and the legacy
# "iOS Distribution" type against the same cap, and likewise the two
# development types, so the cap is applied per *family*, not per raw type.
# Developer ID, Pass Type, Mac Installer etc. are never candidates.
FAMILIES: dict[str, frozenset[str]] = {
    "DISTRIBUTION": frozenset({"DISTRIBUTION", "IOS_DISTRIBUTION"}),
    "DEVELOPMENT": frozenset({"DEVELOPMENT", "IOS_DEVELOPMENT"}),
}
DEFAULT_FAMILIES = ("DISTRIBUTION",)
DEFAULT_MAX_PER_TYPE = 2
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



def describe(cert: dict) -> str:
    """One line per certificate: name, type, expiry, serial.

    The certificates resource does not expose a creation date; Apple signing
    certificates are valid for one year, so expiry order *is* creation order
    and the expiry date is what is shown.
    """
    attrs = cert.get("attributes") or {}
    return (
        f"{attrs.get('certificateType')}  "
        f"name={attrs.get('name') or attrs.get('displayName') or '?'}  "
        f"expires={attrs.get('expirationDate') or '?'}  "
        f"serial={attrs.get('serialNumber') or '?'}  "
        f"id={cert.get('id')}"
    )


def plan_revocations(
    certs: list[dict],
    families: tuple[str, ...] = DEFAULT_FAMILIES,
    max_per_type: int = DEFAULT_MAX_PER_TYPE,
) -> dict[str, tuple[list[dict], list[dict]]]:
    """Decide, per family, which certificates to revoke and which to keep.

    Returns ``{family: (revoke, keep)}``. ``revoke`` is the oldest
    certificates (earliest expiry) beyond ``max_per_type - 1``, so that after
    revocation exactly one slot is free. Nothing is revoked when the family
    already has a free slot, and a family is never emptied unless
    ``max_per_type`` is 1.
    """
    if max_per_type < 1:
        raise ValueError("--max-per-type must be at least 1")
    plan: dict[str, tuple[list[dict], list[dict]]] = {}
    for family in families:
        types = FAMILIES[family]
        members = [
            c for c in certs
            if (c.get("attributes") or {}).get("certificateType") in types
        ]
        members.sort(key=lambda c: (
            (c.get("attributes") or {}).get("expirationDate") or "",
            c.get("id") or "",
        ))
        excess = max(0, len(members) - (max_per_type - 1))
        plan[family] = (members[:excess], members[excess:])
    return plan


def revoke(token: str, cert: dict, dry_run: bool) -> bool:
    label = describe(cert)
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


def run(
    key_path: str,
    key_id: str,
    issuer_id: str,
    dry_run: bool,
    families: tuple[str, ...],
    max_per_type: int,
) -> int:
    if not os.path.isfile(key_path):
        raise SystemExit(f"API key not found at {key_path}")
    token = make_token(key_path, key_id, issuer_id)
    certs = list_certificates(token)
    plan = plan_revocations(certs, families, max_per_type)
    considered = sum(len(r) + len(k) for r, k in plan.values())
    mode = "DRY RUN (pass --revoke to delete)" if dry_run else "LIVE -- revoking"
    print(
        f"{mode}. Account has {len(certs)} certificates; {considered} are in the "
        f"selected famil{'y' if len(families) == 1 else 'ies'} "
        f"({', '.join(families)}); {len(certs) - considered} of other types left alone. "
        f"Cap per family: {max_per_type}."
    )
    targets: list[dict] = []
    for family, (to_revoke, to_keep) in plan.items():
        total = len(to_revoke) + len(to_keep)
        print(f"\n{family}: {total} certificate(s), {len(to_revoke)} to revoke, {len(to_keep)} kept")
        for cert in to_keep:
            print(f"  keep    {describe(cert)}")
        for cert in to_revoke:
            print(f"  REVOKE  {describe(cert)}")
        targets.extend(to_revoke)
    print()
    if not targets:
        print(
            "nothing to revoke -- every selected family already has a free slot, "
            "so Archive can mint into it (or is failing for a different reason)."
        )
        return 0
    failed = 0
    for cert in targets:
        if not revoke(token, cert, dry_run):
            failed += 1
    if failed:
        print(f"::error::{failed} certificate(s) could not be revoked")
        return 1
    return 0


def _cert(cert_id: str, cert_type: str, expires: str) -> dict:
    return {
        "id": cert_id,
        "attributes": {
            "certificateType": cert_type,
            "name": f"cert {cert_id}",
            "expirationDate": expires,
            "serialNumber": f"SERIAL{cert_id}",
        },
    }


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

    # --- revocation planning -------------------------------------------
    def ids(certs: list[dict]) -> list[str]:
        return [c["id"] for c in certs]

    dev_old = _cert("d1", "DEVELOPMENT", "2026-01-01T00:00:00.000+00:00")
    dev_new = _cert("d2", "IOS_DEVELOPMENT", "2027-01-01T00:00:00.000+00:00")
    dist_a = _cert("a", "DISTRIBUTION", "2026-10-01T00:00:00.000+00:00")
    dist_b = _cert("b", "IOS_DISTRIBUTION", "2027-03-01T00:00:00.000+00:00")
    dist_c = _cert("c", "DISTRIBUTION", "2027-06-01T00:00:00.000+00:00")
    dev_id = _cert("x", "DEVELOPER_ID_APPLICATION", "2025-01-01T00:00:00.000+00:00")

    # Empty account: nothing to do.
    assert plan_revocations([]) == {"DISTRIBUTION": ([], [])}

    # One distribution cert with cap 2: a slot is already free, keep it.
    revoke_, keep = plan_revocations([dist_a, dev_old])["DISTRIBUTION"]
    assert ids(revoke_) == [] and ids(keep) == ["a"], (ids(revoke_), ids(keep))

    # At the cap (2 of 2): revoke exactly the OLDEST one, keep the newest.
    revoke_, keep = plan_revocations([dist_b, dist_a, dev_old, dev_new])["DISTRIBUTION"]
    assert ids(revoke_) == ["a"] and ids(keep) == ["b"], (ids(revoke_), ids(keep))

    # Over the cap (3 with cap 2): revoke the two oldest, leave N-1 = 1 so
    # one new certificate fits. Never empties the family.
    revoke_, keep = plan_revocations([dist_c, dist_a, dist_b])["DISTRIBUTION"]
    assert ids(revoke_) == ["a", "b"] and ids(keep) == ["c"], (ids(revoke_), ids(keep))

    # Legacy IOS_DISTRIBUTION counts toward the same family cap.
    revoke_, keep = plan_revocations([dist_b, dist_a])["DISTRIBUTION"]
    assert ids(revoke_) == ["a"], ids(revoke_)

    # A larger cap leaves more room: 3 certs with cap 4 is not full.
    revoke_, _ = plan_revocations([dist_a, dist_b, dist_c], max_per_type=4)["DISTRIBUTION"]
    assert ids(revoke_) == [], ids(revoke_)

    # Development certificates are never in the default plan at all ...
    plan = plan_revocations([dev_old, dev_new, dist_a, dist_b])
    assert list(plan) == ["DISTRIBUTION"], list(plan)
    assert "d1" not in ids(plan["DISTRIBUTION"][0]) and "d1" not in ids(plan["DISTRIBUTION"][1])

    # ... and only when asked for explicitly, with the same one-slot rule.
    plan = plan_revocations([dev_old, dev_new, dist_a], families=("DISTRIBUTION", "DEVELOPMENT"))
    assert ids(plan["DEVELOPMENT"][0]) == ["d1"] and ids(plan["DEVELOPMENT"][1]) == ["d2"], plan
    assert ids(plan["DISTRIBUTION"][0]) == [], plan

    # Types outside both families are never candidates, whatever is asked.
    plan = plan_revocations([dev_id, dev_id, dev_id], families=("DISTRIBUTION", "DEVELOPMENT"))
    assert all(r == [] and k == [] for r, k in plan.values()), plan

    # Nonsense cap is refused rather than silently emptying a family.
    try:
        plan_revocations([dist_a], max_per_type=0)
    except ValueError:
        pass
    else:
        raise AssertionError("max_per_type 0 should fail")

    # The CLI defaults to a dry run and refuses contradictory flags.
    args = _parse([])
    assert not args.revoke and args.max_per_type == DEFAULT_MAX_PER_TYPE
    assert _families(args) == DEFAULT_FAMILIES, _families(args)
    args = _parse(["--type", "distribution", "--type", "development"])
    assert _families(args) == ("DISTRIBUTION", "DEVELOPMENT"), _families(args)

    print("self-test passed")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument(
        "--revoke",
        action="store_true",
        help="Actually delete certificates. Without this flag the script only reports.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report only (the default; kept for callers that spell it out).",
    )
    parser.add_argument(
        "--type",
        dest="types",
        action="append",
        choices=sorted(f.lower() for f in FAMILIES),
        help=(
            "Certificate family to manage. Repeatable. Default: distribution only. "
            "'distribution' covers DISTRIBUTION and IOS_DISTRIBUTION; "
            "'development' covers DEVELOPMENT and IOS_DEVELOPMENT."
        ),
    )
    parser.add_argument(
        "--max-per-type",
        type=int,
        default=DEFAULT_MAX_PER_TYPE,
        help=(
            "Apple's cap for the family. Revoke the oldest certificates until "
            f"one fewer than this remain (default {DEFAULT_MAX_PER_TYPE})."
        ),
    )
    parser.add_argument("--key-path")
    parser.add_argument("--key-id")
    parser.add_argument("--issuer-id")
    return parser


def _parse(argv: list[str]) -> argparse.Namespace:
    return _parser().parse_args(argv)


def _families(args: argparse.Namespace) -> tuple[str, ...]:
    if not args.types:
        return DEFAULT_FAMILIES
    seen: list[str] = []
    for family in (t.upper() for t in args.types):
        if family not in seen:
            seen.append(family)
    return tuple(seen)


def main(argv: list[str] | None = None) -> int:
    parser = _parser()
    args = parser.parse_args(argv)
    if args.self_test:
        self_test()
        return 0
    if args.revoke and args.dry_run:
        parser.error("--revoke and --dry-run contradict each other")
    if args.max_per_type < 1:
        parser.error("--max-per-type must be at least 1")
    missing = [name for name in ("key_path", "key_id", "issuer_id") if not getattr(args, name)]
    if missing:
        parser.error("live run requires --key-path, --key-id and --issuer-id")
    return run(
        args.key_path,
        args.key_id,
        args.issuer_id,
        dry_run=not args.revoke,
        families=_families(args),
        max_per_type=args.max_per_type,
    )


if __name__ == "__main__":
    sys.exit(main())
