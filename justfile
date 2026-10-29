set shell := ["bash", "-uc"]
set dotenv-load := false

compose_file := "docker-compose.yml"
env_file := if path_exists(justfile_directory() + "/.env") == "true" { ".env" } else { ".env.example" }
compose := "docker compose -f " + compose_file + " --env-file " + env_file

default:
    @just --list

# 初始化本地运行环境与 Git hooks
[group: 'init']
init:
    @[ -f .env ] || cp .env.example .env
    @mkdir -p data logs
    @./scripts/garage/render-config.sh
    @command -v lefthook >/dev/null 2>&1 && lefthook install || true

# 签发本地受信通配符证书
[group: 'init']
cert domain="test.local":
    @./scripts/certs/generate.sh "{{domain}}"

# 启动服务 (默认后台运行)
[group: 'services']
up service="":
    @./scripts/garage/render-config.sh
    {{compose}} up -d {{service}}

# 停止服务 (支持 flags="-v")
[group: 'services']
down flags="":
    {{compose}} down {{flags}}

# 重启服务
[group: 'services']
restart service="":
    {{compose}} restart {{service}}

# 查看容器运行状态
[group: 'services']
ps service="":
    {{compose}} ps {{service}}

# 跟踪容器实时日志
[group: 'services']
logs service="" tail="100":
    {{compose}} logs -f --tail={{tail}} {{service}}

# 拉取最新镜像
[group: 'services']
pull service="":
    {{compose}} pull {{service}}

# 构建自定义镜像
[group: 'services']
build service="":
    {{compose}} build {{service}}

# 执行全量代码与配置静态检查
[group: 'quality']
lint:
    {{compose}} config --quiet
    hadolint postgres/Dockerfile dnsmasq/Dockerfile simulator/Dockerfile
    find scripts/ postgres/docker-entrypoint-initdb.d/ -name "*.sh" -exec shellcheck {} +
    actionlint
    rumdl check

# 校验 Compose 配置结构 (供 Git Hook 专用)
[private]
lint-compose:
    {{compose}} config --quiet

# 格式化脚本与文档
[group: 'quality']
fmt:
    find scripts/ postgres/docker-entrypoint-initdb.d/ -name "*.sh" -exec shfmt -w {} +
    rumdl fmt

# 渲染 Garage S3 配置文件 (根据 .env 自动生成 garage.toml)
[group: 'garage']
garage-config:
    @./scripts/garage/render-config.sh

# 初始化 Garage S3 默认存储桶与访问密钥
[group: 'garage']
garage-init:
    @./scripts/garage/init-buckets.sh

# 初始化 OpenBao 集群并导出解封密钥
[group: 'security']
bao-init:
    @./scripts/openbao/init.sh

# 读取本地密钥解封 OpenBao 容器
[group: 'security']
bao-unseal:
    @./scripts/openbao/unseal.sh

# 容器内直通执行 bao CLI (自动注入 Root Token)
[group: 'security']
bao-cli +args:
    @./scripts/openbao/cli.sh {{args}}

# 批量导入 .env 敏感变量至 OpenBao KV 引擎
[group: 'security']
bao-import:
    @./scripts/openbao/import-env.sh

# 初始化 InfluxDB 3 数据库与 Token
[group: 'iot']
iot-init:
    @./scripts/iot/init-influx.sh

# 启动 IoT 全栈服务 (Mosquitto + InfluxDB + Telegraf + Simulator)
[group: 'iot']
iot-up:
    {{compose}} --profile iot up -d mosquitto influxdb influxdb-ui telegraf simulator
    @just iot-init

# 停止 IoT 服务组件
[group: 'iot']
iot-down flags="":
    {{compose}} --profile iot stop mosquitto influxdb influxdb-ui telegraf simulator {{flags}}

# 验证 IoT 完整数据链路连通性与入库状态
[group: 'iot']
iot-test:
    @./scripts/iot/test-pipeline.sh
