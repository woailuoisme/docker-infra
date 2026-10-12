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
    @./scripts/garage/init-buckets.sh

# 签发本地受信通配符证书
cert domain="test.local":
    @./scripts/certs/generate.sh "{{domain}}"

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
    hadolint postgres/Dockerfile dnsmasq/Dockerfile simulator/Dockerfile

lint-shell:
    find scripts/ postgres/docker-entrypoint-initdb.d/ -name "*.sh" -exec shellcheck {} +

lint-actions:
    actionlint

lint-md:
    rumdl check

# 格式化代码与文档
fmt: fmt-shell fmt-md

fmt-shell:
    find scripts/ postgres/docker-entrypoint-initdb.d/ -name "*.sh" -exec shfmt -w {} +

fmt-md:
    rumdl fmt

# --- OpenBao 密钥与安全管理 ---
# 初始化 OpenBao 集群并导出解封密钥至 open-bao/.keys.json
bao-init:
    @./scripts/openbao/init.sh

# 读取本地密钥解封 OpenBao 容器
bao-unseal:
    @./scripts/openbao/unseal.sh

# 查看 OpenBao 容器运行与解封状态
bao-status:
    @docker exec openbao bao status

# 容器内免密直通执行 bao CLI 命令 (自动注入 Root Token)
bao-cli +args:
    @./scripts/openbao/cli.sh {{args}}

# 批量导入 .env 敏感变量至 OpenBao KV 密钥引擎
bao-import-env:
    @./scripts/openbao/import-env.sh

# --- IoT 物联网与时序数据栈 (IoT & Time-Series Stack) ---
# 初始化 InfluxDB 3 时序数据库与 Token 校验
init-iot:
    @./scripts/iot/init-influx.sh

# 启动 IoT 全栈服务 (Mosquitto + InfluxDB + Telegraf + Simulator)
iot-up:
    {{compose}} --profile iot up -d mosquitto influxdb influxdb-ui telegraf simulator
    @just init-iot

# 停止 IoT 服务组件
iot-down flags="":
    {{compose}} --profile iot stop mosquitto influxdb influxdb-ui telegraf simulator {{flags}}

# 查看 IoT 容器运行与健康状态
iot-status:
    {{compose}} --profile iot ps mosquitto influxdb influxdb-ui telegraf simulator

# 跟踪 IoT 模拟器集群遥测日志
iot-sim-logs tail="100":
    {{compose}} logs -f --tail={{tail}} simulator

# 跟踪 Telegraf 消费与入库日志
iot-telegraf-logs tail="100":
    {{compose}} logs -f --tail={{tail}} telegraf

# 验证 IoT 完整链路连通性与 InfluxDB 数据入库状态
iot-test:
    @./scripts/iot/test-pipeline.sh


