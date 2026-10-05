# OpenObserve 云原生可观测性平台

本项目采用 **[OpenObserve](https://github.com/openobserve/openobserve)**（Rust 构建的高性能轻量级可观测性平台），为全栈应用提供统一的日志（Logs）、指标（Metrics）与链路追踪（Traces）存储与分析检索面板。

---

## 🌟 核心设计与优势

1. **云原生存算分离架构 (Storage-Compute Separation)**：
   - 遥测数据切片采用标准 Apache Parquet 列式存储格式，直接持久化写入集群内部的 **Garage S3** 对象存储服务，具备 10 倍以上的压缩率和极低存储成本。
   - 本地 `${DATA_PATH:-./data/}open-observe` 仅作为元数据持久化和写入缓冲缓存使用。
2. **极致轻量全功能一体化**：
   - 声明 `ZO_LOCAL_MODE=true`、`ZO_NODE_ROLE=all`，单容器进程合并运行 Ingester、Querier、Compactor 与 Router 全部角色，相比传统 ELK (Elasticsearch/Logstash/Kibana) 堆栈节省 90% 以上的内存开销。
3. **零信任网络暴露面**：
   - Web 与 API 端口默认绑定本地回环接口 `127.0.0.1:5080`（`${OPENOBSERVE_BIND}`），严防公网未授权访问敏感日志与监控指标；外部统一通过 Traefik / Caddy 网关反代接入。
4. **OTLP 工业标准兼容**：
   - 原生支持 OpenTelemetry (OTLP) 协议，配合同内网的 `otel-collector`，实现微服务无缝上报。
5. **合规与隐私保护**：
   - 显式配置 `ZO_TELEMETRY=false`，杜绝向官方上报匿名遥测数据与查询统计。

---

## 📁 目录结构

```text
docker/open-observe/
├── docker-compose.yml # 编排服务定义 (S3 引擎对接、健康探活、资源配额)
└── README.md          # 平台架构、凭证管理与检索指南
```

---

## 🚀 快速上手与操作指南

### 步骤 1：启动服务

```bash
docker compose up -d

# 查看状态与健康探活
docker compose ps openobserve
```

### 步骤 2：访问控制台

- **本地直接访问**：[http://127.0.0.1:5080](http://127.0.0.1:5080)
- **初始登录凭证**（在 `.env` 中定义）：
  - 邮箱账号：`${OPENOBSERVE_ROOT_EMAIL}`
  - 登录密码：`${OPENOBSERVE_ROOT_PASSWORD}`

### 步骤 3：数据摄取地址与凭据

OpenObserve 预设主组织为 `default`，OTLP 摄取基础凭证在 `.env` 中配置为 `O2_AUTH`（`Basic <base64("email:password")>`）：

- **HTTP 遥测入口**：`http://openobserve:5080/api/default`
  - 日志流：`/api/default/v1/logs`
  - 指标流：`/api/default/v1/metrics`
  - 链路追踪：`/api/default/v1/traces`
- 通常建议将应用遥测统一上报给 **`otel-collector`**（端口 4317/4318），由其完成批处理和排队重试后再转发至 OpenObserve，避免网络抖动丢数据。
