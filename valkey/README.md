# Valkey 高性能内存数据存储 (Redis 开源替代方案)

本项目采用 **Linux Foundation 官方原生镜像 (`valkey/valkey:9.1-alpine`)** 部署，遵循云原生与基础设施即代码（IaC）的生产级最佳实践。针对低配云服务器（2核 1GB/2GB 内存）及队列/缓存主导（BullMQ、Laravel Queue、Centrifugo、Authelia 等）场景进行了防 OOM 与延迟毛刺专项调优。

---

## 🌟 核心设计与优势

1. **官方原生镜像与零冗余构建**：
   - 彻底废弃自定义 `Dockerfile` 与包装脚本，直接基于官方 `valkey/valkey:9.1-alpine` 镜像，消除构建负担并确保享受上游安全补丁。
   - 密码直接通过 Compose 原生 `command` 传参注入（`--requirepass ${REDIS_PASSWORD}`），安全灵活。
2. **低内存与防 OOM 双重硬屏障**：
   - **配置层（valkey.conf）**：内存严格封顶 `maxmemory 256mb`。淘汰策略设为 `noeviction`，确保关键任务队列数据在内存耗尽时拒绝写入并报错，杜绝静默逐出队列任务导致业务丢单。
   - **容器层（docker-compose.yml）**：配置 `mem_limit: 384mb`，为 Valkey 自身内部数据结构、jemalloc 碎片以及客户端网络缓冲区预留充足空间，杜绝容器引发整机 OOM Killer 强杀。
3. **网络安全与零公网暴露**：
   - 彻底移除宿主机 `ports` 端口映射，服务仅在 `backend` 内部容器网络中暴露 (`valkey:6379`)，杜绝公网弱口令扫描与勒索软件利用。
   - 仅供内部业务组件（如 `centrifugo`、`authelia`、`asynqmon` 等）内网互通。
4. **延迟毛刺消除 (Lazy Free)**：
   - 开启全部 5 项异步惰性释放特性（`lazyfree-lazy-*`），将大 Key/Hash/Set 删除、过期清理移至后台线程执行，彻底消除单线程阻塞导致的延迟抖动。
5. **增量安全与混合持久化**：
   - 开启 AOF 增量安全写入（`appendonly yes`），结合原生 `appendfsync everysec` 与混合持久化（AOF 前半段 RDB + 后半段增量指令），兼具毫秒级故障恢复速度与数据可靠性。
6. **精简并发与库收敛**：
   - 连接数由默认 10000 压紧至 `maxclients 1000`，收敛数据库总数至 `databases 2`（db0/db1），避免闲置资源开销。

---

## 📁 目录结构

```text
docker/valkey/
├── valkey.conf        # 核心生产配置（低内存调优、LazyFree、AOF持久化）
├── docker-compose.yml # 编排配置（官方镜像、内网隔离、内存硬限制、健康检查）
└── README.md          # 运维与排障快速指南
```

---

## 🚀 快速上手与操作指南

### 步骤 1：配置环境变量

在根目录 `.env` 文件中确保已定义 `REDIS_PASSWORD`：

```bash
# 生成高强度 32 字符随机密码示例：
# openssl rand -base64 24
REDIS_PASSWORD="your-strong-valkey-password"
TIMEZONE="Asia/Shanghai"
```

### 步骤 2：启动服务

```bash
# 启动容器
docker compose up -d

# 检查容器运行状态与健康检查
docker compose ps

# 查看启动日志
docker compose logs -f valkey
```

---

## 🧪 验证与日常运维命令

### 1. 容器内连通性测试 (PONG)

```bash
docker compose exec -it valkey valkey-cli -a "${REDIS_PASSWORD}" ping
# 期望返回：PONG
```

### 2. 检查内存使用状态与上限

```bash
docker compose exec -it valkey valkey-cli -a "${REDIS_PASSWORD}" info memory | grep -E "used_memory_human|maxmemory_human"
```

### 3. 查看持久化状态 (AOF / RDB)

```bash
docker compose exec -it valkey valkey-cli -a "${REDIS_PASSWORD}" info persistence
```

### 4. 模拟写入与读取测试

```bash
# 写入测试 Key
docker compose exec -it valkey valkey-cli -a "${REDIS_PASSWORD}" set test_health ok ex 60

# 读取测试 Key
docker compose exec -it valkey valkey-cli -a "${REDIS_PASSWORD}" get test_health
```

---

## 💾 数据备份与恢复

- **数据持久化目录**：挂载在宿主机 `${DATA_PATH:-./data/}valkey`。
- **冷备份**：
  在触发备份前可手动触发 BGSAVE：

  ```bash
  docker compose exec valkey valkey-cli -a "${REDIS_PASSWORD}" bgsave
  ```

  随后将挂载目录下的 `dump.rdb` 和 `appendonlydir/` 打包归档即可。
