# Garage 轻量级分布式 S3 对象存储与管理套件

本项目采用 **[Garage](https://garagehq.deuxfleurs.fr/)**（Rust 编写的轻量级、去中心化兼容 Amazon S3 协议的高可用对象存储系统）配合 **[Garage-WebUI](https://github.com/khairul169/garage-webui)**（纯静态极简控制台），为集群内部的 OpenObserve、数据库与系统备份归档、应用上传及静态媒体资源提供高效、低开销、可视化管理的一体化对象存储基座。

---

## 🌟 核心设计与生产最佳实践

1. **统一自包含工程结构 (Single Source of Truth)**：
   - 将 `garage`（S3 存储守护进程）与 `garage-webui`（可视化控制台）统筹编排在同一目录下，共享同级 `./garage.toml:ro` 配置文件作为配置真理源，彻底消除跨目录挂载与敏感令牌重复维护。
2. **LMDB 元数据持久性与容灾加固**：
   - 启用 `metadata_auto_snapshot_interval = "6h"` 定时自动快照，保障在宿主机异常断电、强行杀进程或节点重启时元数据可快速回滚自愈，根治 LMDB 引擎在极端场景下的损坏隐患。
3. **敏感凭据分层安全覆盖**：
   - 核心令牌（`GARAGE_RPC_SECRET`、`GARAGE_ADMIN_TOKEN`、`GARAGE_METRICS_TOKEN`）支持由 `.env` 环境变量动态重写，兼顾本地开箱即用与生产密钥防泄露治理。
4. **精简云原生镜像与 Scratch 适配优化**：
   - **Garage**：直接运行官方标准镜像 `dxflrs/garage:v2.4.1`，剔除冗余自建 Dockerfile，配置内置状态探活 `/garage status`。
   - **Garage-WebUI**：运行官方轻量镜像 `khairul169/garage-webui:1.1.0`（基于 `scratch` 构建）。
   - **关键优化项**：针对 `scratch` 容器缺失 `/tmp` 目录导致大文件分片上传报错（Go `ParseMultipartForm`）的问题，显式挂载 `tmpfs: - /tmp` 内存虚拟盘。不仅彻底消除上传异常，还显著提升并发写性能并保护物理磁盘。
5. **特性裁剪与最小攻击面**：
   - 默认裁剪未在集群中实际使用的 `[s3_web]`（静态网站托管）与 `[k2v_api]`（实验性 KV 引擎），关闭未使用的监听套接字，降低容器攻击面与内存占用。
   - 全容器注入 `no-new-privileges:true`，杜绝提权风险。
6. **零信任网络暴露面**：
   - **S3 API (`3900`)**：默认绑定 `127.0.0.1:3900`，外部请求统一由反向代理网关（Traefik / Caddy）终结 SSL 接入。
   - **RPC (`3901`) & Admin API (`3903`)**：仅本地回环可达，严格阻断集群内部同步与管理端点向公网暴露。
   - **WebUI 控制台 (`3909`)**：默认绑定 `127.0.0.1:3909`，生产环境通过反向代理接入并强制要求 Authelia / SSO 统一鉴权。
7. **自动化引导与生命周期感知**：
   - 容器启动参数 `--single-node --default-bucket` 配合环境变量 `GARAGE_DEFAULT_ACCESS_KEY` / `GARAGE_DEFAULT_SECRET_KEY`，实现开箱即用的自动化集群引导。
   - `garage-webui` 通过 `depends_on: garage: condition: service_healthy` 精准感知底层存储就绪状态，杜绝启动时 Admin API 拒绝连接的问题。
8. **轻量高性能资源控制**：
   - `garage`：限制 CPU: 2.0，内存上限 1GB（预留 128MB）。
   - `garage-webui`：限制 CPU: 0.5，内存上限 256MB（预留 64MB）。

---

## 📁 目录结构

```text
docker/garage/
├── docker-compose.yml # 统一服务编排 (Garage S3 核心 + WebUI 控制台、端口隔离、tmpfs、资源限制)
├── garage.toml        # 核心服务配置 (LMDB 引擎、6h 自动快照、S3 监听、管理令牌)
└── README.md          # 架构指南、CLI 管理指令、S3 接入规范与反代防护
```

---

## 🚀 快速上手与操作指南

### 步骤 1：启动服务

```bash
docker compose up -d

# 查看各容器健康与就绪状态
docker compose ps
```

### 步骤 2：访问 WebUI 可视化控制台

- **本地直连**：浏览器访问 `http://127.0.0.1:3909`
- **后台能力**：
  - **Bucket 管理**：在线新建、删除存储桶，配置公开访问与网站托管。
  - **对象浏览**：在线上传、预览、下载和清理文件。
  - **凭据授权**：创建微服务独立的 Access Key / Secret Key 并分配对应 Bucket 权限。

### 步骤 3：常用 CLI 管理命令

可通过底层容器内置的 `/garage` 二进制进行底层集群管理与排障：

```bash
# 1. 检查节点健康与存储拓扑
docker compose exec garage /garage status

# 2. 列出所有存储桶 (Buckets)
docker compose exec garage /garage bucket list

# 3. 列出访问密钥 (Access Keys)
docker compose exec garage /garage key list

# 4. 创建新存储桶
docker compose exec garage /garage bucket create my-bucket

# 5. 手动触发一次元数据快照
docker compose exec garage /garage meta snapshot
```

### 步骤 4：微服务连接规范 (S3 Client)

同 Docker 网络内部微服务（如 OpenObserve、应用上传组件等）连接参数：

- **Endpoint**: `http://garage:3900`
- **Region**: `garage`
- **Access Key**: `${GARAGE_DEFAULT_ACCESS_KEY}`
- **Secret Key**: `${GARAGE_DEFAULT_SECRET_KEY}`
- **Path Style**: 启用 Path-Style URL (`true`)

---

## 📊 Prometheus 监控与指标采集

Garage 原生在 `3903` 管理端口暴露出 Prometheus 格式的运行监控指标（包括读写 QPS、存储用量、延迟分位数等）：

- **Scrape 地址**：`http://garage:3903/metrics`
- **鉴权要求**：配置了 `metrics_require_token = true` 时，采集端（如 Prometheus 或 OpenTelemetry Collector）需携带 Bearer Token：

  ```yaml
  authorization:
    type: Bearer
    credentials: "${GARAGE_METRICS_TOKEN}"
  ```

---

## 🔒 生产环境反向代理与安全防护示例

为保障 WebUI 与 S3 接口安全，推荐在反向代理（Caddy / Traefik）侧配置接入规则：

```caddy
# 1. WebUI 控制台 (前置 Authelia 单点登录保护)
garage-ui.yourdomain.com {
    forward_auth authelia:9091 {
        uri /api/authz/forward-auth
        copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
    }
    reverse_proxy garage-webui:3909
}

# 2. S3 API 终端 (供公网客户端或外部工具直连)
s3.yourdomain.com {
    reverse_proxy garage:3900
}
```
