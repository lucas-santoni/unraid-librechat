# unraid-librechat

A single-container LibreChat image for Unraid. Bundles LibreChat, MongoDB, and
MeiliSearch behind an s6-overlay v3 supervision tree on `debian:bookworm-slim`.
One row in the Docker tab, one appdata mount, secrets auto-generated on first
boot.

RAG (document upload + vector search) is intentionally **not** included. Use
the UI's Agents + your preferred embeddings provider if you need it.

Image: `ghcr.io/lucas-santoni/unraid-librechat:latest`

## Install on Unraid

1. Open the Docker tab, click **Add Container**, scroll down to
   **Template repositories**, paste the following URL on its own line, and
   click **Save**:

   ```
   https://github.com/lucas-santoni/unraid-librechat
   ```

2. Back under **Add Container**, pick `librechat` from the template dropdown.
3. Leave defaults; only the **Timezone** field is required. Click **Apply**.
4. Wait 10-20 seconds for first boot, then open the WebUI link.

The container persists everything under `/mnt/user/appdata/librechat/`:

```
mongo/     meili/
uploads/   images/    logs/
.env                 (auto-generated on first boot)
librechat.yaml       (optional, user-provided)
```

## Secrets

Five secrets are auto-generated on first boot and written to
`/mnt/user/appdata/librechat/.env`. You do not need to do anything, but if you
want to provide your own:

| Variable | Generate with |
|---|---|
| `CREDS_KEY` | `openssl rand -hex 32` |
| `CREDS_IV` | `openssl rand -hex 16` |
| `JWT_SECRET` | `openssl rand -hex 32` |
| `JWT_REFRESH_SECRET` | `openssl rand -hex 32` |
| `MEILI_MASTER_KEY` | `openssl rand -base64 32` |

Fill them in the **Advanced** section of the template. They are masked in the
Unraid UI. Values you provide win over any pre-existing `.env` content.

## Custom endpoints (librechat.yaml)

Drop a `librechat.yaml` at `/mnt/user/appdata/librechat/librechat.yaml`. It
gets symlinked into the container at start. Reference:
<https://www.librechat.ai/docs/configuration/librechat_yaml>

## How updates flow

- A scheduled workflow (`watch-upstream.yml`) runs daily at 07:00 UTC and
  checks `danny-avila/LibreChat` for a newer non-prerelease tag.
- If there is one, it opens a PR that bumps the version pin file.
- On that PR, `pr-verify.yml` rebuilds the image and boots it end to end. The
  gates are: Mongo `ping`, Meili `/health`, and LibreChat `/api/config`.
- If all three pass, GitHub auto-merge lands the PR. `build.yml` then publishes
  new tags to GHCR (`latest`, `vX.Y.Z`, `vX.Y`).
- In Unraid, click **Check for Updates** on the Docker tab, then **Apply
  Update** on the `librechat` row.

A faulty upstream release cannot land silently: if the image fails to build
or any service fails to start, the PR stays open with a red check.

### One-time GitHub setup (after you fork or clone)

- Settings -> General -> Pull Requests -> enable **Allow auto-merge**.
- Settings -> Branches -> add a protection rule for `main` requiring
  `pr-verify / build-and-smoke` to pass.
- Actions are enabled by default on new repos; confirm under Settings ->
  Actions -> General.

## Troubleshooting

Open a shell inside the container:

```
docker exec -it librechat bash
```

Per-service logs inside the container:

```
/var/log/s6/librechat-api/current
/var/log/s6/mongod/current
/var/log/s6/meilisearch/current
```

LibreChat application logs live under `/mnt/user/appdata/librechat/logs/`.

List the s6 service state:

```
s6-rc -u list
s6-rc -a list
```

Restart a single service:

```
s6-svc -r /run/service/librechat-api
```

If a process never comes up, check the corresponding `init-*` oneshot
completed. `s6-rc -da list` shows anything that failed.

## Ports

Only **3080** is exposed. Mongo and Meili listen on `127.0.0.1` inside the
container. If you need to expose one for debugging, add `-p 7700:7700` (etc)
to Extra Parameters in the template.

## Renaming the repo

If you fork or transfer this repo, update the hardcoded slug in these places:

- `unraid/librechat.xml` (Repository, Registry, Support, Project, TemplateURL,
  Icon)
- `ca_profile.xml` (Repository, TemplateURL, Project, Support, Icon)
- `README.md` (this file)

CI workflows derive the slug from `github.repository` automatically.

## Credits

- LibreChat, <https://github.com/danny-avila/LibreChat> (MIT)
- s6-overlay, <https://github.com/just-containers/s6-overlay>
- Icon vendored from upstream LibreChat under its MIT license.

## License

MIT. See `LICENSE`.
