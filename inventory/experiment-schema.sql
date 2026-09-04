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
    debian_result TEXT NOT NULL,
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

CREATE TABLE trial_corrections (
    correction_id INTEGER PRIMARY KEY,
    trial_id TEXT NOT NULL REFERENCES trials(trial_id),
    field TEXT NOT NULL CHECK(field IN ('failure_signature','metadata_notes','ledger_notes')),
    superseded_value TEXT NOT NULL,
    corrected_value TEXT NOT NULL CHECK(length(trim(corrected_value)) > 0),
    reason TEXT NOT NULL CHECK(length(trim(reason)) > 0),
    evidence_path TEXT NOT NULL,
    evidence_sha256 TEXT NOT NULL CHECK(length(evidence_sha256) = 64),
    recorded_utc TEXT NOT NULL,
    CHECK(superseded_value <> corrected_value)
);
CREATE INDEX trial_corrections_by_field ON trial_corrections(trial_id,field,correction_id);
CREATE TRIGGER corrections_no_update BEFORE UPDATE ON trial_corrections
BEGIN SELECT RAISE(ABORT, 'trial corrections are append-only'); END;
CREATE TRIGGER corrections_no_delete BEFORE DELETE ON trial_corrections
BEGIN SELECT RAISE(ABORT, 'trial corrections are append-only'); END;
CREATE TRIGGER corrections_no_replace BEFORE INSERT ON trial_corrections
WHEN EXISTS (SELECT 1 FROM trial_corrections WHERE correction_id=NEW.correction_id)
BEGIN SELECT RAISE(ABORT, 'trial corrections are append-only'); END;

CREATE VIEW trial_effective AS
SELECT t.trial_id,t.status,t.started_utc,t.finished_utc,t.source_commit,t.toolchain,
       t.kernel_config_path,t.kernel_config_sha256,t.parent_trial,t.config_name,t.change_group,
       t.explicit_symbols,t.autoselected_symbols,t.kernel_image_path,t.kernel_image_sha256,
       t.boot_level,t.toybox_result,t.alpine_result,t.arch_result,t.debian_result,
       coalesce((SELECT corrected_value FROM trial_corrections c
                 WHERE c.trial_id=t.trial_id AND c.field='failure_signature'
                 ORDER BY correction_id DESC LIMIT 1),t.failure_signature) AS failure_signature,
       t.windows_error,t.kernel_log_path,t.crash_log_path,t.classification,t.stock_restore_verified,t.analysis_path,
       coalesce((SELECT corrected_value FROM trial_corrections c
                 WHERE c.trial_id=t.trial_id AND c.field='metadata_notes'
                 ORDER BY correction_id DESC LIMIT 1),t.metadata_notes) AS metadata_notes,
       coalesce((SELECT corrected_value FROM trial_corrections c
                 WHERE c.trial_id=t.trial_id AND c.field='ledger_notes'
                 ORDER BY correction_id DESC LIMIT 1),t.ledger_notes) AS ledger_notes
FROM trials t;

CREATE VIEW trial_summary AS
SELECT trial_id,parent_trial,status,boot_level,toybox_result,alpine_result,arch_result,debian_result,
       failure_signature,windows_error,stock_restore_verified,analysis_path,
       (SELECT count(*) FROM trial_corrections c WHERE c.trial_id=t.trial_id) AS correction_count
FROM trial_effective t;

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

PRAGMA user_version = 5;
