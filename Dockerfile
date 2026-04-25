# Pinned LSIO Calibre-Web image. Tag includes both the upstream Calibre-Web
# release (0.6.26) and LSIO's build number (-ls379), so we get reproducible
# rebuilds rather than chasing `latest`. Bump deliberately when needed.
FROM lscr.io/linuxserver/calibre-web:0.6.26-ls379

# OpenHost bind-mounts the app's persistent data dir at
# /data/app_data/calibre-web inside the container. The LSIO base image
# expects all of Calibre-Web's writable state at /config (declared as
# VOLUME), and we want our books library at /books. Replace both paths
# with symlinks pointing into the persistent OpenHost mount BEFORE the
# container's first boot, so:
#
#   1. The image's `VOLUME /config` directive resolves to the persistent
#      bind-mounted target rather than spawning an anonymous Podman
#      volume that would silently lose data on container recreate.
#   2. LSIO's init-calibre-web-config and svc-calibre-web see /config
#      and /books at the paths they hard-code, but writes go to the
#      OpenHost-managed persistent storage.
#
# We pre-create /data/app_data/calibre-web/{config,books} so the
# symlinks aren't dangling at image-build time. At runtime, OpenHost's
# bind-mount at /data/app_data/calibre-web will overlay these
# directories and the symlink keeps resolving to the same
# in-container path.
RUN rm -rf /config /books \
 && mkdir -p /data/app_data/calibre-web/config /data/app_data/calibre-web/books \
 && ln -s /data/app_data/calibre-web/config /config \
 && ln -s /data/app_data/calibre-web/books /books

# Runtime additions on top of the LSIO image:
#
#   python3-pip - needed once during build to populate the auth-venv,
#                 then removed to keep the image lean.
#
# python3 + python3-venv are already installed by LSIO (they ship the
# /lsiopy venv that calibre-web itself runs from). sqlite3 is also
# already present (LSIO uses it in init-calibre-web-config to seed
# kepubify paths).
#
# We install PyJWT (with the cryptography extra for RS256) and requests
# inside a *separate* venv at /opt/auth-venv. We deliberately do not
# touch /lsiopy because (a) we don't want our pinned versions colliding
# with calibre-web's own dependency tree, and (b) some LSIO post-init
# steps reach into /lsiopy expecting upstream-only contents.
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3-pip \
 && python3 -m venv /opt/auth-venv \
 && /opt/auth-venv/bin/pip install --no-cache-dir \
        'PyJWT[crypto]==2.9.0' \
        'requests==2.32.3' \
 && apt-get -y purge python3-pip \
 && apt-get -y autoremove \
 && rm -rf /var/lib/apt/lists/* /root/.cache /tmp/*

# Auth-proxy sidecar. Listens on 0.0.0.0:8080 (the openhost.toml-declared
# port) and forwards to Calibre-Web on 127.0.0.1:8083 with an
# X-Openhost-User: admin header stamped when the request carries a valid
# router-signed owner JWT. See auth_proxy.py for the full rationale.
COPY auth_proxy.py /app/auth_proxy.py

# An empty Calibre library schema, taken verbatim from upstream Calibre's
# resources/metadata_sqlite.sql. We materialise an empty metadata.db at
# /books on first boot so calibre-web's "DB Location is not Valid" check
# passes and the library configuration step in the wizard is unnecessary.
COPY calibre_metadata_sqlite.sql /app/calibre_metadata_sqlite.sql

# OpenHost-specific s6 services:
#
#   init-openhost-calibre-web (oneshot)
#       Runs after init-calibre-web-config (which seeds /config/app.db).
#       Creates the empty Calibre library, patches app.db to point at it
#       and to enable reverse-proxy header login, and randomises the
#       admin password on first boot.
#
#   svc-auth-proxy (longrun)
#       Starts after svc-calibre-web is ready. Runs auth_proxy.py on
#       0.0.0.0:8080.
#
# The `root/` tree mirrors LSIO's convention so we can drop in service
# definitions without overlay scripting. Each service has a `type` file,
# a `run` script, and `dependencies.d/<dep>` markers; the
# `user/contents.d/<service>` empty files enable each service in the
# generated s6 bundle.
COPY root/ /

# Ensure the run scripts are executable (COPY preserves bits, but it
# doesn't hurt to be explicit, and CI/git-on-Windows checkouts may strip
# them).
RUN chmod +x \
        /etc/s6-overlay/s6-rc.d/init-openhost-calibre-web/run \
        /etc/s6-overlay/s6-rc.d/svc-auth-proxy/run

# The base image already declares EXPOSE 8083, but we listen externally
# on 8080 (the auth-proxy port). Add 8080 to the exposed-port metadata
# so `docker inspect` lines up with reality.
EXPOSE 8080
