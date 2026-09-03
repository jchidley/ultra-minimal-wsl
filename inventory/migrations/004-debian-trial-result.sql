PRAGMA foreign_keys = ON;

BEGIN IMMEDIATE;

ALTER TABLE trials ADD COLUMN debian_result TEXT NOT NULL DEFAULT '';

DROP VIEW trial_summary;
CREATE VIEW trial_summary AS
SELECT trial_id,parent_trial,status,boot_level,toybox_result,alpine_result,arch_result,debian_result,
       failure_signature,windows_error,stock_restore_verified,analysis_path
FROM trials;

UPDATE metadata SET value='4' WHERE key='schema';
PRAGMA user_version = 4;
COMMIT;
