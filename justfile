set shell := ["bash", "-uc"]
set dotenv-load := false

compose_file := "docker-compose.yml"
env_file := if path_exists(justfile_directory() + "/.env") == "true" { ".env" } else { ".env.example" }
compose := "docker compose -f " + compose_file + " --env-file " + env_file

# 列出所有可用运维任务与指令
default:
    @just --list

# 初始化开发环境 (创建 .env 与必要持久化目录，安装 Git hooks)
init:
    @if [ ! -f .env ]; then \
        echo "Creating .env from .env.example..."; \
        cp .env.example .env; \
    else \
        echo ".env already exists, skipping copy."; \
    fi
    @mkdir -p data logs
    @if command -v lefthook >/dev/null 2>&1; then \
        echo "Installing lefthook git hooks..."; \
        lefthook install; \
    fi
    @echo "Environment initialized successfully!"

# ------------------------------------------------------------------------------
# 容器集群生命周期运维 (Cluster Lifecycle Management)
# ------------------------------------------------------------------------------

# 后台启动全部服务或指定服务 (例如: just up 或 just up postgres)
up service="":
    {{compose}} up -d {{service}}

# 停止并移除所有容器及默认网络
down:
    {{compose}} down

# 停止并移除所有容器、默认网络以及关联的持久化卷 (高危操作)
down-v:
    @echo "WARNING: Removing containers and associated volumes..."
    {{compose}} down -v

# 重启全部服务或指定服务 (例如: just restart valkey)
restart service="":
    {{compose}} restart {{service}}

# 启动已停止的服务
start service="":
    {{compose}} start {{service}}

# 停止运行中的服务
stop service="":
    {{compose}} stop {{service}}

# 查看当前运行的服务状态
ps service="":
    {{compose}} ps {{service}}

# 实时跟踪容器日志 (默认最近 100 行，例如: just logs traefik)
logs service="" tail="100":
    {{compose}} logs -f --tail={{tail}} {{service}}

# 查看容器运行进程
top service="":
    {{compose}} top {{service}}

# 拉取上游最新镜像
pull service="":
    {{compose}} pull {{service}}

# 构建本仓库自定义镜像 (crowdsec, postgres)
build service="":
    {{compose}} build {{service}}

# 启动交互式终端容器管理面板 (lazydocker)
ui:
    @if command -v lazydocker >/dev/null 2>&1; then \
        lazydocker; \
    else \
        echo "lazydocker not found. Run 'mise install' to install it."; \
    fi

# ------------------------------------------------------------------------------
# 镜像分析与安全漏洞扫描 (Security & Image Inspection)
# ------------------------------------------------------------------------------

# 扫描 Compose 编排安全基线与配置风险 (trivy)
scan:
    @if command -v trivy >/dev/null 2>&1; then \
        trivy config .; \
    else \
        echo "trivy not found. Run 'mise install' to install it."; \
    fi

# 扫描指定镜像的安全漏洞 CVE (例如: just scan-image postgres)
scan-image image:
    @if command -v trivy >/dev/null 2>&1; then \
        trivy image {{image}}; \
    else \
        echo "trivy not found. Run 'mise install' to install it."; \
    fi

# 交互式分析指定镜像分层结构与空间浪费 (dive，例如: just dive crowdsec)
dive image:
    @if command -v dive >/dev/null 2>&1; then \
        dive {{image}}; \
    else \
        echo "dive not found. Run 'mise install' to install it."; \
    fi


# ------------------------------------------------------------------------------
# 静态质量检查与校验门禁 (Quality Gates & Linting)
# ------------------------------------------------------------------------------

# 运行全量静态检查 (Compose, Dockerfile, Shell, Workflows, Markdown)
lint: lint-compose lint-dockerfile lint-shell lint-actions lint-md

# 校验 Docker Compose 编排语法规范
lint-compose:
    @echo "Validating Docker Compose with {{env_file}}..."
    @{{compose}} config --quiet
    @echo "Docker Compose configuration is valid."

# 检查 Dockerfile 规范 (hadolint)
lint-dockerfile:
    @hadolint crowdsec/Dockerfile postgres/Dockerfile

# Shell 脚本静态分析 (shellcheck)
lint-shell:
    @find postgres/docker-entrypoint-initdb.d/ -name "*.sh" -exec shellcheck {} +

# GitHub Actions 工作流语法分析 (actionlint)
lint-actions:
    @actionlint

# Markdown 格式规范检测 (rumdl)
lint-md:
    @rumdl check

# 输出 Compose 解析后的最终合并配置 (可指定特定服务)
validate-compose service="":
    {{compose}} config {{service}}

# 校验别名 (对齐 CI 与通用约定)
validate: lint
check: lint

# ------------------------------------------------------------------------------
# 自动化格式化与修复 (Code Formatting & Fixing)
# ------------------------------------------------------------------------------

# 自动格式化所有 Shell 脚本与 Markdown 文档
fmt: fmt-shell fmt-md

# 格式化 Shell 脚本 (shfmt)
fmt-shell:
    @find postgres/docker-entrypoint-initdb.d/ -name "*.sh" -exec shfmt -w {} +

# 格式化 Markdown 文档 (rumdl)
fmt-md:
    @rumdl fmt

# 自动修复全量格式 (fmt 别名)
fix: fmt
