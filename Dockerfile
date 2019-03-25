FROM golang:1 AS signal

COPY signal/main.go /app/main.go

RUN cd /app && go get -d ./... && CGO_ENABLED=0 GOOS=linux go build -a -ldflags '-s -w -extldflags "-static"' .

FROM alpine:3.9 AS build

ARG NGINX_VERSION="1.15.9"
ARG GPG_KEYS="B0F4253373F8F6F510D42178520A9993A1C052F8"

ARG NGINX_CONFIG="\
    --sbin-path=/nginx \
    --conf-path=/etc/nginx/nginx.conf \
    --pid-path=/tmp/nginx.pid \
    --http-log-path=/dev/stdout \
    --error-log-path=/dev/stdout \
    --http-client-body-temp-path=/tmp/client_temp \
    --http-proxy-temp-path=/tmp/proxy_temp \
    --http-fastcgi-temp-path=/tmp/fastcgi_temp \
    --http-uwsgi-temp-path=/tmp/uwsgi_temp \
    --http-scgi-temp-path=/tmp/scgi_temp \
    --with-file-aio \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-stream \
    --with-stream_ssl_module \
    --with-http_stub_status_module \
    --with-threads"

RUN apk add --update --no-cache \
      ca-certificates \
      openssl \
      pcre \
      zlib \
      libaio \
      bash \
      curl \
      git \
    && \
    apk add --update --no-cache --virtual .build-deps \
      gnupg1 \
      build-base \
      openssl-dev \
      pcre-dev \
      zlib-dev \
      libaio-dev \
      linux-headers \
      libcap \
      curl \
    && \
    cd /tmp && \
    curl -fSL https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz -o nginx.tar.gz && \
    curl -fSL https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz.asc -o nginx.tar.gz.asc && \
    export GNUPGHOME="$(mktemp -d)" && \
    found=''; \
    for server in \
      ha.pool.sks-keyservers.net \
      hkp://keyserver.ubuntu.com:80 \
      hkp://p80.pool.sks-keyservers.net:80 \
      pgp.mit.edu \
    ; do \
      echo "Fetching GPG key $GPG_KEYS from $server"; \
      gpg --keyserver "$server" --keyserver-options timeout=10 --recv-keys "$GPG_KEYS" && found=yes && break; \
    done; \
    test -z "$found" && echo >&2 "error: failed to fetch GPG key $GPG_KEYS" && exit 1; \
    gpg --batch --verify nginx.tar.gz.asc nginx.tar.gz && \
    tar xzf nginx.tar.gz && \
    mv /tmp/nginx-$NGINX_VERSION /tmp/nginx && \
    rm -rf "$GNUPGHOME" nginx.tar.gz.asc nginx.tar.gz && \
    cd /tmp/nginx && \
    ./configure $NGINX_CONFIG && \
    make && \
    mv /tmp/nginx/objs/nginx /usr/local/bin/nginx && \
    /usr/sbin/setcap cap_net_bind_service+ep /usr/local/bin/nginx && \
    rm -rf /tmp/nginx && \
    apk del .build-deps && \
    mkdir -p /var/log/nginx && cd /var/log/nginx && ln -s /dev/stderr error.log && ln -s /dev/stdout access.log

ENV LE_WORKING_DIR=/usr/local/bin \
    LE_CONFIG_HOME=/etc/ssl/acme.sh
RUN curl https://get.acme.sh | sh && rm -rf "$LE_WORKING_DIR/deploy" "$LE_CONFIG_HOME/account.conf" "/etc/crontabs/cron.update" && find /tmp/ -type f -delete && acme.sh --uninstallcronjob

RUN curl https://raw.githubusercontent.com/mcnilz/minicron/master/minicron > /usr/local/bin/minicron && chmod +x /usr/local/bin/minicron

RUN mkdir -p /etc/nginx && \
    cd /etc/nginx && \
    mkdir -p /etc/bot-blocker/bots.d /etc/bot-blocker/conf.d && \
    ln -s /etc/bot-blocker/bots.d . && \
    ln -s /etc/bot-blocker/conf.d bots-conf.d && \
    touch /etc/nginx/bots.d/blockbots.conf && \
    touch /etc/nginx/bots.d/ddos.conf

COPY --from=signal /app/app /usr/local/bin/docker-signal

COPY /docker/passwd /docker/group /etc/
COPY /docker/mime.types /etc/nginx/mime.types
COPY /nginx.conf /etc/nginx/
COPY /include/ /etc/nginx/include/
COPY /docker/default.conf /etc/nginx/conf.d/
COPY /docker/cron-acme /docker/cron-bot-blocker /docker/update-bot-blocker /usr/local/bin/

USER nginx

CMD ["nginx", "-g", "daemon off;"]
