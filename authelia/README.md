# Authelia 身份认证与单点登录 (SSO)

本项目采用 **[Authelia v4.39](https://github.com/authelia/authelia)**，作为集群与服务的前置单点登录（SSO）与双因子认证（2FA）守门人，与 Traefik / Caddy 反向代理网关协同工作。

---

## 🌟 核心设计与优势

1. **容器级模板化机密注入**：
   - 启用 `X_AUTHELIA_CONFIG_FILTERS=template`，所有密钥（`JWT_SECRET`、`SESSION_SECRET`、`STORAGE_ENCRYPTION_KEY`、Redis 密码及 Resend API Key）全部通过环境变量动态解析，杜绝将凭据明文硬编码于 YAML 配置文件中。
2. **仓库自包含与只读防护**：
   - 采用相对路径挂载 `./config:/config:ro`，摆脱对宿主机绝对路径 `${CONFIG_PATH}` 的隐式耦合，并开启只读属性 `:ro`，杜绝容器进程被提权后篡改 ACL 认证规则与用户清单。
   - 运行时数据存储独立挂载至 `${DATA_PATH:-./data/}authelia:/data`。
3. **零信任网络暴露面**：
   - 端口默认绑定本地回环接口 `127.0.0.1:9091`（`${AUTHELIA_BIND}`），避免认证端点绕过网关直接暴露给公网。
4. **现代化身份认证能力**：
   - **双因子认证 (2FA)**：内置支持基于时间戳的动态口令（TOTP）与 FIDO2 / WebAuthn / Passkeys 现代通行密钥无感登录。
   - **防暴力破解**：配置 `regulation` 策略，同一 IP 连续 3 次失败自动封禁 5 分钟。
   - **分布式会话**：会话状态持久化至 Valkey (Redis 兼容)，`inactivity: 60m`，`expiration: 3h`，重启不丢登录态。
   - **热加载用户库**：`authentication_backend.file` 开启 `watch: true`，修改 `users_database.yml` 即时生效，无需重启容器。
5. **轻量生产限额**：
   - 限制 CPU: 1.0 核，内存上限 256M（预留 64M），确保高并发验签时资源受控。

---

## 📁 目录结构

```text
docker/authelia/
├── config/
│   ├── configuration.yml   # 核心配置文件 (模板语法、ACL 规则、端点映射)
│   └── users_database.yml  # 用户数据库 (Argon2id 加密凭据、分组权限)
├── docker-compose.yml      # 容器编排服务定义
└── README.md               # 运维与使用指南
```

---

## 🚀 快速上手与操作指南

### 步骤 1：启动服务

```bash
docker compose up -d

# 查看状态与健康探活
docker compose ps authelia
```

### 步骤 2：生成新用户密码 (Argon2id)

如需在 `config/users_database.yml` 中新增或修改用户密码，使用官方推荐的 Argon2id 哈希算法生成密文：

```bash
docker run --rm authelia/authelia:4.39 authelia crypto hash generate argon2 --password 'YourSecurePassword123!'
```

输出示例：

```text
$argon2id$v=19$m=65536,t=3,p=4$...
```

将该字符串填入 `users_database.yml` 中的 `password` 字段即可（容器会自动热加载）。

### 步骤 3：网关 ForwardAuth 集成

在 Traefik 中配合中间件即可一键保护任意后端服务：

```yaml
http:
  middlewares:
    authelia:
      forwardAuth:
        address: http://authelia:9091/api/authz/forward-auth
        trustForwardHeader: true
        authResponseHeaders:
          - Remote-User
          - Remote-Groups
          - Remote-Name
          - Remote-Email
```
