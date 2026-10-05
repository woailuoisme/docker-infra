# Centrifugo 实时消息推送引擎

本项目采用 **[Centrifugo v6](https://github.com/centrifugal/centrifugo)** 官方容器镜像，为业务系统提供百万级并发、高可用、低延迟的实时消息推送与 WebSocket / SSE 长连接服务。

---

## 🌟 核心设计与优势

1. **精简云原生架构 (移除冗余 Dockerfile)**：
   - 直接运行官方标准镜像 `centrifugo/centrifugo:v6.9`，摒弃繁冗且难以随上游演进的自建 Dockerfile，降低镜像维护成本。
2. **仓库自包含只读配置**：
   - 通过 `./config.yaml:/centrifugo/config.yaml:ro` 相对只读挂载，杜绝依赖宿主机外部全局环境变量路径 `${CONFIG_PATH}`，天然免疫容器内被提权改写配置。
3. **多传输协议并存与自动降级**：
   - 原生支持双向 WebSocket 与 HTTP-Stream，同时开启单向轻量级的 `uni_websocket` 与 `uni_sse` (Server-Sent Events)，满足不同前端/移动端客户环境网络穿透需求。
4. **分布式引擎 (Valkey / Redis)**：
   - 生产环境默认连接同内网的 `valkey` 服务，实现跨节点广播和订阅发布（Pub/Sub）共享，无缝支持 Centrifugo 服务水平横向扩容（Scale-Out）。
5. **分级命名空间安全策略 (Namespaces)**：
   - `public`：公开广播大厅，开启消息恢复（`allow_recovery: true`），断网重连无感补发，禁止客户端私自发布（必须通过业务后端 API 发布）。
   - `private`：敏感私有频道，必须携带签名 Token 订阅。
   - `user`：用户专属单播频道，关闭 presence 与 join/leave 广播，极致节省 Valkey 内存。
   - `notification`：瞬时弱通知，高吞吐低耗，关闭恢复机制以削峰填谷。
6. **高并发与资源限额**：
   - 调优 `ulimits.nofile: 65536`，支撑大规模并发连接；设定内存限额 `256M`（预留 `64M`），避免长连接堆积导致雪崩。

---

## 📁 目录结构

```text
docker/centrifugo/
├── config.yaml        # Centrifugo 核心配置文件 (协议、引擎、通道规则)
├── docker-compose.yml # 服务编排 (网络划分、环境变量注入、健康检查、高并发句柄)
└── README.md          # 架构与运维指南
```

---

## 🚀 快速上手与操作指南

### 步骤 1：启动服务

```bash
docker compose up -d

# 查看状态与健康探活
docker compose ps centrifugo
```

### 步骤 2：验证健康检查与管理后台

- **服务健康探测**：

  ```bash
  curl -s http://127.0.0.1:48000/health
  # 返回: {"status":"ok"}
  ```

- **管理控制台**：
  - 访问地址：[http://127.0.0.1:48000/admin](http://127.0.0.1:48000/admin)
  - 登录密码：`.env` 中定义的 `CENTRIFUGO_ADMIN_PASSWORD`
- **Prometheus 指标端点**：
  - 访问地址：`http://127.0.0.1:48000/metrics`

### 步骤 3：后端 API 发布消息示例

业务服务端可通过 HTTP API 直接下发消息到指定频道（使用 `.env` 中的 `CENTRIFUGO_API_KEY`）：

```bash
curl -X POST http://127.0.0.1:48000/api/publish \
  -H "Authorization: apikey aef5a17a-fdeb-48aa-b2c1-d490c62ff950" \
  -H "Content-Type: application/json" \
  -d '{
    "channel": "public:chat",
    "data": {"message": "Hello from backend!"}
  }'
```
