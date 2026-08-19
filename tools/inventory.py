#!/usr/bin/env python3
"""Search and update the generated Kconfig dependency inventory."""

from __future__ import annotations

import argparse
import csv
import sqlite3
from pathlib import Path

FIELDS = {
    "review_status",
    "requirement_status",
    "documentation_status",
    "layer",
    "feature_group",
    "checked",
    "rationale",
    "source_url",
    "notes",
}


def symbol_name(value: str) -> str:
    return value.strip().upper().removeprefix("CONFIG_")


def export_annotations(db: sqlite3.Connection, path: Path) -> None:
    query = """SELECT 'CONFIG_' || symbol AS symbol, review_status,
        requirement_status, documentation_status, layer, feature_group,
        checked, rationale, source_url, notes FROM annotations ORDER BY symbol"""
    cursor = db.execute(query)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow([item[0] for item in cursor.description])
        writer.writerows(cursor)


def show(db: sqlite3.Connection, name: str) -> None:
    row = db.execute(
        """SELECT s.*, a.review_status, a.requirement_status,
                  a.documentation_status, a.layer, a.feature_group, a.checked,
                  a.rationale, a.source_url, a.notes
             FROM symbols s JOIN annotations a ON a.symbol=s.name
            WHERE s.name=?""",
        (name,),
    ).fetchone()
    if not row:
        raise SystemExit(f"Unknown symbol CONFIG_{name}")
    labels = [item[0] for item in db.execute("SELECT 1").description]
    labels = [item[1] for item in db.execute("PRAGMA table_info(symbols)")] + [
        "review_status", "requirement_status", "documentation_status", "layer",
        "feature_group", "checked", "rationale", "source_url", "notes"
    ]
    print(f"CONFIG_{name}")
    for label, value in zip(labels, row):
        if value not in (None, ""):
            print(f"  {label}: {value}")
    print("  config values:")
    for config, value in db.execute(
        "SELECT config_name,value FROM config_values WHERE symbol=? ORDER BY config_name", (name,)
    ):
        print(f"    {config}: {value}")
    print("  outgoing relationships:")
    for relation, target, condition, origin in db.execute(
        "SELECT relation,target,condition_expr,origin FROM edges WHERE source=? ORDER BY relation,target", (name,)
    ):
        suffix = f" if {condition}" if condition and condition != "y" else ""
        print(f"    {relation} CONFIG_{target}{suffix} [{origin}]")
    print("  incoming relationships:")
    for relation, source, condition, origin in db.execute(
        "SELECT relation,source,condition_expr,origin FROM edges WHERE target=? ORDER BY relation,source", (name,)
    ):
        suffix = f" if {condition}" if condition and condition != "y" else ""
        print(f"    CONFIG_{source} {relation}{suffix} [{origin}]")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default="inventory/kconfig-dependencies.sqlite")
    parser.add_argument("--annotations", default="inventory/annotations.csv")
    sub = parser.add_subparsers(dest="command", required=True)
    show_parser = sub.add_parser("show")
    show_parser.add_argument("symbol")
    todo_parser = sub.add_parser("todo")
    todo_parser.add_argument("--enabled-in")
    todo_parser.add_argument("--limit", type=int, default=100)
    set_parser = sub.add_parser("set")
    set_parser.add_argument("symbol")
    set_parser.add_argument("assignments", nargs="+", metavar="FIELD=VALUE")
    trial_parser = sub.add_parser("trial")
    trial_parser.add_argument("trial_id", nargs="?")
    args = parser.parse_args()

    db = sqlite3.connect(Path(args.db))
    if args.command == "show":
        show(db, symbol_name(args.symbol))
    elif args.command == "todo":
        parameters = []
        join = ""
        where = "a.checked=0"
        if args.enabled_in:
            join = "JOIN config_values cv ON cv.symbol=s.name"
            where += " AND cv.config_name=? AND cv.value IN ('y','m')"
            parameters.append(args.enabled_in)
        parameters.append(args.limit)
        query = f"""SELECT 'CONFIG_'||s.name, s.type, s.prompt,
                    a.requirement_status, a.documentation_status
               FROM symbols s JOIN annotations a ON a.symbol=s.name {join}
              WHERE {where} ORDER BY s.name LIMIT ?"""
        for row in db.execute(query, parameters):
            print("\t".join(str(value) for value in row))
    elif args.command == "set":
        name = symbol_name(args.symbol)
        exists = db.execute("SELECT 1 FROM annotations WHERE symbol=?", (name,)).fetchone()
        if not exists:
            raise SystemExit(f"Unknown symbol CONFIG_{name}")
        updates = {}
        for assignment in args.assignments:
            if "=" not in assignment:
                raise SystemExit(f"Expected FIELD=VALUE: {assignment}")
            field, value = assignment.split("=", 1)
            if field not in FIELDS:
                raise SystemExit(f"Unknown field {field}; choose from {sorted(FIELDS)}")
            if field == "checked":
                value = int(value.lower() in {"1", "true", "yes", "y", "x"})
            updates[field] = value
        clause = ", ".join(f"{field}=?" for field in updates)
        db.execute(f"UPDATE annotations SET {clause} WHERE symbol=?", (*updates.values(), name))
        db.commit()
        export_annotations(db, Path(args.annotations))
        print(f"Updated CONFIG_{name} and {args.annotations}")
    elif args.command == "trial":
        if not db.execute(
            "SELECT 1 FROM sqlite_master WHERE type='view' AND name='trial_inventory'"
        ).fetchone():
            raise SystemExit("Trial inventory is absent; run tools/inventory_records.py")
        if args.trial_id:
            cursor = db.execute(
                "SELECT * FROM trial_inventory WHERE trial_id=?", (args.trial_id,)
            )
            row = cursor.fetchone()
            if not row:
                raise SystemExit(f"Unknown trial {args.trial_id}")
            for label, value in zip((item[0] for item in cursor.description), row):
                if value not in (None, ""):
                    print(f"{label}: {value}")
        else:
            for row in db.execute(
                """SELECT trial_id,status,parent_trial,config_name,change_group,
                          boot_level,stock_restore_verified
                     FROM trial_inventory ORDER BY started_utc"""
            ):
                print("\t".join(str(value) for value in row))
    db.close()


if __name__ == "__main__":
    main()
