#!/usr/bin/env python3
"""Extract GuestLog user data deterministically from tracerpt CSV output."""

from __future__ import annotations

import argparse
import csv
import io
import json
from pathlib import Path


def decode_csv(path: Path) -> str:
    data = path.read_bytes()
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        return data.decode("utf-16")
    return data.decode("utf-8-sig")


def extract_guest_logs(csv_path: Path, output_path: Path) -> dict[str, int]:
    reader = csv.reader(io.StringIO(decode_csv(csv_path), newline=""))
    try:
        raw_headers = next(reader)
    except StopIteration as error:
        raise ValueError("tracerpt CSV is empty") from error
    headers = [header.strip() for header in raw_headers]
    if not headers or any(not header for header in headers) or len(headers) != len(set(headers)):
        raise ValueError("tracerpt CSV has missing or duplicate normalized headers")
    required = {"Event Name", "User Data"}
    missing = required - set(headers)
    if missing:
        raise ValueError(f"tracerpt CSV lacks required headers: {sorted(missing)}")

    total = 0
    records: list[str] = []
    for values in reader:
        if not values or not any(values):
            continue
        total += 1
        if len(values) != len(headers):
            raise ValueError(f"tracerpt CSV row {total + 1} has {len(values)} fields, expected {len(headers)}")
        row = dict(zip(headers, values))
        if row["Event Name"].strip() == "GuestLog":
            records.append(row["User Data"].rstrip())

    if not records:
        raise ValueError("tracerpt CSV contains no GuestLog records")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("".join(f"{record}\n" for record in records), encoding="utf-8", newline="")
    return {"rows": total, "guestLogRecords": len(records)}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--csv", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        result = extract_guest_logs(Path(args.csv), Path(args.output))
    except (OSError, UnicodeError, csv.Error, ValueError) as error:
        raise SystemExit(f"GuestLog extraction failed: {error}") from error
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
