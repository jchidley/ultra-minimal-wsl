#!/usr/bin/env python3
"""Build a searchable SQLite/CSV inventory from a Linux Kconfig tree.

Run with uv, for example:
  uv run --with kconfiglib==14.1.0 tools/build-kconfig-inventory.py --srctree PATH ...
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import os
import re
import sqlite3
import sys
from pathlib import Path

import kconfiglib

# Large driver menus can produce deeply nested OR expressions.
sys.setrecursionlimit(100_000)

TYPE_NAMES = {
    kconfiglib.BOOL: "bool",
    kconfiglib.TRISTATE: "tristate",
    kconfiglib.STRING: "string",
    kconfiglib.INT: "int",
    kconfiglib.HEX: "hex",
    kconfiglib.UNKNOWN: "unknown",
}

ANNOTATION_FIELDS = [
    "symbol",
    "review_status",
    "requirement_status",
    "documentation_status",
    "layer",
    "feature_group",
    "checked",
    "rationale",
    "source_url",
    "notes",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--srctree", required=True, help="Linux kernel source root")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--annotations", required=True)
    parser.add_argument(
        "--config",
        action="append",
        default=[],
        metavar="NAME=PATH",
        help="Config snapshot to include; repeatable",
    )
    parser.add_argument("--arch", default="x86")
    parser.add_argument("--srcarch", default="x86")
    return parser.parse_args()


def parse_named_paths(values: list[str]) -> list[tuple[str, Path]]:
    result = []
    for value in values:
        if "=" not in value:
            raise SystemExit(f"--config must be NAME=PATH: {value}")
        name, path = value.split("=", 1)
        if not name or not path:
            raise SystemExit(f"--config must be NAME=PATH: {value}")
        result.append((name, Path(path).resolve()))
    return result


def expression_symbols(expr, defined: set) -> set[str]:
    found: set[str] = set()

    def walk(item) -> None:
        if isinstance(item, kconfiglib.Symbol):
            if item in defined:
                found.add(item.name)
            return
        if isinstance(item, tuple):
            for child in item[1:]:
                walk(child)

    walk(expr)
    return found


def expression_text(expr) -> str:
    return kconfiglib.expr_str(expr) if expr is not None else ""


def locations(sym) -> str:
    return ";".join(f"{node.filename}:{node.linenr}" for node in sym.nodes)


def prompts(sym) -> str:
    return " | ".join(node.prompt[0] for node in sym.nodes if node.prompt)


def help_text(sym) -> str:
    return "\n\n".join(node.help.strip() for node in sym.nodes if node.help)


def load_annotations(path: Path) -> dict[str, dict[str, str]]:
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("w", newline="", encoding="utf-8") as handle:
            csv.DictWriter(handle, fieldnames=ANNOTATION_FIELDS).writeheader()
        return {}
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        missing = set(ANNOTATION_FIELDS) - set(reader.fieldnames or [])
        if missing:
            raise SystemExit(f"annotations CSV is missing columns: {sorted(missing)}")
        rows = {}
        for row in reader:
            name = row["symbol"].removeprefix("CONFIG_").strip()
            if name:
                row["symbol"] = name
                rows[name] = row
        return rows


def create_schema(db: sqlite3.Connection) -> None:
    db.executescript(
        """
        PRAGMA foreign_keys = ON;
        CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE symbols(
            name TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            prompt TEXT NOT NULL,
            help TEXT NOT NULL,
            direct_dep_expr TEXT NOT NULL,
            reverse_select_expr TEXT NOT NULL,
            reverse_imply_expr TEXT NOT NULL,
            locations TEXT NOT NULL
        );
        CREATE TABLE edges(
            source TEXT NOT NULL,
            target TEXT NOT NULL,
            relation TEXT NOT NULL,
            condition_expr TEXT NOT NULL DEFAULT '',
            origin TEXT NOT NULL DEFAULT '',
            PRIMARY KEY(source, target, relation, condition_expr, origin),
            FOREIGN KEY(source) REFERENCES symbols(name),
            FOREIGN KEY(target) REFERENCES symbols(name)
        );
        CREATE INDEX edges_target_idx ON edges(target, relation);
        CREATE INDEX edges_source_idx ON edges(source, relation);
        CREATE TABLE configs(name TEXT PRIMARY KEY, path TEXT NOT NULL);
        CREATE TABLE config_values(
            config_name TEXT NOT NULL,
            symbol TEXT NOT NULL,
            value TEXT NOT NULL,
            PRIMARY KEY(config_name, symbol),
            FOREIGN KEY(config_name) REFERENCES configs(name),
            FOREIGN KEY(symbol) REFERENCES symbols(name)
        );
        CREATE INDEX config_values_symbol_idx ON config_values(symbol, config_name);
        CREATE TABLE annotations(
            symbol TEXT PRIMARY KEY,
            review_status TEXT NOT NULL DEFAULT 'TODO',
            requirement_status TEXT NOT NULL DEFAULT 'UNRESOLVED',
            documentation_status TEXT NOT NULL DEFAULT '',
            layer TEXT NOT NULL DEFAULT '',
            feature_group TEXT NOT NULL DEFAULT '',
            checked INTEGER NOT NULL DEFAULT 0,
            rationale TEXT NOT NULL DEFAULT '',
            source_url TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT '',
            FOREIGN KEY(symbol) REFERENCES symbols(name)
        );
        CREATE VIEW dependency_list AS
            SELECT 'CONFIG_' || e.source AS symbol,
                   e.relation,
                   'CONFIG_' || e.target AS related_symbol,
                   e.condition_expr,
                   e.origin
            FROM edges e;
        CREATE VIEW config_differences AS
            SELECT a.config_name AS config_a,
                   b.config_name AS config_b,
                   'CONFIG_' || a.symbol AS symbol,
                   a.value AS value_a,
                   b.value AS value_b
              FROM config_values a
              JOIN config_values b ON b.symbol=a.symbol AND a.config_name < b.config_name
             WHERE a.value <> b.value;
        CREATE VIEW review_queue AS
            SELECT 'CONFIG_' || s.name AS symbol,
                   a.review_status,
                   a.requirement_status,
                   a.documentation_status,
                   a.layer,
                   a.feature_group,
                   a.checked,
                   s.type,
                   s.prompt,
                   s.direct_dep_expr,
                   (SELECT group_concat('CONFIG_' || e.target, ';')
                      FROM edges e
                     WHERE e.source = s.name AND e.relation = 'depends_on') AS depends_on,
                   (SELECT group_concat('CONFIG_' || e.source, ';')
                      FROM edges e
                     WHERE e.target = s.name AND e.relation IN ('depends_on','selects','implies')) AS depended_on_by,
                   a.rationale,
                   a.source_url,
                   a.notes
            FROM symbols s JOIN annotations a ON a.symbol = s.name;
        """
    )


def add_edge(db, source, target, relation, condition="", origin="") -> None:
    if source == target:
        return
    db.execute(
        "INSERT OR IGNORE INTO edges VALUES (?,?,?,?,?)",
        (source, target, relation, condition, origin),
    )


def export_query(db, path: Path, query: str) -> None:
    cursor = db.execute(query)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow([column[0] for column in cursor.description])
        writer.writerows(cursor)


def enable_transitional_compatibility() -> None:
    """Let released kconfiglib parse Linux 6.18's metadata-only property.

    `transitional` changes old-config migration/output behavior; it does not
    change dependency expressions. Keep symbols/defaults and ignore only the
    unsupported property line in the parser's input stream.
    """
    original_open = kconfiglib.Kconfig._open
    transitional_line = re.compile(r"(?m)^[ \t]*transitional[ \t]*$")
    modules_property = re.compile(r"(?m)^([ \t]*)modules[ \t]*$")

    def compatible_open(instance, filename, mode):
        handle = original_open(instance, filename, mode)
        if mode != "r":
            return handle
        content = handle.read()
        handle.close()
        if transitional_line.search(content):
            content = transitional_line.sub("# transitional (parser compatibility)", content)
        # Linux 6.18's `modules` property is the successor to `option modules`.
        content = modules_property.sub(r"\1option modules", content)
        return io.StringIO(content)

    kconfiglib.Kconfig._open = compatible_open


def main() -> None:
    args = parse_args()
    srctree = Path(args.srctree).resolve()
    output = Path(args.output_dir).resolve()
    annotation_path = Path(args.annotations).resolve()
    configs = parse_named_paths(args.config)
    output.mkdir(parents=True, exist_ok=True)

    os.environ.update(
        srctree=str(srctree),
        ARCH=args.arch,
        SRCARCH=args.srcarch,
        CC=os.environ.get("CC", "gcc"),
        LD=os.environ.get("LD", "ld"),
    )
    enable_transitional_compatibility()
    old_cwd = Path.cwd()
    os.chdir(srctree)
    try:
        kconf = kconfiglib.Kconfig(str(srctree / "Kconfig"), warn=False)
    finally:
        os.chdir(old_cwd)

    defined = set(kconf.unique_defined_syms)
    annotations = load_annotations(annotation_path)
    db_path = output / "kconfig-dependencies.sqlite"
    if db_path.exists():
        db_path.unlink()
    db = sqlite3.connect(db_path)
    create_schema(db)
    db.executemany(
        "INSERT INTO metadata VALUES (?,?)",
        [
            ("srctree", str(srctree)),
            ("arch", args.arch),
            ("srcarch", args.srcarch),
            ("symbol_count", str(len(defined))),
            ("parser", f"kconfiglib {getattr(kconfiglib, 'VERSION', 'unknown')}"),
            ("parser_compatibility", "Linux 6.18 transitional marker ignored; modules property translated to legacy option modules; dependency/default expressions retained"),
        ],
    )

    for sym in sorted(defined, key=lambda item: item.name):
        db.execute(
            "INSERT INTO symbols VALUES (?,?,?,?,?,?,?,?)",
            (
                sym.name,
                TYPE_NAMES.get(sym.type, str(sym.type)),
                prompts(sym),
                help_text(sym),
                expression_text(sym.direct_dep),
                expression_text(sym.rev_dep),
                expression_text(sym.weak_rev_dep),
                locations(sym),
            ),
        )

    for sym in sorted(defined, key=lambda item: item.name):
        for target in expression_symbols(sym.direct_dep, defined):
            add_edge(db, sym.name, target, "depends_on", expression_text(sym.direct_dep), "direct_dep")
        for node in sym.nodes:
            origin = f"{node.filename}:{node.linenr}"
            if node.prompt:
                for target in expression_symbols(node.prompt[1], defined):
                    add_edge(db, sym.name, target, "prompt_depends_on", expression_text(node.prompt[1]), origin)
            for target_sym, condition in node.selects:
                if target_sym in defined:
                    add_edge(db, sym.name, target_sym.name, "selects", expression_text(condition), origin)
            for target_sym, condition in node.implies:
                if target_sym in defined:
                    add_edge(db, sym.name, target_sym.name, "implies", expression_text(condition), origin)
            for default_expr, condition in node.defaults:
                for target in expression_symbols(default_expr, defined):
                    add_edge(db, sym.name, target, "default_ref", expression_text(condition), origin)
                for target in expression_symbols(condition, defined):
                    add_edge(db, sym.name, target, "default_condition", expression_text(condition), origin)
            for low, high, condition in node.ranges:
                for expr in (low, high):
                    for target in expression_symbols(expr, defined):
                        add_edge(db, sym.name, target, "range_ref", expression_text(condition), origin)
                for target in expression_symbols(condition, defined):
                    add_edge(db, sym.name, target, "range_condition", expression_text(condition), origin)

    for name, path in configs:
        db.execute("INSERT INTO configs VALUES (?,?)", (name, str(path)))
        kconf.load_config(str(path), replace=True)
        db.executemany(
            "INSERT INTO config_values VALUES (?,?,?)",
            ((name, sym.name, sym.str_value) for sym in defined),
        )

    for sym in sorted(defined, key=lambda item: item.name):
        row = annotations.get(sym.name, {})
        checked = str(row.get("checked", "")).strip().lower() in {"1", "true", "yes", "y", "x"}
        db.execute(
            "INSERT INTO annotations VALUES (?,?,?,?,?,?,?,?,?,?)",
            (
                sym.name,
                row.get("review_status") or "TODO",
                row.get("requirement_status") or "UNRESOLVED",
                row.get("documentation_status") or "",
                row.get("layer") or "",
                row.get("feature_group") or "",
                int(checked),
                row.get("rationale") or "",
                row.get("source_url") or "",
                row.get("notes") or "",
            ),
        )

    db.commit()
    export_query(db, output / "symbols.csv", "SELECT * FROM symbols ORDER BY name")
    export_query(db, output / "dependencies.csv", "SELECT * FROM dependency_list ORDER BY symbol, relation, related_symbol")
    export_query(db, output / "config-values.csv", "SELECT config_name, 'CONFIG_' || symbol AS symbol, value FROM config_values ORDER BY symbol, config_name")
    export_query(db, output / "config-differences.csv", "SELECT * FROM config_differences ORDER BY config_a, config_b, symbol")
    export_query(db, output / "review-queue.csv", "SELECT * FROM review_queue ORDER BY symbol")
    export_query(db, output / "stage1-enabled-review.csv", "SELECT rq.* FROM review_queue rq JOIN config_values cv ON cv.symbol=substr(rq.symbol,8) WHERE cv.config_name='stage1' AND cv.value IN ('y','m') ORDER BY rq.symbol")
    config_names = {name for name, _ in configs}
    if {"mkroot", "stage1"} <= config_names:
        export_query(
            db,
            output / "mkroot-stage1-delta.csv",
            """SELECT 'CONFIG_' || s.name AS symbol,
                      m.value AS mkroot_value, w.value AS stage1_value,
                      s.type, s.prompt, s.direct_dep_expr,
                      a.review_status, a.requirement_status,
                      a.documentation_status, a.layer, a.feature_group,
                      a.checked, a.rationale, a.source_url, a.notes
                 FROM symbols s
                 JOIN config_values m ON m.symbol=s.name AND m.config_name='mkroot'
                 JOIN config_values w ON w.symbol=s.name AND w.config_name='stage1'
                 JOIN annotations a ON a.symbol=s.name
                WHERE m.value <> w.value
                ORDER BY s.name""",
        )
    export_query(
        db,
        annotation_path,
        "SELECT 'CONFIG_' || symbol AS symbol, review_status, requirement_status, documentation_status, layer, feature_group, checked, rationale, source_url, notes FROM annotations ORDER BY symbol",
    )
    summary = {
        "database": str(db_path),
        "symbols": db.execute("SELECT count(*) FROM symbols").fetchone()[0],
        "edges": db.execute("SELECT count(*) FROM edges").fetchone()[0],
        "configs": [name for name, _ in configs],
        "annotations_applied": len(set(annotations) & {sym.name for sym in defined}),
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))
    db.close()


if __name__ == "__main__":
    main()
