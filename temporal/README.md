# Temporal 分布式工作流与事务编排引擎

本项目基于 **[Temporal CLI Dev Server](https://github.com/temporalio/cli)**（`temporalio/temporal:1.9.1`），为微服务体系提供轻量、全功能、开箱即用的工作流编排、Saga 分布式事务与任务调度中心。

---

## 🌟 核心设计与优势

1. **单容器全功能集成 (Zero-Dependency)**：
   - 将 Temporal 核心四大微服务（Frontend、History、Matching、Worker）与 Web UI 监控看板全部打包于单一容器中运行。
   - 使用嵌入式 SQLite 文件存储持久化（`/etc/temporal/temporal.db`），无需前置部署繁重的 Cassandra/PostgreSQL 与 Elasticsearch 集群，极大降低内存占用（仅需 256M~1GB）。
2. **零信任网络暴露面**：
   - **Web UI (8233)**：默认仅绑定本地回环地址 `127.0.0.1:8233`（`${TEMPORAL_UI_BIND}`），避免工作流历史与参数直曝公网；生产环境统一通过 Traefik / Caddy 反向代理网关接入并挂载 Authelia 认证拦截。
   - **gRPC (7233)**：开放供应用层 SDK 客户端与外部 Worker 连接执行任务，支持容器网络直连（`temporal:7233`）。
3. **数据安全与持久化**：
   - 挂载路径具备自包含安全兜底 `${DATA_PATH:-./data/}temporal:/etc/temporal`，容器重置或升级时任务执行历史（Execution History）永不丢失。
4. **原生健康检查探活**：
   - 基于官方 CLI `temporal operator cluster health` 执行集群健康度动态探测，支持秒级自动自愈与故障重启。

---

## 📁 目录结构

```text
docker/temporal/
├── docker-compose.yml # 服务编排（单容器 Dev 模式、本地回环绑定、健康检查、资源限额）
└── README.md          # 架构、连接规范与运维指南
```

---

## 🚀 快速上手与操作指南

### 步骤 1：启动服务

```bash
docker compose up -d

# 查看状态与健康探活
docker compose ps temporal
```

### 步骤 2：Web UI 访问与反向代理

- **本地直接访问**：[http://127.0.0.1:8233](http://127.0.0.1:8233)
- **网关反代接入**（例如 Caddyfile）：

  ```caddyfile
  import proxy-app temporal.{$SITE_ADDRESS} temporal:8233
  ```

### 步骤 3：应用端 SDK 客户端连接

在 Go、Python、TypeScript/Node.js 或 PHP/RoadRunner 中配置客户端：

- **Docker 内部微服务调用**：`temporal:7233`
- **宿主机本地调试连接**：`127.0.0.1:7233`
- **默认命名空间**：`default`

### 步骤 4：常用 CLI 命令

容器内置官方 `temporal` 命令行管理工具：

```bash
# 1. 检查集群健康状态
docker compose exec temporal temporal operator cluster health

# 2. 查看命名空间列表
docker compose exec temporal temporal operator namespace list

# 3. 列出当前所有正在运行或已完成的工作流
docker compose exec temporal temporal workflow list
```
