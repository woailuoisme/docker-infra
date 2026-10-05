# OpenTelemetry Collector 统一遥测网关

本项目采用 **[OpenTelemetry Collector Contrib](https://github.com/open-telemetry/opentelemetry-collector-contrib)**，作为微服务架构中统一的指标（Metrics）、日志（Logs）与分布式追踪（Traces）遥测数据接入与转发网关。

---

## 🌟 核心设计与优势

1. **工业级数据处理流水线 (Pipeline Architecture)**：
   - **背压内存保护 (`memory_limiter`)**：优先执行内存边界检查（384MB 硬限额 / 128MB 尖峰缓冲），在下游出现故障或高突发流量时实施背压丢弃/降级，杜绝网关自身 OOM 崩溃。
   - **自动化资源富化 (`resource_detection`)**：自动识别注入 `host.name`、`os.type` 等环境元数据，免去应用代码逐个硬编码标签。
   - **批处理降频 (`batch`)**：以 5 秒或 1024 条为阈值聚合并行打包，将高频小请求整合成批量写入，大幅降低 OpenObserve 的磁盘 I/O 与索引开销。
2. **防丢数据弹性重试机制 (`sending_queue` + `retry_on_failure`)**：
   - 内部配置 5000 条缓冲发送队列，当下游 OpenObserve 重启、压缩维护或网络抖动时，遥测数据在内存中自动排队并按指数退避算法重试，保障业务链路数据完整性。
3. **仓库自包含只读配置**：
   - 使用相对路径只读挂载 `./config.yml:/etc/otelcol-contrib/config.yaml:ro`，摆脱宿主机外部全局环境变量路径耦合。
4. **全场景统一双网络拓扑**：
   - 接入 `backend` 供内部微服务/Worker 走高速内网通信；接入 `frontend` 方便 Traefik / Caddy 网关将前端浏览器端或移动端上报请求安全反代接入。
5. **自身可观测性与健康度管理**：
   - 暴露内置健康探针 `127.0.0.1:13133`，配置 Docker Compose 自动探活自愈。
   - 暴露 Prometheus 指标 `127.0.0.1:8888`，用于实时监控队列水位、摄取速率与丢弃率。

---

## 📁 目录结构

```text
docker/otel-collector/
├── config.yml         # 核心处理流水线定义 (接收器、内存限制、批处理、OpenObserve 导出)
├── docker-compose.yml # 服务编排 (网络规划、端口映射、健康探针、资源限额)
└── README.md          # 架构指南与 SDK 接入范例
```

---

## 🚀 快速上手与操作指南

### 步骤 1：启动服务

```bash
docker compose up -d

# 查看状态与健康探针
docker compose ps otel-collector
```

### 步骤 2：应用端 SDK 上报端点

在微服务应用（Go, Java, Node.js, Python, Rust 等）的 OpenTelemetry SDK 中配置：

- **Docker 内部容器通信**：
  - gRPC: `otel-collector:4317`
  - HTTP: `http://otel-collector:4318`
- **宿主机直连开发调试**：
  - gRPC: `127.0.0.1:4317`
  - HTTP: `http://127.0.0.1:4318`

### 步骤 3：HTTP 手动测试验证

向 HTTP 端口发送一条测试日志验证转发通路：

```bash
curl -X POST http://127.0.0.1:4318/v1/logs \
  -H "Content-Type: application/json" \
  -d '{
    "resourceLogs": [{
      "resource": {
        "attributes": [{
          "key": "service.name",
          "value": {"stringValue": "manual-test"}
        }]
      },
      "scopeLogs": [{
        "logRecords": [{
          "timeUnixNano": "1700000000000000000",
          "body": {"stringValue": "Hello from OpenTelemetry Collector!"}
        }]
      }]
    }]
  }'
```

前往 [http://127.0.0.1:5080](http://127.0.0.1:5080) 进入 OpenObserve 控制台，即可在 `default` 日志流中查询到该条测试日志。
