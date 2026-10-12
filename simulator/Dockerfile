# ==============================================================================
# 阶段 1: 单文件依赖打包 (Bun Builder)
# ==============================================================================
FROM oven/bun:1.4-alpine AS builder
WORKDIR /app

# 优先拷贝依赖定义文件以最大化利用 Docker 缓存层
COPY package.json bun.lock ./

# 安装生产环境依赖
RUN bun install --frozen-lockfile --production

# 仅拷贝源码目录
COPY src/ ./src/

# 将全部第三方依赖与应用源码混淆打包为单个极简 JS 文件，彻底剔除 node_modules
RUN bun build --minify --target=bun src/index.js --outfile /app/app.js

# ==============================================================================
# 阶段 2: 极轻量高安全最终运行镜像 (Bun 1.4 Alpine Runner, ~90MB)
# ==============================================================================
FROM oven/bun:1.4-alpine AS runner
WORKDIR /app

# 直接复用官方镜像预置的非特权安全用户 bun (UID 1000)
USER bun

# 仅从构建阶段拷贝打包好的单文件并赋予 bun 属主
COPY --from=builder --chown=bun:bun /app/app.js ./app.js

# 环境变量默认值 (支持 Compose / .env 覆盖)
ENV MQTT_HOST=mosquitto \
    MQTT_PORT=1883 \
    MQTT_USERNAME=admin \
    MQTT_PASSWORD=admin123! \
    DEVICE_NO=VM-BJ-001,VM-BJ-002,VM-BJ-003 \
    REPORT_INTERVAL=10000 \
    MQTT_MAX_RECONNECTS=5 \
    NODE_ENV=production

# 使用 Bun 原生极速启动单文件应用
CMD ["bun", "run", "app.js"]
