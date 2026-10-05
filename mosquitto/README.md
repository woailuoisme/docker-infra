# Eclipse Mosquitto MQTT Broker

本项目采用 **Eclipse Mosquitto 2.x 官方镜像 (`eclipse-mosquitto:2-alpine`)** 构建，遵循基础设施即代码（IaC）的生产级最佳实践。彻底消除自定义构建与启动脚本包装，实现轻量、安全、可审计的自包含部署。

---

## 🌟 核心设计与优势

1. **官方原生镜像**：直接使用 `eclipse-mosquitto:2-alpine`，告别私有 Dockerfile 维护成本与安全补丁滞后风险。
2. **凭据安全与零泄露**：
   - 移除环境变量注入明文密码的脆弱做法，通过 `mosquitto_passwd` 进行 SHA512-PBKDF2 安全哈希生成。
   - 敏感文件 `config/passwd` 纳入 `.gitignore`，防止误提交。
3. **配置只读保护 (`:ro`)**：
   - `mosquitto.conf`、`acl` 和 `passwd` 均以只读形式精准挂载，防止运行时被容器内部意外篡改或被空卷遮蔽。
4. **双协议监听**：
   - `1883`：标准 MQTT 协议（IoT 边缘设备通信）。
   - `9001`：WebSockets 协议（供 Web 前端、H5、IoT 监控面板或反向代理直连）。
5. **多租户动态模式隔离 (Pattern ACL)**：
   - 无需为每个新增设备手动维护庞大的 ACL 静态列表。通过 `%u/#`（按登录账号）与 `device/%u/#` 模式自动隔离各设备专属主题。
6. **无侵入健康检查 (Inline Healthcheck)**：
   - 在 `docker-compose.yml` 中内联调用镜像内置的 `mosquitto_sub` 探测 `$SYS/broker/version`，告别外置探针脚本。

---

## 📁 目录结构

```text
docker/mosquitto/
├── config/
│   ├── mosquitto.conf     # 生产环境核心配置（连接数、队列、日志、协议）
│   ├── acl                # 权限控制列表（Admin 超管 + Pattern 设备隔离）
│   ├── passwd.example     # 密码文件格式模板与生成说明
│   └── passwd             # [本地生成] 实际加密凭据文件（Git 忽略）
├── docker-compose.yml     # 容器编排文件
└── README.md              # 运维与开发指南
```

---

## 🚀 快速上手与操作指南

### 步骤 1：生成凭据文件 (`passwd`)

Mosquitto 2.x 强制要求密码使用加密散列。在当前 `docker/mosquitto/` 目录下执行以下命令，利用官方临时容器生成密码文件：

```bash
# 1. 首次创建并设置管理员 admin 账户密码（-c 参数代表新建文件）：
docker run --rm -v "$(pwd)/config:/mosquitto/config" eclipse-mosquitto:2 \
  mosquitto_passwd -c -b /mosquitto/config/passwd admin "YourStrongAdminPass"

# 2. （可选）追加业务或设备账户（无需 -c）：
docker run --rm -v "$(pwd)/config:/mosquitto/config" eclipse-mosquitto:2 \
  mosquitto_passwd -b /mosquitto/config/passwd dev_device_01 "DeviceSecret123"

# 3. 设置安全的本地权限（仅所有者/组可读）：
chmod 640 config/passwd
```

### 步骤 2：启动服务

```bash
# 启动容器
docker compose up -d

# 查看运行状态与健康检查
docker compose ps

# 查看日志
docker compose logs -f mosquitto
```

---

## 🧪 连通性与权限测试

可使用宿主机或临时容器的 `mosquitto_sub` / `mosquitto_pub` 验证：

### 1. 超级管理员测试（读写全量主题）

```bash
# 终端 1：订阅全部主题
docker run --rm --network host eclipse-mosquitto:2 \
  mosquitto_sub -h 127.0.0.1 -p 1883 -u admin -P "YourStrongAdminPass" -t "#" -v

# 终端 2：发布测试消息
docker run --rm --network host eclipse-mosquitto:2 \
  mosquitto_pub -h 127.0.0.1 -p 1883 -u admin -P "YourStrongAdminPass" -t "test/topic" -m "hello mqtt"
```

### 2. IoT 设备租户隔离测试

根据 `config/acl` 中的配置，账号 `dev_device_01` 仅能发布和订阅属于自己的前缀：

```bash
# 允许的操作：发布到自己的设备主题
docker run --rm --network host eclipse-mosquitto:2 \
  mosquitto_pub -h 127.0.0.1 -p 1883 -u dev_device_01 -P "DeviceSecret123" -t "device/dev_device_01/telemetry" -m '{"temp": 25.4}'

# 被拒绝的操作：试图订阅或发布其他设备/系统主题（将被 ACL 阻断）
docker run --rm --network host eclipse-mosquitto:2 \
  mosquitto_pub -h 127.0.0.1 -p 1883 -u dev_device_01 -P "DeviceSecret123" -t "admin/secret" -m "hack"
```

---

## ⚙️ 核心参数调优说明 (`mosquitto.conf`)

| 参数项 | 当前设定值 | 生产建议与考量 |
| :--- | :--- | :--- |
| `max_packet_size` | `10485760` (10MB) | 严格限制单包大小，防御客户端异常提交超大 payload 导致 Broker OOM |
| `persistent_client_expiration` | `1d` (1天) | 自动清理长期断线的持久化客户端与未收割队列，防止内存和持久化存储无限膨胀 |
| `max_queued_messages` | `2000` | 离线 QoS 1/2 消息排队上限，防止突发积压打满内存 |
| `max_inflight_messages` | `40` | 提高未确认并发消息流吞吐量 |
| `sys_interval` | `60` | 监控指标刷新周期设为 60s，减少高频 `$SYS` 主题发布带来的内部锁开销 |
| `log_dest` | `stdout` | 日志交由容器运行时标准输出统一采集，避免容器内写磁盘造成的无谓 I/O |
