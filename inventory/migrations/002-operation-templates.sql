PRAGMA foreign_keys = ON;

BEGIN IMMEDIATE;

CREATE TABLE operation_templates (
    template_id TEXT PRIMARY KEY,
    path TEXT NOT NULL UNIQUE,
    sha256 TEXT NOT NULL CHECK(length(sha256) = 64)
) WITHOUT ROWID;

CREATE TABLE operation_template_bindings (
    operation_id TEXT PRIMARY KEY REFERENCES operations(operation_id),
    template_id TEXT NOT NULL REFERENCES operation_templates(template_id)
) WITHOUT ROWID;

CREATE TABLE trial_operation_results (
    trial_id TEXT PRIMARY KEY REFERENCES trials(trial_id),
    operation_id TEXT NOT NULL UNIQUE REFERENCES operations(operation_id)
) WITHOUT ROWID;

UPDATE metadata SET value='2' WHERE key='schema';

INSERT INTO operation_templates VALUES
('controlled-runtime-v1','control-plane/contract-templates/controlled-runtime.v1.json','b2abe14b297997fb91fdc1d82b15ed85f35c75595cca5e37279cb06040910e89'),
('debug-console-diagnostic-v1','control-plane/contract-templates/debug-console-diagnostic.v1.json','6a14eb071a65a5f85d45bf22351e1ffe1c3b6d9e8272c0dfab4b74fb87dfe4fe'),
('legacy-migrated-runtime-v1','control-plane/contract-templates/legacy-migrated-runtime.v1.json','c29e767b9f0c28b51d52955865a42affa06a1a9caec45a85bfc1a077c4ee6212');

INSERT INTO operation_template_bindings
SELECT operation_id,'legacy-migrated-runtime-v1'
FROM operations
WHERE operation_id IN (
    'minimal-v6-k-pidns-runtime-008',
    'minimal-v6-k-pidns-runtime-009',
    'minimal-v6-k-pidns-runtime-010',
    'minimal-v6-k-pidns-runtime-011',
    'minimal-v6-k-pidns-runtime-012'
);
INSERT INTO operation_template_bindings VALUES
('minimal-v6-k-overlay-pidns-runtime-013','controlled-runtime-v1'),
('minimal-v6-k-overlay-pidns-diagnostic-runtime-014','debug-console-diagnostic-v1'),
('minimal-v6-k-overlay-pidns-diagnostic-runtime-015','debug-console-diagnostic-v1');

INSERT INTO trial_operation_results
SELECT 'CP-MINIMAL-V6-K-PIDNS-001','minimal-v6-k-pidns-runtime-012'
WHERE EXISTS (SELECT 1 FROM trials WHERE trial_id='CP-MINIMAL-V6-K-PIDNS-001');
INSERT INTO trial_operation_results
SELECT 'CP-MINIMAL-V6-K-OVERLAY-PIDNS-001','minimal-v6-k-overlay-pidns-runtime-013'
WHERE EXISTS (SELECT 1 FROM trials WHERE trial_id='CP-MINIMAL-V6-K-OVERLAY-PIDNS-001');
INSERT INTO trial_operation_results
SELECT 'CP-MINIMAL-V6-K-OVERLAY-PIDNS-DIAG-001','minimal-v6-k-overlay-pidns-diagnostic-runtime-015'
WHERE EXISTS (SELECT 1 FROM trials WHERE trial_id='CP-MINIMAL-V6-K-OVERLAY-PIDNS-DIAG-001');

DROP VIEW active_operation;
CREATE VIEW active_operation AS
SELECT o.operation_id,o.kind,o.candidate_id,o.trial_id,o.status,o.executable,
       b.template_id,a.path AS controller_path,a.sha256 AS controller_sha256,
       o.rationale,o.fixed_contract,o.runtime_boundary
FROM operations o
LEFT JOIN operation_template_bindings b USING(operation_id)
LEFT JOIN artifacts a ON a.artifact_id=o.controller_artifact_id
WHERE o.executable=1 AND o.status IN ('prepared','runtime-planned','uac-requested','worker-started','probe-started');

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

PRAGMA user_version = 2;
COMMIT;
