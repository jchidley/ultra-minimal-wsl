from __future__ import annotations

import csv
import hashlib
import sqlite3
import tempfile
import unittest
from pathlib import Path

from tools.inventory_records import parse_config, sync_configs


class InventoryRecordsTests(unittest.TestCase):
    def test_parse_config_normalizes_strings_and_unset_values(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / ".config"
            path.write_text('CONFIG_NAME="value"\n# CONFIG_FLAG is not set\n')
            self.assertEqual(
                parse_config(path, {"NAME": "string", "FLAG": "bool"}),
                {"NAME": "value", "FLAG": "n"},
            )

    def test_candidate_is_rebuilt_from_parent_and_exact_config(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            parent = root / "parent.config"
            child = root / "child.config"
            parent.write_text('CONFIG_FEATURE=n\nCONFIG_NAME="same"\n')
            child.write_text('CONFIG_FEATURE=y\nCONFIG_NAME="same"\n')

            manifest = root / "configs.csv"
            rows = [
                ("parent", parent.name, "", self._sha(parent), "G-001"),
                ("child", child.name, "parent", self._sha(child), "K-001"),
            ]
            with manifest.open("w", newline="") as handle:
                writer = csv.writer(handle)
                writer.writerow(("name", "path", "parent", "sha256", "trial_id"))
                writer.writerows(rows)

            db = sqlite3.connect(":memory:")
            db.executescript(
                """PRAGMA foreign_keys=ON;
                   CREATE TABLE symbols(name TEXT PRIMARY KEY,type TEXT NOT NULL);
                   CREATE TABLE configs(name TEXT PRIMARY KEY,path TEXT NOT NULL);
                   CREATE TABLE config_values(
                     config_name TEXT,symbol TEXT,value TEXT,
                     PRIMARY KEY(config_name,symbol),
                     FOREIGN KEY(config_name) REFERENCES configs(name));
                   INSERT INTO symbols VALUES ('FEATURE','bool'),('NAME','string');
                   INSERT INTO configs VALUES ('parent','old');
                   INSERT INTO config_values VALUES
                     ('parent','FEATURE','n'),('parent','NAME','wrong');"""
            )
            sync_configs(db, manifest, root)
            self.assertEqual(
                db.execute(
                    "SELECT symbol,value FROM config_values WHERE config_name='child' ORDER BY symbol"
                ).fetchall(),
                [("FEATURE", "y"), ("NAME", "same")],
            )
            db.close()

    @staticmethod
    def _sha(path: Path) -> str:
        return hashlib.sha256(path.read_bytes()).hexdigest()


if __name__ == "__main__":
    unittest.main()
