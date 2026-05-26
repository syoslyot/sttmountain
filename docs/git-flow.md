# Git Flow

This repo follows protected-branch Git flow. Do not push directly to `main` or `develop`.

## Branch Types

| Branch | Purpose |
| --- | --- |
| `main` | production release |
| `develop` | integration branch |
| `feature/<scope>-<desc>` | new behavior |
| `fix/<scope>-<desc>` | bug fix |
| `docs/<desc>` | documentation |
| `release/v<version>` | release preparation |
| `hotfix/<desc>` | urgent production fix |

## Feature and Fix Flow

```text
develop -> feature/fix branch -> PR to develop
```

After merge, pull `develop`.

## Release Flow

```text
develop -> release/v<version>
release/v<version> -> PR to main
release/v<version> -> PR to develop
```

Release branches may include:

- `VERSION` bump;
- docs updates;
- final migration notes;
- main/develop synchronization changes.

Do not merge release PRs locally. Wait for GitHub PR merge, then pull.

## Hotfix Flow

```text
main -> hotfix/<desc>
hotfix/<desc> -> PR to main
hotfix/<desc> -> PR to develop
```

If the hotfix includes SQL, add it as a migration and run it manually in dev/prod as appropriate.

## DB Migration Reminder

Whenever a PR adds or changes SQL, explicitly remind the DB admin to run the migration manually in Supabase. The usual order is dev first, verify, then prod.
