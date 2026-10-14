#!/usr/bin/env python3
"""Generates Google Authenticator migration test vectors using protoc.

Encodes real protobuf wire bytes with `protoc --encode`, so the parser is tested
against genuine output rather than hand-assembled data.

Run from the repository root:
    python3 tool/generate_migration_vectors.py
"""

from __future__ import annotations

import base64
import subprocess
import sys
from pathlib import Path

PROTO = Path("proto/otp_migration.proto")
OUT = Path("test/fixtures/migration_vectors.yaml")

# The classic JBSWY3DPEHPK3PXP key, as raw bytes ("Hello!" + DEADBEEF).
SECRET_HEX = "48656c6c6f21deadbeef"


def encode(textproto: str) -> str:
    """Encodes a text-format message to base64 protobuf wire bytes."""
    result = subprocess.run(
        ["protoc", f"--proto_path={PROTO.parent}", "--encode=MigrationPayload",
         str(PROTO)],
        input=textproto.encode(),
        capture_output=True,
        check=True,
    )
    return base64.b64encode(result.stdout).decode()


def params(
    secret_hex: str,
    name: str,
    issuer: str = "",
    algorithm: str = "SHA1",
    digits: str = "SIX",
    otp_type: str = "TOTP",
    counter: int = 0,
) -> str:
    """Builds one OtpParameters entry in protobuf text format."""
    secret = "".join(f"\\x{secret_hex[i:i+2]}" for i in range(0, len(secret_hex), 2))
    lines = [f'  secret: "{secret}"', f'  name: "{name}"']
    if issuer:
        lines.append(f'  issuer: "{issuer}"')
    lines += [
        f"  algorithm: {algorithm}",
        f"  digits: {digits}",
        f"  type: {otp_type}",
    ]
    if counter:
        lines.append(f"  counter: {counter}")
    return "otp_parameters {\n" + "\n".join(lines) + "\n}\n"


def payload(entries: list[str], version: int = 1, batch_size: int = 1,
            batch_index: int = 0, batch_id: int = 1234567890) -> str:
    return (
        "".join(entries)
        + f"version: {version}\n"
        + f"batch_size: {batch_size}\n"
        + f"batch_index: {batch_index}\n"
        + f"batch_id: {batch_id}\n"
    )


CASES: list[tuple[str, str, str]] = [
    (
        "single_totp_sha1",
        "A single SHA1/TOTP/6-digit account — the common case.",
        payload([params(SECRET_HEX, "GitHub:ada@example.com", "GitHub")]),
    ),
    (
        "two_accounts",
        "Two accounts in one payload: SHA1/6-digit and SHA256/8-digit.",
        payload([
            params(SECRET_HEX, "GitHub:ada@example.com", "GitHub"),
            params(SECRET_HEX, "GitLab:grace@example.com", "GitLab",
                   algorithm="SHA256", digits="EIGHT"),
        ], batch_size=2),
    ),
    (
        "hotp_with_counter",
        "A counter-based (HOTP) account carrying a counter.",
        payload([params(SECRET_HEX, "ada", "Bank", otp_type="HOTP", counter=42)]),
    ),
    (
        "sha512_eight_digits",
        "SHA512 with 8 digits.",
        payload([params(SECRET_HEX, "ada", "Acme", algorithm="SHA512",
                       digits="EIGHT")]),
    ),
    (
        "name_only_no_issuer",
        "No issuer field; the name carries 'Issuer:Account'.",
        payload([params(SECRET_HEX, "GitHub:ada@example.com")]),
    ),
    (
        "blank_secret",
        "An entry with an empty secret — must be rejected, not imported blank.",
        payload([params("", "ada", "GitHub")]),
    ),
    (
        "unspecified_enums",
        "An entry whose enums are all UNSPECIFIED — must be rejected.",
        payload([params(SECRET_HEX, "ada", "GitHub",
                       algorithm="ALGORITHM_TYPE_UNSPECIFIED",
                       digits="DIGIT_COUNT_UNSPECIFIED",
                       otp_type="OTP_TYPE_UNSPECIFIED")]),
    ),
    (
        "unknown_algorithm_md5",
        "MD5, which this app does not support — must be rejected per-account.",
        payload([params(SECRET_HEX, "ada", "Legacy", algorithm="MD5")]),
    ),
]

HEADER = """# Test vectors for the Google Authenticator migration parser.
#
# GENERATED FILE — do not edit by hand.
# Regenerate with: python3 tool/generate_migration_vectors.py
#
# Each value is a base64 protobuf MigrationPayload, exactly as Google
# Authenticator embeds it in otpauth-migration://offline?data=<value>.
"""


def main() -> int:
    if subprocess.run(["protoc", "--version"], capture_output=True).returncode:
        print("protoc is required but was not found", file=sys.stderr)
        return 1

    lines = [HEADER]
    for key, description, textproto in CASES:
        encoded = encode(textproto)
        lines.append(f"\n# {description}\n")
        lines.append(f"{key}: >-\n  {encoded}\n")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("".join(lines))
    print(f"wrote {OUT} with {len(CASES)} vectors")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
