# vlaaibaar/ddev-addon

Shared DDEV features for Vlaaibaar projects. Install or update in a project with:

```
ddev add-on get vlaaibaar/ddev-addon
ddev restart
```

Updating overwrites only the add-on's own files (marked `#ddev-generated`). Project settings are never overwritten.

## Sync: pull/push database and uploads

Adds the DDEV providers `production` and `staging` for Craft CMS sites.

1. Fill in the shared settings in `.ddev/vlaaibaar/sync/production.env` and `staging.env` (created on install). Commit them.
2. Choose the SSH user:
   - **Shared user** (recommended on Cloudways): set `SSH_USER` to the server's master user in the shared `.env` file. Each developer adds their own public key under *Master Credentials → SSH Public Keys*, so access is revoked per person by removing their key.
   - **Personal users**: each developer creates their own `production.local.env` / `staging.local.env` next to them, with only their SSH user (see `example.local.env`). These files are gitignored and override a shared `SSH_USER`.
3. Use it:

```
ddev auth ssh                       # once per session
ddev pull production                # DB + uploads -> local
ddev pull staging --skip-files      # DB only
ddev pull staging --skip-db         # uploads only
ddev push staging                   # local DB + uploads -> staging
ddev push staging --skip-files      # DB only
ddev push staging --skip-db         # uploads only
```

Add `-y` to skip the confirmation prompt.

| Setting | Meaning |
| --- | --- |
| `SSH_HOST` | Host or IP of the server, without a user. An older `user@host` value still works |
| `SSH_USER` | SSH user. Either shared in `<env>.env` (e.g. the Cloudways master user) or personal in `<env>.local.env`, which wins. SSH keys handle authentication |
| `REMOTE_PATH` | Folder with the `craft` executable. Relative paths start from the SSH user's home folder; use an absolute path for the Cloudways master user |
| `REMOTE_UPLOADS` | Uploads folder on the server |
| `ALLOW_PUSH` | `true` allows `ddev push`. Created as `false` for production, `true` for staging |
| `REMOTE_PHP` | Optional. PHP binary on the server, default `php<version>` from `php_version` in `.ddev/config.yaml` (e.g. `php8.3`), falling back to `php` if that doesn't exist |

How it works:
- The database is exported and restored with Craft's `craft db/backup` / `db/restore` on the server, so no database passwords are needed locally. After a push, `craft up` runs.
- Commands on the server run with `umask 002`, and pushed uploads are made group-writable, so files stay writable for the site when the SSH user isn't the PHP user (e.g. the Cloudways master user).
- Pulling uploads mirrors the server (local-only files are removed). Pushing uploads never deletes files on the server.
- Local uploads go to the project's `upload_dirs` (set in `.ddev/config.yaml`).
