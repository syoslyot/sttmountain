# Deployment and Automation

This repo uses GitHub Actions for validation, scheduled sync, manual sync, and Docker image publishing.

## GitHub Actions

PRs targeting `main` run:

```bash
python -c "from app.main import app; print('Import OK')"
```

After merge to `main`, the workflow builds and pushes the Docker image to GHCR.

## Scheduled Sync

The workflow can run on schedule and through manual dispatch.

During sync, GitHub Actions installs:

- Python dependencies from `requirements.txt`;
- LibreOffice for document conversion;
- `fonts-noto-cjk` for Chinese text rendering.

Then it runs:

```text
scripts/sync_drive.py
scripts/normalize.py
```

## Secrets

| Secret | Purpose |
| --- | --- |
| `GDRIVE_CREDENTIALS_JSON` | Google Service Account credentials |
| `GDRIVE_ROOT_FOLDER_ID` | Drive root folder to scan |
| `SUPABASE_URL` | prod Supabase URL |
| `SUPABASE_SERVICE_KEY` | prod service role key |
| `SUPABASE_URL_DEV` | dev Supabase URL |
| `SUPABASE_SERVICE_KEY_DEV` | dev service role key |

Service role keys have write access. Never expose them to frontend code.

## Deployment Target

The Docker image is pushed to GHCR. The existing server deployment uses Docker Compose, Nginx, and Watchtower to pull new images and restart services.

## Manual DB Migration

GitHub Actions does not apply DB migrations. The DB admin must run SQL manually in Supabase:

1. dev DB;
2. verification;
3. prod DB;
4. release frontend/backend changes.
