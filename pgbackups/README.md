# PostgreSQL 自动化备份与灾备归档服务

本项目采用 **[prodrigestivill/postgres-backup-local](https://github.com/prodrigestivill/docker-postgres-backup-local)**（基于 PostgreSQL 18 Alpine 原生客户端），为 PostgreSQL / TimescaleDB 提供开箱即用、具备分层滚动留存与故障探针的自动化快照备份系统。

---

## 🌟 核心设计与优势

1. **版本精准对齐 (PostgreSQL 18 原生驱动)**：
   - 镜像标签锁定 `18-alpine`，与底层 PostgreSQL 18.x 数据库客户端引擎内核版本一致，彻底杜绝 `pg_dump` 跨大版本导出可能引发的元数据语法不兼容问题。
2. **全 Schema 覆盖与高效压缩**：
   - 移除 `--schema=public` 单一模式限制，全面覆盖 TimescaleDB 内部时序表、扩展插件及其他自定义 Schema，防范恢复时数据缺失。
   - 配置 `-Z6 --blobs`，兼顾压缩率与 CPU 效率，完整保留大对象数据。
3. **分层生命周期留存 (G-F-S 轮转策略)**：
   - `BACKUP_KEEP_DAYS=7`：保留最近 7 天的每日备份。
   - `BACKUP_KEEP_WEEKS=4`：保留最近 4 周的周日快照。
   - `BACKUP_KEEP_MONTHS=6`：保留最近 6 个月的月末快照。
   - 自动滚动清理过期历史归档，防止宿主机磁盘跑满。
4. **探针监控与启动验真**：
   - 开启 `BACKUP_ON_START=TRUE`，容器启动时执行首次备份自检。
   - 暴露内置 `HEALTHCHECK_PORT=8080`，当备份超期或失败时返回 HTTP 500 状态码，供 Uptime Kuma 等外部告警平台探测。
5. **健壮依赖与资源限额**：
   - 声明 `depends_on: postgres: condition: service_healthy`，数据库就绪前不提前执行。
   - 设置内存上限 `512M`（预留 `64M`），限制大型快照压缩过程中的内存峰值。

---

## 📁 目录结构

```text
docker/pgbackups/
├── docker-compose.yml # 编排配置 (调度策略、分层留存、健康探活、资源配额)
└── README.md          # 备份机制、手动触发与灾难恢复指南
```

---

## 🚀 快速上手与操作指南

### 步骤 1：启动服务

```bash
docker compose up -d

# 查看状态
docker compose ps pgbackups
```

### 步骤 2：手动立即触发备份

无需等待每日凌晨 03:00 定时调度，可通过容器内 `backup.sh` 脚本立即执行全量快照：

```bash
docker compose exec pgbackups backup
```

### 步骤 3：查看备份文件列表

持久化文件存储于宿主机的 `${DATA_PATH:-./data/}pgbackups` 目录下：

```bash
ls -lh data/pgbackups/
# 输出示例:
# 2026-10-06T03_45_00.sql.gz
```

### 步骤 4：灾难恢复指南 (Restore)

若需将备份恢复到指定数据库中：

```bash
# 1. 拷贝备份文件或直接通过流式解压还原到 postgres 容器中
zcat data/pgbackups/2026-10-06T03_45_00.sql.gz | docker compose exec -T postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB}
```
