ARG CADDY_VERSION=2.11

FROM caddy:${CADDY_VERSION}-builder-alpine AS builder

RUN xcaddy build \
    --output /usr/bin/caddy \
    --with github.com/caddyserver/transform-encoder \
    --with github.com/mholt/caddy-l4@v0.1.3 \
    --with github.com/caddy-dns/cloudflare@v0.2.4 \
    --with github.com/caddy-dns/alidns@v1.0.29 \
    --with github.com/caddy-dns/tencentcloud@v0.4.3 \
    --with github.com/caddyserver/replace-response \
    --with github.com/mholt/caddy-ratelimit@v0.1.0 \
    --with github.com/sagikazarmark/caddy-fs-s3@v0.12.0 \
    --with github.com/corazawaf/coraza-caddy/v2@v2.6.2 \
    --with github.com/hslatman/caddy-crowdsec-bouncer/http@v0.15.0 \
    --with github.com/hslatman/caddy-crowdsec-bouncer/layer4@v0.15.0 \
    --with github.com/sablierapp/sablier-caddy-plugin@v1.0.2 \
    --with github.com/darkweak/souin/plugins/caddy@v1.7.10 \
    --with github.com/darkweak/storages/badger/caddy@v0.0.23 \
    --with github.com/darkweak/storages/otter/caddy@v0.0.23 \
    --with github.com/darkweak/storages/redis/caddy@v0.0.23

FROM caddy:${CADDY_VERSION}-alpine
LABEL maintainer="seaside <531773730@qq.com>"

ENV TZ=Asia/Shanghai

RUN apk add --no-cache nss-tools tzdata curl && \
    ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo "${TZ}" > /etc/timezone

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
