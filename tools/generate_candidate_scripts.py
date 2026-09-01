#!/usr/bin/env python3
"""Generate the three candidate-specific PowerShell scripts from a checked delta."""

from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).parents[1]
TOKEN_MARKERS = ("{{", "@@SUBSTITUTE@@")


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def resolve(value: str) -> Path:
    expanded = os.path.expandvars(value.replace("%LOCALAPPDATA%", os.environ.get("LOCALAPPDATA", "%LOCALAPPDATA%")))
    path = Path(expanded)
    return path if path.is_absolute() else ROOT / path


def render_text(source: str, substitutions: list[dict]) -> str:
    if not substitutions:
        raise ValueError("at least one substitution is required")
    old_values = [item.get("old") for item in substitutions]
    if None in old_values or len(old_values) != len(set(old_values)):
        raise ValueError("missing or duplicate substitution source")

    spans: list[tuple[int, int, str]] = []
    for item in substitutions:
        if set(item) != {"old", "new"} or not item["old"] or item["old"] == item["new"]:
            raise ValueError("each substitution must contain one distinct old/new pair")
        positions: list[int] = []
        start = 0
        while True:
            found = source.find(item["old"], start)
            if found < 0:
                break
            positions.append(found)
            start = found + 1
        if len(positions) != 1:
            raise ValueError(f"substitution source occurs {len(positions)} times: {item['old']!r}")
        spans.append((positions[0], positions[0] + len(item["old"]), item["new"]))

    spans.sort()
    for previous, current in zip(spans, spans[1:]):
        if current[0] < previous[1]:
            raise ValueError("substitution spans overlap")
    rendered = source
    for start, end, replacement in reversed(spans):
        rendered = rendered[:start] + replacement + rendered[end:]
    unresolved = [marker for marker in TOKEN_MARKERS if marker in rendered]
    if unresolved:
        raise ValueError(f"unresolved substitution marker(s): {unresolved}")
    return rendered


def render_file(spec: dict) -> tuple[Path, str, str]:
    required = {"name", "source", "output", "source_sha256", "output_sha256", "substitutions"}
    if set(spec) != required:
        raise ValueError(f"file specification fields differ: missing={sorted(required-set(spec))}, extra={sorted(set(spec)-required)}")
    source_path, output_path = resolve(spec["source"]), resolve(spec["output"])
    source_bytes = source_path.read_bytes()
    if digest(source_bytes) != spec["source_sha256"]:
        raise ValueError(f"source identity mismatch: {source_path}")
    source = source_bytes.decode("utf-8")
    rendered = render_text(source, spec["substitutions"])
    rendered_bytes = rendered.encode("utf-8")
    if digest(rendered_bytes) != spec["output_sha256"]:
        raise ValueError(f"unexpected generated output: {output_path}")
    delta = "".join(difflib.unified_diff(
        source.splitlines(keepends=True), rendered.splitlines(keepends=True),
        fromfile=str(source_path), tofile=str(output_path),
    ))
    if not delta:
        raise ValueError(f"generated delta is empty: {spec['name']}")
    return output_path, rendered, delta


def generate(delta_path: Path, *, write: bool) -> str:
    record = json.loads(delta_path.read_text(encoding="utf-8"))
    if set(record) != {"schema", "generator", "files"} or record["schema"] != 1 or record["generator"] != "candidate-powershell-v1":
        raise ValueError("unsupported candidate generation delta")
    if len(record["files"]) != 3 or {item.get("name") for item in record["files"]} != {"build", "runner", "controller"}:
        raise ValueError("delta must define exactly build, runner, and controller outputs")
    rendered = [render_file(spec) for spec in record["files"]]
    for output_path, text, _ in rendered:
        if write:
            output_path.parent.mkdir(parents=True, exist_ok=True)
            if output_path.exists() and output_path.read_text(encoding="utf-8") != text:
                raise ValueError(f"refusing to replace differing output: {output_path}")
            output_path.write_text(text, encoding="utf-8", newline="")
        elif not output_path.is_file() or output_path.read_bytes() != text.encode("utf-8"):
            raise ValueError(f"generated output is absent or differs: {output_path}")
    return "\n".join(delta for _, _, delta in rendered)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--delta", required=True)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    try:
        print(generate(Path(args.delta), write=args.write), end="")
    except (OSError, ValueError, json.JSONDecodeError) as error:
        raise SystemExit(f"Candidate generation failed: {error}") from error


if __name__ == "__main__":
    main()
