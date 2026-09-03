#!/usr/bin/env python3
"""Apply reviewed experiment-database schema migrations transactionally."""

from __future__ import annotations

import argparse
import hashlib
import sqlite3
from pathlib import Path

ROOT = Path(__file__).parents[1]
DEFAULT_DB = ROOT / "inventory/experiments.sqlite"
MIGRATIONS = {
    1: ROOT / "inventory/migrations/002-operation-templates.sql",
    2: ROOT / "inventory/migrations/003-arch-trial-result.sql",
}
TARGET_VERSION = 3


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_templates(db: sqlite3.Connection) -> None:
    for template_id, value, expected in db.execute(
        "SELECT template_id,path,sha256 FROM operation_templates"
    ):
        path = ROOT / value
        if not path.is_file() or sha256(path) != expected:
            raise SystemExit(f"Template identity mismatch for {template_id}: {path}")


def migrate(path: Path) -> None:
    if not path.is_file():
        raise SystemExit(f"Experiment database is missing: {path}")
    db = sqlite3.connect(path)
    try:
        db.execute("PRAGMA foreign_keys=ON")
        version = db.execute("PRAGMA user_version").fetchone()[0]
        while version < TARGET_VERSION:
            migration = MIGRATIONS.get(version)
            if migration is None:
                raise SystemExit(f"No migration from schema version {version}")
            db.executescript(migration.read_text(encoding="utf-8"))
            version = db.execute("PRAGMA user_version").fetchone()[0]
        if version != TARGET_VERSION:
            raise SystemExit(f"Database schema {version} is newer than supported {TARGET_VERSION}")
        verify_templates(db)
        integrity = db.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok" or list(db.execute("PRAGMA foreign_key_check")):
            raise SystemExit(f"Migrated database validation failed: integrity={integrity}")
        db.execute("PRAGMA journal_mode=DELETE")
    finally:
        db.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default=str(DEFAULT_DB))
    args = parser.parse_args()
    migrate(Path(args.db).resolve())
