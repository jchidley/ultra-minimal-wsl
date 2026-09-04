PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;

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

DROP VIEW trial_summary;
CREATE VIEW trial_summary AS
SELECT trial_id,parent_trial,status,boot_level,toybox_result,alpine_result,arch_result,debian_result,
       failure_signature,windows_error,stock_restore_verified,analysis_path,
       (SELECT count(*) FROM trial_corrections c WHERE c.trial_id=t.trial_id) AS correction_count
FROM trial_effective t;

UPDATE metadata SET value='5' WHERE key='schema';
PRAGMA user_version = 5;
COMMIT;
