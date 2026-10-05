# Meilisearch 搜索引擎服务

本项目采用 **Meilisearch 官方镜像 (`getmeili/meilisearch:v1.54`)** 部署，遵循云原生与基础设施即代码（IaC）的生产级最佳实践。针对低配服务器（2核 1GB/2GB 内存）环境进行了深度防 OOM 与稳定性调优。

---

## 🌟 核心设计与优势

1. **官方原生镜像**：直接采用 `getmeili/meilisearch:v1.54` 纯净镜像，消除自建 Dockerfile 与时区包冗余，享受官方最新安全与性能优化。
2. **低内存与防 OOM 双保险**：
   - **配置层（config.toml）**：限制索引构建最大内存 (`max_indexing_memory = "256 MiB"`)，开启 `experimental_reduce_indexing_memory_usage` (LMDB `MDB_WRITEMAP` 模式)，限制单线程构建 (`max_indexing_threads = 1`)，防止后台建索引打满 CPU 影响在线搜索。
   - **容器层（docker-compose.yml）**：配置 `deploy.resources.limits`（内存上限 1024M，预留 256M），双重屏障杜绝容器引发整机 OOM。
3. **安全配置与只读挂载**：
   - `config.toml` 以只读 (`:ro`) 方式精准挂载，杜绝运行时被篡改。
   - 生产环境默认禁止匿名访问 (`env = "production"`，强制要求校验 `MEILI_MASTER_KEY`，长度须 $\ge$ 16 字节）。
   - 默认通过 `127.0.0.1:7700` 本地回环绑定，防止未授权公网暴露，统一通过反向代理（Traefik / Caddy）提供受保护的路由访问。
4. **原生健康检查与监控**：
   - 采用官方轻量 `wget --spider` 探针直连 `/health` 接口，无多余依赖。
   - 开启原生 Prometheus 指标输出 (`/metrics`)，无须额外 Exporter 即可采集搜索延迟与任务队列指标。
5. **自动化快照与灾备**：
   - 每日（86400秒）自动生成冷备快照到 `/meili_data/snapshots/`，保障数据安全。

---

## 📁 目录结构

```text
docker/meilisearch/
├── config.toml        # 核心生产配置（低内存调优、安全限流、快照策略、监控）
├── docker-compose.yml # 编排配置（官方镜像、资源硬限额、内联健康探针）
└── README.md          # 运维与 API 快速指南
```

---

## 🚀 快速上手与操作指南

### 步骤 1：配置环境变量

在根目录或本地 `.env` 中确保已定义 `MEILI_MASTER_KEY`（生产模式下必须至少 16 字节）：

```bash
# 生成高强度 32 字符 Master Key 示例：
# openssl rand -base64 24
MEILI_MASTER_KEY="your-super-strong-master-key-at-least-16-bytes"
TIMEZONE="Asia/Shanghai"
```

### 步骤 2：启动服务

```bash
# 启动容器
docker compose up -d

# 查看状态与健康检查
docker compose ps

# 查看实时日志
docker compose logs -f meilisearch
```

---

## 🧪 服务验证与常用命令

### 1. 健康检查

```bash
curl -i http://127.0.0.1:7700/health
# 期望返回：{"status":"available"}
```

### 2. 获取 API Keys（获取搜索专用 Key）

> 💡 **最佳实践**：生产环境中前端应用**切勿使用 Master Key**，应使用具备只读权限的 `Default Search API Key`。

```bash
curl -s -H "Authorization: Bearer ${MEILI_MASTER_KEY}" \
  http://127.0.0.1:7700/keys | jq .
```

### 3. 创建索引与搜索示例

```bash
# 1. 创建测试索引并写入文档
curl -X POST 'http://127.0.0.1:7700/indexes/movies/documents' \
  -H "Authorization: Bearer ${MEILI_MASTER_KEY}" \
  -H 'Content-Type: application/json' \
  --data-binary '[
    { "id": 1, "title": "Inception", "genre": "Sci-Fi" },
    { "id": 2, "title": "Interstellar", "genre": "Sci-Fi" }
  ]'

# 2. 执行搜索
curl -X POST 'http://127.0.0.1:7700/indexes/movies/search' \
  -H "Authorization: Bearer ${MEILI_MASTER_KEY}" \
  -H 'Content-Type: application/json' \
  --data-binary '{ "q": "Inception" }' | jq .
```

### 4. 采集 Prometheus 监控指标

```bash
curl -s -H "Authorization: Bearer ${MEILI_MASTER_KEY}" \
  http://127.0.0.1:7700/metrics
```

---

## 💾 数据备份与灾难恢复

1. **自动快照 (Snapshots)**：
   - 保存在 `${DATA_PATH}meili_data/snapshots/`，每天自动轮转。
2. **手动导出 Dump**：

   ```bash
   curl -X POST 'http://127.0.0.1:7700/dumps' \
     -H "Authorization: Bearer ${MEILI_MASTER_KEY}"
   ```

   导出结果保存在 `${DATA_PATH}meili_data/dumps/`，跨版本升级时可通过 `--import-dump` 导入无缝恢复。
