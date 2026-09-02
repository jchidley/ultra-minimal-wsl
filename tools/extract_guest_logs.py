#!/usr/bin/env python3
"""Extract GuestLog user data deterministically from tracerpt CSV output."""

from __future__ import annotations

import argparse
import csv
import io
import json
import re
from pathlib import Path


PROVIDER_GUID = re.compile(r"^\{[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\}$")


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
    event_index = headers.index("Event Name")
    user_data_index = headers.index("User Data")
    for values in reader:
        if not values or not any(values):
            continue
        total += 1
        if len(values) <= event_index or values[event_index].strip() != "GuestLog":
            # tracerpt emits provider-specific rows wider than its generic CSV
            # header. They are outside this extractor's GuestLog contract.
            continue
        if len(values) > len(headers) and PROVIDER_GUID.fullmatch(values[-1].strip()):
            # WSL GuestLog rows append their provider GUID after User Data even
            # though tracerpt omits that provider-specific column from the header.
            # tracerpt also fails to quote commas in this payload consistently,
            # so reconstruct only the bounded fields before that terminal GUID.
            payload = ",".join(values[user_data_index:-1]).strip()
            if len(payload) >= 2 and payload.startswith('"') and payload.endswith('"'):
                payload = payload[1:-1]
            records.append(payload.rstrip())
            continue
        if len(values) != len(headers):
            raise ValueError(f"tracerpt CSV row {total + 1} has {len(values)} fields, expected {len(headers)}")
        records.append(values[user_data_index].rstrip())

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
