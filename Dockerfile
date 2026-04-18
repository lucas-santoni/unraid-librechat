# syntax=docker/dockerfile:1.7

ARG LIBRECHAT_REF
ARG LIBRECHAT_SHA
ARG S6_OVERLAY_VERSION=3.2.2.0
ARG MEILI_VERSION=v1.42.1
ARG NODE_MAJOR=20
ARG NODE_MAX_OLD_SPACE_SIZE=6144

###############################################################################
# Stage 1 - Build LibreChat (replicates upstream Dockerfile.multi api-build)
###############################################################################
FROM node:20-bookworm-slim AS librechat-builder

ARG LIBRECHAT_SHA
ARG NODE_MAX_OLD_SPACE_SIZE

RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN git clone --filter=blob:none https://github.com/danny-avila/LibreChat.git /app \
 && git -C /app checkout --detach "${LIBRECHAT_SHA}"

RUN npm config set fetch-retry-maxtimeout 600000 \
 && npm config set fetch-retries 5 \
 && npm config set fetch-retry-mintimeout 15000 \
 && npm ci

RUN cd /app/packages/data-provider && npm run build \
 && cd /app/packages/data-schemas && npm run build \
 && cd /app/packages/api && npm run build \
 && cd /app/packages/client && npm run build

ENV NODE_OPTIONS="--max-old-space-size=${NODE_MAX_OLD_SPACE_SIZE}"
RUN cd /app/client && npm run build
ENV NODE_OPTIONS=""

RUN rm -rf /app/node_modules \
 && npm ci --omit=dev

# Fetch uv binary for MCP support (matches upstream Dockerfile.multi)
COPY --from=ghcr.io/astral-sh/uv:0.6.13 /uv /uvx /out/bin/

###############################################################################
# Stage 2 - Runtime
###############################################################################
FROM debian:bookworm-slim AS runtime

ARG TARGETARCH
ARG S6_OVERLAY_VERSION
ARG MEILI_VERSION
ARG NODE_MAJOR

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC \
    PUID=99 \
    PGID=100 \
    NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=3080 \
    MONGO_URI=mongodb://127.0.0.1:27017/LibreChat \
    MEILI_HOST=http://127.0.0.1:7700 \
    MEILI_NO_ANALYTICS=true \
    ALLOW_REGISTRATION=true \
    MONGO_WIREDTIGER_CACHE_GB=0.5 \
    MEILI_MAX_INDEXING_MEMORY=512MB \
    NODE_MAX_OLD_SPACE_SIZE=2048 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_KEEP_ENV=1 \
    S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg xz-utils tini tzdata \
      procps netcat-openbsd jq openssl passwd \
      libjemalloc2 \
 && rm -rf /var/lib/apt/lists/*

# NodeSource (Node 20)
RUN curl -fsSL "https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key" \
      | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
      > /etc/apt/sources.list.d/nodesource.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/*

# MongoDB - binaries pulled from the official image so this works on amd64 and arm64.
# MongoDB does not publish arm64 packages in their Debian apt repo.
COPY --from=mongo:7-jammy /usr/bin/mongod   /usr/bin/mongod
COPY --from=mongo:7-jammy /usr/bin/mongosh  /usr/bin/mongosh
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libssl3 libcurl4 libsnappy1v5 \
 && rm -rf /var/lib/apt/lists/*

# MeiliSearch binary
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
      amd64) meili_asset="meilisearch-linux-amd64" ;; \
      arm64) meili_asset="meilisearch-linux-aarch64" ;; \
      *)     echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /usr/local/bin/meilisearch \
      "https://github.com/meilisearch/meilisearch/releases/download/${MEILI_VERSION}/${meili_asset}"; \
    chmod +x /usr/local/bin/meilisearch; \
    /usr/local/bin/meilisearch --version

# s6-overlay v3
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
      amd64) s6_arch="x86_64" ;; \
      arm64) s6_arch="aarch64" ;; \
      *)     echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/s6-noarch.tar.xz \
      "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz"; \
    curl -fsSL -o /tmp/s6-arch.tar.xz \
      "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${s6_arch}.tar.xz"; \
    tar -C / -Jxpf /tmp/s6-noarch.tar.xz; \
    tar -C / -Jxpf /tmp/s6-arch.tar.xz; \
    rm -f /tmp/s6-noarch.tar.xz /tmp/s6-arch.tar.xz

# Runtime user (uid 99 / gid 100, Unraid nobody:users). PUID/PGID remap at boot.
RUN set -eux; \
    if ! getent group users >/dev/null; then groupadd -g 100 users; fi; \
    useradd -o -u 99 -g users -d /config -M -s /bin/bash librechat

# LibreChat artifacts (chown at COPY time; avoids a multi-minute RUN chown and layer duplication)
COPY --from=librechat-builder --chown=librechat:users /app /app
COPY --from=librechat-builder /out/bin/uv /usr/local/bin/uv
COPY --from=librechat-builder /out/bin/uvx /usr/local/bin/uvx

# s6 service tree and init scripts
COPY rootfs/ /

# Ensure scripts are executable
RUN find /etc/s6-overlay -type f \( -name run -o -name up -o -name finish \) -exec chmod +x {} + \
 && find /etc/s6-overlay/scripts -type f -exec chmod +x {} + \
 && find /usr/local/bin -type f -exec chmod +x {} +

EXPOSE 3080
ENTRYPOINT ["/init"]
