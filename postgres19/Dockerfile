ARG POSTGRES_VERSION=19.0-trixie
FROM postgres:${POSTGRES_VERSION}
LABEL maintainer="seaside <531773730@qq.com>"

ARG TZ=Asia/Shanghai

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    && curl -fSsL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ARG PGCRON_VERSION=1.6.8-1.pgdg13+3
ARG POSTGIS_VERSION=3.7.0+dfsg-1.pgdg13+2
ARG PGVECTOR_VERSION=0.8.7-1.pgdg13+2
# pgroonga 不在 PGDG 源，需额外引入 Groonga 官方源；PG19 包暂未发布，故默认关闭
ARG PGROONGA_VERSION=4.1.0-1

# 扩展开关，false 可裁掉对应扩展
ARG WITH_PGROONGA=false
ARG WITH_POSTGIS=true
ARG WITH_PGVECTOR=true
ARG WITH_PGCRON=false

RUN apt-get update && apt-get install -y --no-install-recommends \
    tzdata \
    && if [ "$WITH_POSTGIS" = "true" ]; then apt-get install -y --no-install-recommends postgresql-19-postgis-3="${POSTGIS_VERSION}"; fi \
    && if [ "$WITH_PGVECTOR" = "true" ]; then apt-get install -y --no-install-recommends postgresql-19-pgvector="${PGVECTOR_VERSION}"; fi \
    && if [ "$WITH_PGCRON" = "true" ]; then apt-get install -y --no-install-recommends postgresql-19-cron="${PGCRON_VERSION}"; fi \
    && if [ "$WITH_PGROONGA" = "true" ]; then \
    curl -fsSLo /tmp/groonga.deb https://packages.groonga.org/debian/groonga-apt-source-latest-trixie.deb \
    && apt-get install -y /tmp/groonga.deb && apt-get update \
    && apt-get install -y --no-install-recommends postgresql-19-pgdg-pgroonga="${PGROONGA_VERSION}" \
    && rm /tmp/groonga.deb; \
    fi \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/TZ

COPY postgresql.conf /etc/postgresql/postgresql.conf
# pg_cron 未安装时必须从 preload 移除，否则 Postgres 启动即失败（pgroonga 无需 preload）
RUN if [ "$WITH_PGCRON" != "true" ]; then sed -i 's/pg_cron,//' /etc/postgresql/postgresql.conf; fi

COPY docker-entrypoint-initdb.d/ /docker-entrypoint-initdb.d/

ENV POSTGRES_CONFIG_FILE=/etc/postgresql/postgresql.conf

CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]

HEALTHCHECK --interval=60s --timeout=10s --retries=5 --start-period=60s \
    CMD ["sh", "-c", "pg_isready -d ${POSTGRES_DB:-postgres} -U ${POSTGRES_USER:-postgres}"]

EXPOSE 5432
