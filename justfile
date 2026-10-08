set shell := ["bash", "-uc"]
set dotenv-load := false

compose_file := "docker-compose.yml"
env_file := if path_exists(justfile_directory() + "/.env") == "true" { ".env" } else { ".env.example" }
compose := "docker compose -f " + compose_file + " --env-file " + env_file

default:
    @just --list

# 初始化本地环境与 hooks
init:
    @[ -f .env ] || cp .env.example .env
    @mkdir -p data logs
    @command -v lefthook >/dev/null 2>&1 && lefthook install || true

# 初始化 Garage S3 存储桶与访问密钥 (default & bgin)
init-garage:
    @./garage/scripts/init-buckets.sh

# 签发本地受信通配符证书
cert domain="test.local":
    @mkdir -p data/ssl/live/{{domain}}
    mkcert -install
    mkcert -cert-file data/ssl/live/{{domain}}/fullchain.pem -key-file data/ssl/live/{{domain}}/privkey.pem "{{domain}}" "*.{{domain}}" "*.s3.{{domain}}"

# 启动服务
up service="":
    {{compose}} up -d {{service}}

# 停止服务 (可传 flags="-v")
down flags="":
    {{compose}} down {{flags}}

# 重启服务
restart service="":
    {{compose}} restart {{service}}

# 查看服务状态
ps service="":
    {{compose}} ps {{service}}

# 跟踪服务日志
logs service="" tail="100":
    {{compose}} logs -f --tail={{tail}} {{service}}

# 构建自定义镜像
build service="":
    {{compose}} build {{service}}

# 渲染解析后的 Compose 配置
config service="":
    {{compose}} config {{service}}

# 终端容器管理面板
ui:
    lazydocker

# Compose 配置风险扫描
scan:
    trivy config .

# 全量代码与配置检查
lint: lint-compose lint-dockerfile lint-shell lint-actions lint-md

lint-compose:
    {{compose}} config --quiet

lint-dockerfile:
    hadolint crowdsec/Dockerfile postgres/Dockerfile dnsmasq/Dockerfile

lint-shell:
    find postgres/docker-entrypoint-initdb.d/ garage/scripts/ -name "*.sh" -exec shellcheck {} +

lint-actions:
    actionlint

lint-md:
    rumdl check

# 格式化代码与文档
fmt: fmt-shell fmt-md

fmt-shell:
    find postgres/docker-entrypoint-initdb.d/ garage/scripts/ -name "*.sh" -exec shfmt -w {} +

fmt-md:
    rumdl fmt
