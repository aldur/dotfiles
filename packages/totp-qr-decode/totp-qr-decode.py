#!/usr/bin/env python3
"""Decode a TOTP setup QR code into its parameters."""

import argparse
import sys
from urllib.parse import urlparse, parse_qs, unquote


def decode_qr(path: str) -> str:
    import cv2

    img = cv2.imread(path)
    if img is None:
        sys.exit(f"Could not read image: {path}")

    data, _points, _straight = cv2.QRCodeDetector().detectAndDecode(img)
    if not data:
        sys.exit(f"No QR code found in {path}")
    return data


def parse_otpauth(uri: str) -> dict[str, str | None]:
    if not uri.startswith("otpauth://"):
        sys.exit(f"Not an otpauth URI: {uri!r}")

    parsed = urlparse(uri)
    params = {k: v[0] for k, v in parse_qs(parsed.query).items()}

    label = unquote(parsed.path.lstrip("/"))
    issuer_label, sep, account = label.partition(":")
    if not sep:
        account, issuer_label = issuer_label, ""

    return {
        "type": parsed.netloc,  # totp or hotp
        "issuer": params.get("issuer", issuer_label),
        "account": account,
        "secret": params.get("secret"),
        "algorithm": params.get("algorithm", "SHA1"),
        "digits": params.get("digits", "6"),
        "period": params.get("period", "30"),
        "counter": params.get("counter"),  # hotp only
    }


def main() -> None:
    ap = argparse.ArgumentParser(description="Decode a TOTP setup QR code.")
    ap.add_argument("image", help="path to QR code image (png/jpg/etc.)")
    ap.add_argument("--raw", action="store_true", help="print the otpauth URI only")
    args = ap.parse_args()

    uri = decode_qr(args.image)
    if args.raw:
        print(uri)
        return

    info = {k: v for k, v in parse_otpauth(uri).items() if v}
    width = max(map(len, info))
    for k, v in info.items():
        print(f"{k:<{width}}  {v}")
    print(f"\nuri: {uri}")


if __name__ == "__main__":
    main()
