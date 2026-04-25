# openhost-calibre-web

[Calibre-Web](https://github.com/janeczku/calibre-web) packaged for OpenHost.
Calibre-Web is a Flask web app that serves an existing Calibre ebook library
over the web with a clean reading UI, OPDS feed, sync support, and
admin/user management.

## Features

- **Owner SSO via OpenHost.** Owners are auto-logged-in as the Calibre-Web
  `admin` user via the bundled auth-proxy sidecar. The proxy verifies the
  `zone_auth` JWT signed by the OpenHost router (RS256 against the
  router's published JWKS) and stamps `X-Openhost-User: admin` on the
  upstream request when the claim `sub == "owner"` checks out.
- **Username/password fallback for invited readers.** Calibre-Web's normal
  login form at `/login` still works, so you can mint shared accounts for
  family members or co-owners who don't have an OpenHost identity. The
  default `admin` password is randomised at first boot — see
  `admin-password.txt` below for recovery.
- **Empty library on first boot.** A blank Calibre library is seeded at
  `/books/metadata.db` so Calibre-Web skips its setup wizard and lands you
  on the (empty) book list immediately. Drop EPUBs and PDFs in via the
  web UI's upload button or by writing them to the persistent volume.
- **Persistent state.** Both `app.db` (settings, users, downloads) and
  the Calibre library files live under `OPENHOST_APP_DATA_DIR` and
  survive container rebuilds.

## Persistent layout

OpenHost bind-mounts the app's data directory at `/data/app_data/calibre-web`
inside the container. The image symlinks the LSIO-expected paths into it:

```
/config/                  -> /data/app_data/calibre-web/config/
  app.db                    Calibre-Web settings + users (SQLite)
  admin-password.txt        Generated random admin password (recovery)
  .openhost-initialised     Sentinel; presence means first-boot done
  ...                       Other LSIO-managed config files

/books/                   -> /data/app_data/calibre-web/books/
  metadata.db               Calibre library catalogue (SQLite)
  <Author>/<Title>/...      Book files added through the web UI
```

To populate the library by hand, copy a complete Calibre directory tree
into `/data/app_data/calibre-web/books/` (preserving `metadata.db` and
all author/title subdirectories) and reload the app from the OpenHost
admin UI.

## Login

- **Owner.** Browse to the app URL while signed in to OpenHost as the
  zone owner. The auth-proxy will recognise the `zone_auth` cookie and
  log you in as `admin` automatically.
- **Other users.** Visit `/login` and enter the username/password of an
  account you've created via the admin UI ("Users" -> "Create New
  User").
- **Recovery.** The randomised admin password is stored in
  `/data/app_data/calibre-web/config/admin-password.txt` (mode 0600,
  owned by the container's PUID). If the auth-proxy ever gets wedged
  and you can't log in via SSO, this is your escape hatch.

## Manifest

| key | value | rationale |
|---|---|---|
| `port` | 8080 | The auth-proxy sidecar's listen port. Calibre-Web itself runs on `127.0.0.1:8083` inside the container. |
| `health_check` | `/robots.txt` | Cheapest 200-OK route Calibre-Web serves to anonymous traffic. |
| `public_paths` | `["/"]` | Calibre-Web mediates auth itself, so the entire app needs to be reachable. |
| `app_data` | `true` | Library files + settings db. |
| `memory_mb` | 768 | Calibre-Web + ImageMagick (cover thumbnails) + Python. |
| `cpu_millicores` | 500 | Spikes during cover thumbnail generation. |

## Caveats

- **Library starts empty.** If you have an existing Calibre library on
  another machine, you'll need to copy `metadata.db` and the book
  subdirectories into `/data/app_data/calibre-web/books/` yourself
  (e.g. via scp + the OpenHost host shell, or by mounting the volume
  on the host).
- **Ebook conversion is not enabled.** The LSIO image supports a Calibre
  Docker mod (`linuxserver/mods:universal-calibre`) that adds the Calibre
  conversion binaries. We don't pull it in by default — it more than
  doubles the image size. If you need format conversion (EPUB -> MOBI,
  etc.), add `DOCKER_MODS=linuxserver/mods:universal-calibre` to the
  container's environment by editing `Dockerfile` and rebuilding.
- **No OAuth providers.** Calibre-Web's built-in Google/GitHub OAuth
  login is supported by the upstream image but not pre-configured. If
  you need those, configure them through the admin UI; secrets persist
  in `app.db`.
- **Reverse-proxy auto-registration is OFF.** Unlike Forgejo, Calibre-Web
  does not auto-create users for unknown reverse-proxy headers
  (see `cps/usermanagement.py:load_user_from_reverse_proxy_header`).
  The owner is mapped to the pre-existing `admin` account; non-owners
  cannot use SSO and must use a Calibre-Web-local password.

## Reference

- Upstream Docker image: <https://hub.docker.com/r/linuxserver/calibre-web>
- Calibre-Web source: <https://github.com/janeczku/calibre-web>
- Empty-library schema (vendored at `calibre_metadata_sqlite.sql`):
  <https://github.com/kovidgoyal/calibre/blob/master/resources/metadata_sqlite.sql>
