PRAGMA foreign_keys = ON;
PRAGMA journal_mode = DELETE;

CREATE TABLE metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE configs (
    name TEXT PRIMARY KEY,
    path TEXT NOT NULL,
    parent TEXT REFERENCES configs(name),
    sha256 TEXT NOT NULL CHECK(length(sha256) = 64),
    trial_id TEXT
) WITHOUT ROWID;

CREATE TABLE candidates (
    candidate_id TEXT PRIMARY KEY,
    kind TEXT NOT NULL,
    parent_candidate_id TEXT REFERENCES candidates(candidate_id),
    status TEXT NOT NULL,
    rationale TEXT NOT NULL DEFAULT ''
) WITHOUT ROWID;

CREATE TABLE artifacts (
    artifact_id INTEGER PRIMARY KEY,
    kind TEXT NOT NULL,
    location TEXT NOT NULL CHECK(location IN ('repository','host','fixture','evidence')),
    path TEXT NOT NULL,
    sha256 TEXT NOT NULL CHECK(length(sha256) = 64),
    bytes INTEGER CHECK(bytes IS NULL OR bytes >= 0),
    product_code TEXT,
    signature_state TEXT,
    UNIQUE(path, sha256)
);

CREATE TABLE candidate_artifacts (
    candidate_id TEXT NOT NULL REFERENCES candidates(candidate_id),
    artifact_id INTEGER NOT NULL REFERENCES artifacts(artifact_id),
    role TEXT NOT NULL,
    PRIMARY KEY(candidate_id, role)
) WITHOUT ROWID;

CREATE TABLE operations (
    operation_id TEXT PRIMARY KEY,
    kind TEXT NOT NULL,
    candidate_id TEXT REFERENCES candidates(candidate_id),
    trial_id TEXT,
    parent_operation_id TEXT REFERENCES operations(operation_id),
    status TEXT NOT NULL,
    executable INTEGER NOT NULL CHECK(executable IN (0,1)),
    controller_artifact_id INTEGER REFERENCES artifacts(artifact_id),
    rationale TEXT NOT NULL DEFAULT '',
    fixed_contract TEXT NOT NULL DEFAULT '',
    runtime_boundary TEXT NOT NULL DEFAULT '',
    prepared_utc TEXT,
    uac_requested_utc TEXT,
    worker_started_utc TEXT,
    first_probe_utc TEXT,
    completed_utc TEXT
) WITHOUT ROWID;

CREATE TABLE operation_artifacts (
    operation_id TEXT NOT NULL REFERENCES operations(operation_id),
    artifact_id INTEGER NOT NULL REFERENCES artifacts(artifact_id),
    role TEXT NOT NULL,
    PRIMARY KEY(operation_id, role)
) WITHOUT ROWID;

CREATE TABLE operation_templates (
    template_id TEXT PRIMARY KEY,
    path TEXT NOT NULL UNIQUE,
    sha256 TEXT NOT NULL CHECK(length(sha256) = 64)
) WITHOUT ROWID;

CREATE TABLE operation_template_bindings (
    operation_id TEXT PRIMARY KEY REFERENCES operations(operation_id),
    template_id TEXT NOT NULL REFERENCES operation_templates(template_id)
) WITHOUT ROWID;

CREATE TABLE operation_dispositions (
    disposition_id INTEGER PRIMARY KEY,
    operation_id TEXT NOT NULL REFERENCES operations(operation_id),
    disposition TEXT NOT NULL,
    reason TEXT NOT NULL,
    recorded_utc TEXT NOT NULL
);

CREATE TABLE trials (
    trial_id TEXT PRIMARY KEY,
    status TEXT NOT NULL,
    started_utc TEXT NOT NULL,
    finished_utc TEXT NOT NULL,
    source_commit TEXT NOT NULL,
    toolchain TEXT NOT NULL,
    kernel_config_path TEXT NOT NULL,
    kernel_config_sha256 TEXT NOT NULL,
    parent_trial TEXT REFERENCES trials(trial_id),
    config_name TEXT REFERENCES configs(name),
    change_group TEXT NOT NULL,
    explicit_symbols TEXT NOT NULL,
    autoselected_symbols TEXT NOT NULL,
    kernel_image_path TEXT NOT NULL,
    kernel_image_sha256 TEXT NOT NULL,
    boot_level TEXT NOT NULL,
    toybox_result TEXT NOT NULL,
    alpine_result TEXT NOT NULL,
    arch_result TEXT NOT NULL,
    failure_signature TEXT NOT NULL,
    windows_error TEXT NOT NULL,
    kernel_log_path TEXT NOT NULL,
    crash_log_path TEXT NOT NULL,
    classification TEXT NOT NULL,
    stock_restore_verified TEXT NOT NULL,
    analysis_path TEXT NOT NULL,
    metadata_notes TEXT NOT NULL,
    ledger_notes TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE trial_operation_results (
    trial_id TEXT PRIMARY KEY REFERENCES trials(trial_id),
    operation_id TEXT NOT NULL UNIQUE REFERENCES operations(operation_id)
) WITHOUT ROWID;

CREATE VIEW active_operation AS
SELECT o.operation_id,o.kind,o.candidate_id,o.trial_id,o.status,o.executable,
       b.template_id,a.path AS controller_path,a.sha256 AS controller_sha256,
       o.rationale,o.fixed_contract,o.runtime_boundary
FROM operations o
LEFT JOIN operation_template_bindings b USING(operation_id)
LEFT JOIN artifacts a ON a.artifact_id=o.controller_artifact_id
WHERE o.executable=1 AND o.status IN ('prepared','runtime-planned','uac-requested','worker-started','probe-started');

CREATE VIEW trial_summary AS
SELECT trial_id,parent_trial,status,boot_level,toybox_result,alpine_result,arch_result,
       failure_signature,windows_error,stock_restore_verified,analysis_path
FROM trials;

CREATE VIEW candidate_lineage AS
WITH RECURSIVE lineage(candidate_id,parent_candidate_id,depth) AS (
  SELECT candidate_id,parent_candidate_id,0 FROM candidates
  UNION ALL
  SELECT lineage.candidate_id,c.parent_candidate_id,lineage.depth+1
  FROM lineage JOIN candidates c ON c.candidate_id=lineage.parent_candidate_id
  WHERE lineage.parent_candidate_id IS NOT NULL
)
SELECT * FROM lineage;

CREATE TRIGGER trials_no_update BEFORE UPDATE ON trials
BEGIN SELECT RAISE(ABORT, 'finalized trials are immutable'); END;
CREATE TRIGGER trials_no_delete BEFORE DELETE ON trials
BEGIN SELECT RAISE(ABORT, 'finalized trials are immutable'); END;
CREATE TRIGGER terminal_operations_no_update BEFORE UPDATE ON operations
WHEN OLD.status IN ('completed','candidate-finalized','infrastructure-failure','superseded','cancelled')
BEGIN SELECT RAISE(ABORT, 'terminal operations are immutable'); END;
CREATE TRIGGER dispositions_no_update BEFORE UPDATE ON operation_dispositions
BEGIN SELECT RAISE(ABORT, 'operation dispositions are append-only'); END;
CREATE TRIGGER dispositions_no_delete BEFORE DELETE ON operation_dispositions
BEGIN SELECT RAISE(ABORT, 'operation dispositions are append-only'); END;
CREATE TRIGGER templates_no_update BEFORE UPDATE ON operation_templates
BEGIN SELECT RAISE(ABORT, 'operation templates are immutable'); END;
CREATE TRIGGER templates_no_delete BEFORE DELETE ON operation_templates
BEGIN SELECT RAISE(ABORT, 'operation templates are immutable'); END;
CREATE TRIGGER template_bindings_no_update BEFORE UPDATE ON operation_template_bindings
BEGIN SELECT RAISE(ABORT, 'operation template bindings are immutable'); END;
CREATE TRIGGER template_bindings_no_delete BEFORE DELETE ON operation_template_bindings
BEGIN SELECT RAISE(ABORT, 'operation template bindings are immutable'); END;
CREATE TRIGGER trial_results_no_update BEFORE UPDATE ON trial_operation_results
BEGIN SELECT RAISE(ABORT, 'trial-producing operations are immutable'); END;
CREATE TRIGGER trial_results_no_delete BEFORE DELETE ON trial_operation_results
BEGIN SELECT RAISE(ABORT, 'trial-producing operations are immutable'); END;

PRAGMA user_version = 3;
