FROM crowdsecurity/crowdsec:v1.8.1-slim

# 预置环境并预装 Traefik 解析器与防御规则集合 (构建期固化，消除容器冷启动联网下载)
RUN mkdir -p /etc/crowdsec /var/lib/crowdsec/data && \
    cp -r /staging/etc/crowdsec/* /etc/crowdsec/ && \
    cscli hub update && \
    cscli collections install \
        crowdsecurity/traefik \
        crowdsecurity/http-cve \
        crowdsecurity/whitelist-good-actors \
        crowdsecurity/base-http-scenarios \
        crowdsecurity/appsec-virtual-patching \
        crowdsecurity/appsec-generic-rules && \
    cp -r /etc/crowdsec/* /staging/etc/crowdsec/ && \
    mkdir -p /staging/var/lib/crowdsec/data && \
    cp -r /var/lib/crowdsec/data/* /staging/var/lib/crowdsec/data/

# 静态内置配置与自定义规则初始备份
COPY config/ /etc/crowdsec/
COPY config/ /staging/etc/crowdsec/
