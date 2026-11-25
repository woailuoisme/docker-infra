FROM oven/bun:1.4-alpine AS build
WORKDIR /app
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile
COPY src ./src
# 依赖与源码打包成单文件，运行镜像不需要 node_modules
RUN bun build --minify --target=bun src/index.js --outfile app.js

FROM oven/bun:1.4-alpine
WORKDIR /app
COPY --from=build --chown=bun:bun /app/app.js ./app.js
USER bun

ENV MQTT_HOST=mosquitto \
    MQTT_PORT=1883 \
    MQTT_USERNAME=admin \
    MQTT_PASSWORD=admin123! \
    DEVICE_NO=VM-BJ-001,VM-BJ-002,VM-BJ-003 \
    REPORT_INTERVAL=10000 \
    MQTT_MAX_RECONNECTS=5 \
    NODE_ENV=production

CMD ["bun", "app.js"]
