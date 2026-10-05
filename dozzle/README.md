# Dozzle 轻量级容器日志与状态监控面板

本项目采用 **[Dozzle v10](https://github.com/amir20/dozzle)**，为 Docker 容器提供实时的 Web 界面日志流式查看、内存/CPU 资源看板、容器重启与安全终端 Shell 控制。

---

## 🌟 核心设计与优势

1. **直接只读 Socket 接入 (移除未定义代理依赖)**：
   - 挂载宿主机 `/var/run/docker.sock:/var/run/docker.sock:ro`，以只读权限安全读取容器元数据与日志流，彻底移除了对外部缺失服务 `docker-socket-proxy` 的硬编码依赖。
2. **零信任网络暴露与网关统一鉴权**：
   - 鉴于开启了容器 Shell 执行能力（`DOZZLE_ENABLE_SHELL: true`），Web 端口默认严格绑定本地回环接口 `127.0.0.1:8180`（`${DOZZLE_BIND}`），严禁未经授权的公网扫描。
   - 去除了本地冗余的 `users.yml` 单点认证文件，统一由反向代理（Traefik / Caddy）前置集成 Authelia 进行企业级 SSO / 2FA 统一认证与访问控制。
3. **隐私保护与轻量资源限额**：
   - 设置 `DOZZLE_NO_ANALYTICS: true`，禁止向第三方回传遥测数据。
   - 限制 CPU: 0.5 核，内存上限 256M（预留 64M），避免高并发日志长连接占用过多宿主机内存。

---

## 📁 目录结构

```text
docker/dozzle/
├── docker-compose.yml # 服务编排（只读 socket、本地回环绑定、健康探针、资源限制）
└── README.md          # 运维指南与反向代理接入规范
```

---

## 🚀 快速上手与操作指南

### 步骤 1：启动服务

```bash
docker compose up -d

# 查看状态与健康探活
docker compose ps dozzle
```

### 步骤 2：访问控制台

- **本地直接访问**：[http://127.0.0.1:8180](http://127.0.0.1:8180)

### 步骤 3：网关反向代理接入（Traefik / Caddy）

若需要外网通过域名访问，推荐配合 Authelia 进行双因子 SSO 认证：

```caddyfile
import proxy-app dozzle.{$SITE_ADDRESS} 127.0.0.1:8180
```
