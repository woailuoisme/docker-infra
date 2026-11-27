# IoT 售货机服务端架构设计 (Server Architecture)

本文档定义了冷链便当售货机云端数据处理与监控系统的整体架构设计。

---

## 1. 技术栈总览

| 组件 | 镜像版本 | 用途 | 端口 |
| :--- | :--- | :--- | :--- |
| **Mosquitto** | `eclipse-mosquitto:2.1-alpine` | MQTT 5.0 Broker | 1883 (内部), 8883 (Traefik MQTTS), 9001 (WS) |
| **Telegraf** | `telegraf:1.40-alpine` | 数据采集代理 (MQTT → InfluxDB 3) | 8080 (监控指标，宿主机映射 9080) |
| **InfluxDB 3 Core** | `influxdb:3.12-core` | Apache Arrow 列式时序数据库 (Parquet 存储) | 8181 (HTTP Write / SQL / Flight SQL) |
| **InfluxDB 3 UI** *(可选)* | `influxdata/influxdb3-ui:1.11.2` | Web Explorer 数据查询控制台 | 8080 (宿主机映射 8810) |
| **Grafana** | `grafana/grafana:13.3-slim` | 可视化监控仪表盘 (Flight SQL / InfluxQL) | 3000 (宿主机映射 3311) |

---

## 2. 系统架构图

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                           IoT 售货机设备层                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐                │
│  │ VM-SH-001│  │ VM-SH-002│  │ VM-BJ-001│  │ VM-GZ-001│  ...           │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘                │
│       │             │             │             │                       │
│       └─────────────┴──────┬──────┴─────────────┘                       │
│                            │ MQTT 5.0 (QoS 0/1/2)                       │
└────────────────────────────┼────────────────────────────────────────────┘
                             ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        服务端数据层 (Docker Compose)                    │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                    Mosquitto (MQTT Broker)                        │  │
│  │  - 端口: 1883 (TCP), 8883 (Traefik MQTTS), 9001 (WebSocket)      │  │
│  │  - 主题订阅: v1/vm/+/telemetry, v1/vm/+/events,                  │  │
│  │             v1/vm/+/status, v1/vm/+/commands/ack                 │  │
│  └───────────────────────────┬──────────────────────────────────────┘  │
│                              │                                          │
│                              ▼                                          │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                    Telegraf (数据采集代理)                        │  │
│  │  - 输入: inputs.mqtt_consumer (json_v2 解析 + Topic 提取 Tag)     │  │
│  │  - 缓冲: metric_batch_size = 5000, flush_interval = 10s          │  │
│  │  - 输出: outputs.influxdb_v3 (HTTP /api/v3/write_lp Line Protocol)│  │
│  └───────────────────────────┬──────────────────────────────────────┘  │
│                              │                                          │
│                              ▼                                          │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                InfluxDB 3 Core (列式时序数据库)                   │  │
│  │  - 引擎: Apache Arrow + DataFusion + Parquet 列式存储             │  │
│  │  - 数据库 (Database): iot (Schema-on-Write 自动建表)              │  │
│  │  - Measurement 表: vm_telemetry, vm_events, vm_status,           │  │
│  │                    vm_command_acks                                │  │
│  │  - 鉴权: Bearer Token (--admin-token-file / INFLUXDB_TOKEN)       │  │
│  └───────────────────────────┬──────────────────────────────────────┘  │
│                              │                                          │
│                              ▼                                          │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                    Grafana (可视化监控)                           │  │
│  │  - 数据源: InfluxDB3-SQL (Flight SQL) & InfluxDB3-InfluxQL       │  │
│  │  - 仪表盘: 机群运营总览、单机诊断、温度趋势、事件追踪             │  │
│  │  - 告警规则: 超温、离线、暴力告警                                 │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                         │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 3. 数据流详解

### 3.1 遥测数据流 (Telemetry)

```text
设备 → MQTT (v1/vm/{device_no}/telemetry, QoS 0)
     → Telegraf (inputs.mqtt_consumer + json_v2)
     → 解析 system / environment / connectivity / location 字段与 device_no Tag
     → InfluxDB 3 (iot 库 vm_telemetry 表, Line Protocol 写入)
     → Grafana (Flight SQL 实时仪表盘)
```

### 3.2 事件数据流 (Events)

```text
设备 → MQTT (v1/vm/{device_no}/events, QoS 1)
     → Telegraf (inputs.mqtt_consumer + json_v2)
     → 提取 device_no / event_type Tag 与 order_id / channel_id / error_code / g_force 字段
     → InfluxDB 3 (iot 库 vm_events 表)
     → Grafana (告警面板 + 通知规则)
```

### 3.3 状态与指令回执数据流 (Status & Command ACKs)

```text
设备 → MQTT (v1/vm/{device_no}/status, QoS 1, Retain)
     → Telegraf → InfluxDB 3 (iot 库 vm_status 表) → Grafana (在线状态面板)

设备 → MQTT (v1/vm/{device_no}/commands/ack, QoS 1)
     → Telegraf → InfluxDB 3 (iot 库 vm_command_acks 表) → Grafana / 业务后台
```

---

## 4. 数据库 Schema 设计 (InfluxDB 3 Schema-on-Write)

InfluxDB 3 Core 采用 **Schema-on-Write** 模式：在 `iot` 数据库创建后，Telegraf 写入 Line Protocol 时会自动按 Measurement 创建并维护对应的 Parquet 列式表与 Tag 索引，无需预先执行 DDL 建表。

> 初始化数据库示例：
>
> ```bash
> curl -sS -X POST "http://localhost:8181/api/v3/configure/database" \
>   -H "Authorization: Bearer ${INFLUXDB_TOKEN}" \
>   -H "Content-Type: application/json" \
>   -d '{"db": "iot"}'
> ```

### 4.1 遥测数据表 (`vm_telemetry`)

| 列名 | 角色 | 类型 | 说明 |
| :--- | :--- | :--- | :--- |
| `time` | Timestamp | `TIMESTAMP` | 由 `ts` 字段解析的设备采样时间戳 |
| `device_no` | Tag | `STRING` (Dictionary) | 从 Topic `v1/vm/{device_no}/telemetry` 提取的设备编号 |
| `voltage` | Field | `FLOAT64` | 供电电压 (V) |
| `current` | Field | `FLOAT64` | 工作电流 (A) |
| `uptime` | Field | `INT64` | 设备运行时长 (s) |
| `door_closed` | Field | `BOOLEAN` | 柜门闭合状态 |
| `temp_zone_0` ~ `3` | Field | `FLOAT64` | 4 温区冷柜温度 (°C) |
| `ambient_temp` | Field | `FLOAT64` | 环境温度 (°C) |
| `vibration_g` | Field | `FLOAT64` | 震动加速度 (g) |
| `rssi` | Field | `INT64` | 蜂窝信号强度 (dBm) |
| `lat`, `lng` | Field | `FLOAT64` | GPS 经纬度坐标 |

### 4.2 事件数据表 (`vm_events`)

| 列名 | 角色 | 类型 | 说明 |
| :--- | :--- | :--- | :--- |
| `time` | Timestamp | `TIMESTAMP` | 由 Unix 时间戳 `ts` 解析 |
| `device_no` | Tag | `STRING` (Dictionary) | 设备编号 |
| `event_type` | Tag | `STRING` (Dictionary) | 事件类型 (`DISPENSE_SUCCESS` / `TEMP_OVERHEAT` / `VANDALISM_ALERT` 等) |
| `order_id` | Field | `STRING` | 关联订单号 (可选) |
| `channel_id` | Field | `STRING` | 货道编号 (可选) |
| `error_code` | Field | `STRING` | 故障/错误码 (可选) |
| `g_force` | Field | `FLOAT64` | 冲击震动加速度 (可选) |

### 4.3 状态数据表 (`vm_status`)

| 列名 | 角色 | 类型 | 说明 |
| :--- | :--- | :--- | :--- |
| `time` | Timestamp | `TIMESTAMP` | 由 Unix 时间戳 `ts` 解析 |
| `device_no` | Tag | `STRING` (Dictionary) | 设备编号 |
| `status` | Tag | `STRING` (Dictionary) | 在线状态 (`online` / `offline`) |
| `firmware` | Field | `STRING` | 固件版本 (可选) |
| `hardware` | Field | `STRING` | 硬件版本 (可选) |

### 4.4 指令确认表 (`vm_command_acks`)

| 列名 | 角色 | 类型 | 说明 |
| :--- | :--- | :--- | :--- |
| `time` | Timestamp | `TIMESTAMP` | 接收时间戳 |
| `device_no` | Tag | `STRING` (Dictionary) | 设备编号 |
| `status` | Tag | `STRING` (Dictionary) | 指令执行状态 |
| `cmd_id` | Field | `STRING` | 指令唯一 ID |
| `execution_duration_ms` | Field | `INT64` | 执行耗时 (ms，可选) |
| `error_code` | Field | `STRING` | 失败错误码 (可选) |

---

## 5. Telegraf 配置

实际配置拆分在 `telegraf/telegraf.conf`、`telegraf/telegraf.d/inputs-mqtt-iot.conf` 与 `telegraf/telegraf.d/outputs-influxdb.conf`，核心管道如下：

```toml
# /etc/telegraf/telegraf.conf

[agent]
  interval = "10s"
  round_interval = true
  metric_batch_size = 5000
  metric_buffer_limit = 50000
  flush_interval = "10s"
  flush_jitter = "2s"
  omit_hostname = true
  logformat = "structured"
  skip_processors_after_aggregators = true

# ==================== 输入: MQTT Consumer ====================
[[inputs.mqtt_consumer]]
  servers = ["tcp://${MQTT_HOST}:${MQTT_PORT}"]
  topics = ["v1/vm/+/telemetry"]
  data_format = "json_v2"
  client_id = "telegraf_iot_telemetry"
  username = "${MQTT_USERNAME}"
  password = "${MQTT_PASSWORD}"
  qos = 0

  [[inputs.mqtt_consumer.json_v2]]
    measurement_name = "vm_telemetry"
    timestamp_path = "ts"
    timestamp_format = "2006-01-02T15:04:05.999Z07:00"

    [[inputs.mqtt_consumer.topic_parsing]]
      topic = "v1/vm/+/telemetry"
      tags = "_/_/device_no/_"

    [[inputs.mqtt_consumer.json_v2.field]]
      path = "system.voltage"
      rename = "voltage"
      type = "float"
    [[inputs.mqtt_consumer.json_v2.field]]
      path = "system.current"
      rename = "current"
      type = "float"
    [[inputs.mqtt_consumer.json_v2.field]]
      path = "system.uptime"
      rename = "uptime"
      type = "int"
    [[inputs.mqtt_consumer.json_v2.field]]
      path = "system.door_closed"
      rename = "door_closed"
      type = "bool"
    [[inputs.mqtt_consumer.json_v2.field]]
      path = "environment.freezer_temps.0"
      rename = "temp_zone_0"
      type = "float"
    [[inputs.mqtt_consumer.json_v2.field]]
      path = "environment.freezer_temps.1"
      rename = "temp_zone_1"
      type = "float"
    [[inputs.mqtt_consumer.json_v2.field]]
      path = "environment.freezer_temps.2"
      rename = "temp_zone_2"
      type = "float"
    [[inputs.mqtt_consumer.json_v2.field]]
      path = "environment.freezer_temps.3"
      rename = "temp_zone_3"
      type = "float"
    [[inputs.mqtt_consumer.json_v2.field]]
      path = "environment.ambient_temp"
      rename = "ambient_temp"
      type = "float"
    [[inputs.mqtt_consumer.json_v2.field]]
      path = "environment.vibration_g"
      rename = "vibration_g"
      type = "float"
    [[inputs.mqtt_consumer.json_v2.field]]
      path = "connectivity.rssi"
      rename = "rssi"
      type = "int"
    [[inputs.mqtt_consumer.json_v2.field]]
      path = "location.lat"
      rename = "lat"
      type = "float"
    [[inputs.mqtt_consumer.json_v2.field]]
      path = "location.lng"
      rename = "lng"
      type = "float"
# (另有 vm_events / vm_status / vm_command_acks 三个独立 consumer，详见 telegraf/telegraf.d/inputs-mqtt-iot.conf)

# ==================== 输出: InfluxDB 3 ====================
[[outputs.influxdb_v3]]
  urls = ["http://${INFLUXDB_HOST}:${INFLUXDB_PORT}"]
  database = "${INFLUXDB_DATABASE}"
  token = "${INFLUXDB_TOKEN}"
  timeout = "5s"
  namedrop = ["internal_*"]
```

---

## 6. Grafana 监控面板 (InfluxDB 3 SQL / Flight SQL)

Grafana 通过 `influxdata-flightsql-datasource` 插件连接 `http://influxdb:8181`（数据源 `InfluxDB3-SQL` 与 `InfluxDB3-InfluxQL`），使用 Apache DataFusion SQL 语法查询：

### 6.1 设备概览仪表盘

| 面板 | 查询示例 (InfluxDB 3 SQL) | 用途 |
| :--- | :--- | :--- |
| **在线设备数** | `SELECT COUNT(DISTINCT device_no) FROM vm_status WHERE status = 'online' AND time > NOW() - INTERVAL '5 minutes'` | 实时在线统计 |
| **今日订单数** | `SELECT COUNT(*) FROM vm_events WHERE event_type = 'DISPENSE_SUCCESS' AND time >= DATE_TRUNC('day', NOW())` | 业务指标 |
| **活跃告警** | `SELECT time, device_no, event_type, error_code FROM vm_events WHERE event_type IN ('CHANNEL_JAM', 'HEATING_FAILURE') AND time > NOW() - INTERVAL '1 hour' ORDER BY time DESC` | 故障监控 |
| **设备分布地图** | `SELECT device_no, MAX(lat) AS lat, MAX(lng) AS lng FROM vm_telemetry WHERE time > NOW() - INTERVAL '5 minutes' GROUP BY device_no` | 地理位置 |

### 6.2 温度监控面板

```sql
-- 冷冻温区趋势图 (InfluxDB 3 DataFusion DATE_BIN)
SELECT
    DATE_BIN(INTERVAL '5 minutes', time) AS bucket,
    device_no,
    AVG(temp_zone_0) AS zone_0,
    AVG(temp_zone_1) AS zone_1,
    AVG(temp_zone_2) AS zone_2,
    AVG(temp_zone_3) AS zone_3
FROM vm_telemetry
WHERE time > NOW() - INTERVAL '24 hours'
GROUP BY bucket, device_no
ORDER BY bucket ASC;
```

### 6.3 告警规则配置

| 告警名称 | 条件 | 通知渠道 |
| :--- | :--- | :--- |
| **设备离线** | `vm_status.status = 'offline'` 持续 5 分钟 | 钉钉/企业微信 |
| **冷冻超温** | `temp_zone_* > -10` | 短信 + 邮件 |
| **暴力告警** | `event_type = 'VANDALISM_ALERT'` | 电话 + 短信 |

---

## 7. 容器编排 (Docker Compose)

由仓库根目录 `docker-compose.yml` 通过 `include` 统一编排以下服务模块：

* `mosquitto/docker-compose.yml`
* `influxdb/docker-compose.yml`
* `telegraf/docker-compose.yml`
* `grafana/docker-compose.yml`
* `simulator/docker-compose.yml`

---

## 8. 扩展性设计

### 8.1 水平扩展

* **MQTT Broker**: 使用 EMQX / RMQTT 集群替代单节点 Mosquitto
* **InfluxDB 3**: 将底层 `--object-store` 从本地 `file` 切换为共享 S3 对象存储（如仓库内的 Garage S3），并可按需扩展为读写分离的多节点架构（InfluxDB 3 Enterprise / Clustered）
* **Telegraf**: 每个区域部署独立实例，通过 HTTP/Arrow 并发写入 InfluxDB 3

### 8.2 高可用设计

* **时序存储**: InfluxDB 3 基于对象存储实现存算分离与 Parquet 持久化，配合本地/对象存储快照保障数据不丢失
* **Grafana**: 多实例 + 共享 PostgreSQL 元数据库后端
* **MQTT**: 集群模式 + 负载均衡（Traefik MQTTS / TCP Keepalive）

---

*Created by Antigravity - IoT Backend Architecture*
