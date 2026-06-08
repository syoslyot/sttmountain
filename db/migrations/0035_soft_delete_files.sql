-- Migration 0035: soft delete for file tables
-- Instead of hard-deleting rows and Storage objects immediately,
-- mark deleted_at / deleted_by and let a scheduled script clean up after 3 months.

ALTER TABLE gpx_files
  ADD COLUMN IF NOT EXISTS deleted_at  TIMESTAMPTZ DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS deleted_by  UUID        DEFAULT NULL;

ALTER TABLE map_files
  ADD COLUMN IF NOT EXISTS deleted_at  TIMESTAMPTZ DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS deleted_by  UUID        DEFAULT NULL;

ALTER TABLE record_files
  ADD COLUMN IF NOT EXISTS deleted_at  TIMESTAMPTZ DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS deleted_by  UUID        DEFAULT NULL;

-- Index to speed up the nightly cleanup job
CREATE INDEX IF NOT EXISTS idx_gpx_files_deleted_at    ON gpx_files    (deleted_at) WHERE deleted_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_map_files_deleted_at    ON map_files    (deleted_at) WHERE deleted_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_record_files_deleted_at ON record_files (deleted_at) WHERE deleted_at IS NOT NULL;
