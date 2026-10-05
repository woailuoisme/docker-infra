# Asynqmon 分布式队列监控看板

本项目使用 **[hibiken/asynqmon](https://github.com/hibiken/asynqmon)** 官方容器镜像，为 Golang Asynq 异步任务队列提供基于 Web 的实时可视化监控管理面板。

---

## 🌟 核心设计与优势

1. **跨架构仿真支持**：针对官方镜像缺少 arm64 架构的现状，声明 `platform: linux/amd64`，确保在 Apple Silicon (M1/M2/M3/M4) 及开发机上平稳无感模拟运行。
2. **零信任网络边界**：
   - Asynqmon 原生不带登录认证机制。配置默认绑定本地回环接口 `127.0.0.1:8500`（`${ASYNQMON_BIND}`），严防未授权公网访问导致任务被恶意取消或数据泄露。
   - 生产环境统一通过 Traefik / Caddy 反向代理，并挂载 Authelia 单点登录拦截保护。
3. **依赖健康就绪检查**：
   - 声明 `depends_on: valkey: condition: service_healthy`，确保底层存储就绪后再启动 Web 服务，杜绝反复重启报错。
4. **轻量资源硬限额**：
   - 内存上限设为 `128M`（预留 `32M`），防止管理面板过度占用低配云主机资源。

---

## 📁 目录结构

```text
docker/asynqmon/
├── docker-compose.yml # 服务编排（平台声明、本地安全绑定、健康探活、资源限制）
└── README.md          # 使用与运维快速指南
```

---

## 🚀 快速上手与操作指南

### 步骤 1：启动服务

```bash
docker compose up -d

# 查看状态
docker compose ps asynqmon
```

### 步骤 2：访问控制台

- 本地浏览器访问：[http://127.0.0.1:8500](http://127.0.0.1:8500)
- 可实时查看队列任务统计（`Active`、`Pending`、`Scheduled`、`Retry`、`Archived`、`Completed`），并支持手动重试或归档失败任务。
