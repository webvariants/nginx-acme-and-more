FROM golang:1 AS signal

COPY signal/main.go /app/main.go

RUN cd /app && go get -d ./... && CGO_ENABLED=0 GOOS=linux go build -a -ldflags '-s -w -extldflags "-static"' .

FROM alpine:3.10 AS files

RUN mkdir -p /rootfs/etc/nginx && \
    cd /rootfs/etc/nginx && \
    mkdir -p /rootfs/etc/bot-blocker/bots.d /rootfs/etc/bot-blocker/conf.d && \
    ln -s ../bot-blocker/bots.d . && \
    ln -s ../bot-blocker/conf.d bots-conf.d && \
    touch /rootfs/etc/nginx/bots-conf.d/botblocker-nginx-settings.conf && \
    touch /rootfs/etc/nginx/bots-conf.d/globalblacklist.conf && \
    touch /rootfs/etc/nginx/bots.d/blockbots.conf && \
    touch /rootfs/etc/nginx/bots.d/ddos.conf

COPY --from=signal /app/app /rootfs/usr/local/bin/docker-signal

COPY /docker/passwd /docker/group /rootfs/etc/
COPY /docker/mime.types /rootfs/etc/nginx/mime.types
COPY /nginx.conf /rootfs/etc/nginx/
COPY /include/ /rootfs/etc/nginx/include/
COPY /docker/default.conf /rootfs/etc/nginx/conf.d/
COPY /docker/cron-acme /docker/cron-bot-blocker /docker/update-bot-blocker /docker/cron-rotate-log /docker/rotate-log /rootfs/usr/local/bin/

FROM alpine:3.10

ARG NGINX_VERSION="1.17.2"
ARG GPG_KEYS="B0F4253373F8F6F510D42178520A9993A1C052F8"
ARG MODSECURITY_VERSION="3.0.3"
ARG MODSECURITY_SHA256="8aa1300105d8cc23315a5e54421192bc617a66246ad004bd89e67c232208d0f4"
ARG MODSECURITY_CRS_VERSION="3.1.1"
ARG NGX_BROTLI_COMMIT="8104036af9cff4b1d34f22d00ba857e2a93a243c"

ARG NGINX_CONFIG="\
    --sbin-path=/usr/local/bin/nginx \
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
    --with-http_gzip_static_module \
    --with-threads"

RUN apk add --update --no-cache \
      ca-certificates \
      coreutils \
      openssl \
      pcre \
      zlib \
      libaio \
      libxml2 \
      libstdc++ \
      yajl \
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
      libxml2-dev \
      linux-headers \
      libcap \
      curl \
    && \
    cd /tmp && \
    curl -fSL https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz -o nginx.tar.gz && \
    curl -fSL https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz.asc -o nginx.tar.gz.asc && \
    curl -fSL https://github.com/SpiderLabs/ModSecurity/releases/download/v$MODSECURITY_VERSION/modsecurity-v$MODSECURITY_VERSION.tar.gz -o modsecurity.tar.gz && \
    git clone --recursive https://github.com/eustas/ngx_brotli.git && \
    cd ngx_brotli && \
	  git checkout -b $NGX_BROTLI_COMMIT $NGX_BROTLI_COMMIT && \
    cd .. && \
    if [ "$MODSECURITY_SHA256" != "$(sha256sum modsecurity.tar.gz | awk '{print $1}')" ]; then exit 1; fi && \
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
    tar xzf modsecurity.tar.gz && \
    rm modsecurity.tar.gz && \
    mv /tmp/modsecurity-v$MODSECURITY_VERSION /tmp/modsecurity && \
    cd /tmp/modsecurity && \
    export MAKEFLAGS="-j $(grep -c ^processor /proc/cpuinfo)" && \
    ./configure --enable-standalone-module && \
    make && \
    make install && \
    strip /usr/local/modsecurity/lib/libmodsecurity.so.3.0.3 && \
    rm -rf /usr/local/modsecurity/lib/*.a /usr/local/modsecurity/lib/*.la && \
    mkdir -p /usr/share/modsecurity && \
    cp /tmp/modsecurity/modsecurity.conf-recommended /usr/share/modsecurity/modsecurity.conf && \
    cp /tmp/modsecurity/unicode.mapping /usr/share/modsecurity/unicode.mapping && \
    rm -rf /tmp/modsecurity && \
    cd /tmp && \
    git clone https://github.com/SpiderLabs/ModSecurity-nginx && \
    cd ModSecurity-nginx && git checkout d7101e13685efd7e7c9f808871b202656a969f4b && \
    cd /tmp/nginx && \
    ./configure $NGINX_CONFIG --add-module=../ModSecurity-nginx --add-module=../ngx_brotli && \
    make && \
    mv /tmp/nginx/objs/nginx /usr/local/bin/nginx && \
    /usr/sbin/setcap cap_net_bind_service+ep /usr/local/bin/nginx && \
    rm -rf /tmp/nginx /tmp/ModSecurity-nginx /tmp/ngx_brotli && \
    apk del .build-deps && \
    mkdir -p /var/log/nginx && cd /var/log/nginx && ln -s /dev/stderr error.log && ln -s /dev/stdout access.log && ln -s /dev/stderr modsec_audit.log && \
    rm -rf /usr/share/terminfo && \
    ldd /usr/local/modsecurity/lib/libmodsecurity.so.3 && \
    cd /usr/local/share && \
    curl -L https://github.com/SpiderLabs/owasp-modsecurity-crs/archive/v$MODSECURITY_CRS_VERSION.tar.gz | tar xz && \
    mv owasp-modsecurity-crs-$MODSECURITY_CRS_VERSION modsecurity-crs && \
    rm -rf modsecurity-crs/util && \
    cp /usr/share/modsecurity/unicode.mapping modsecurity-crs/ && \
    sed -e 's#/var/log/#/var/log/nginx/#g' -e 's#SecStatusEngine On#SecStatusEngine Off#g' /usr/share/modsecurity/modsecurity.conf > modsecurity-crs/owasp-modsecurity.conf && \
    echo 'SecAction "id:900990, phase:1, nolog, pass, t:none, setvar:tx.crs_setup_version=310"' >> modsecurity-crs/owasp-modsecurity.conf && \
    echo "Include /usr/local/share/modsecurity-crs/rules/*.conf" >> modsecurity-crs/owasp-modsecurity.conf && \
    rm /usr/local/share/modsecurity-crs/rules/REQUEST-910-IP-REPUTATION.conf

ENV LE_WORKING_DIR=/usr/local/bin \
    LE_CONFIG_HOME=/etc/ssl/acme.sh \
    PS1="🐳  \u@\h \W \\$ "

RUN curl https://get.acme.sh | sh && rm -rf "$LE_WORKING_DIR/deploy" "$LE_CONFIG_HOME/account.conf" "/etc/crontabs/cron.update" && find /tmp/ -type f -delete && acme.sh --uninstallcronjob && rmdir /etc/ssl/acme.sh

RUN curl https://raw.githubusercontent.com/mcnilz/minicron/master/minicron > /usr/local/bin/minicron && chmod +x /usr/local/bin/minicron

COPY --from=files /rootfs/ /

USER nginx

CMD ["nginx", "-g", "daemon off;"]
