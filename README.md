# Nginx acme and more

[![](https://images.microbadger.com/badges/image/webvariants/nginx-acme-and-more.svg)](https://microbadger.com/images/webvariants/nginx-acme-and-more "Get your own image badge on microbadger.com")

## Features

- nginx
- acme.sh
- nginx-ultimate-bad-bot-blocker
- modsecurity 3.0.3
- modsecurity crs 3.1.0
- (minicron)
- (docker-signal)
- (docker-compose)

## Setup

```bash
    # pull image
    ./docker-compose pull

    # create directories, .env and install nginx-ultimate-bad-bot-blocker
    ./init

    # copy default vhosts on port 80 to
    cp .conf.d-example/000-default.conf .conf.d-example/999-last.conf .conf.d/

    # start with minimal config
    ./docker-compose up -d

    # get nginx container name and add to .env
    echo SIGNAL_CONTAINER=$(./docker-compose ps nginx | tail -n 1 | cut -d' '  -f1) >> .env
    ./docker-compose up -d

    # get certificate for "live app" (change to your domain)
    ./docker-compose exec nginx acme.sh --issue -d example.com -w /usr/share/nginx/html

    # create vhost for "live app" (change to your domain)
    sed -e 's/INSERT-DEFAULT-DOMAIN/example.com/g' conf.d-example/001-live.conf > conf.d/001-live.conf

    # create default vhost on port 443 (change to your domain)
    sed -e 's/INSERT-DEFAULT-DOMAIN/example.com/g' conf.d-example/000-default-ssl.conf > conf.d/000-default-ssl.conf

    # start your "live app" with docker and connect to the network of this stack
    # edit conf.d/001-live.conf and change "live:80" to container name and port of you live app
    # look for an example app in example-app/docker-compose.yml

    # reload nginx config through HUP signal
    ./docker-compose kill -s HUP nginx

    # open live app (change to your domain)
    curl http://example.com
```