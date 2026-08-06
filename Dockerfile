# syntax=docker/dockerfile:1.7
# You can pin a specific FrankenPHP tag by overriding this ARG at build time.
# Example: docker build --build-arg FRANKENPHP_IMAGE=dunglas/frankenphp:1.3.1-alpine .
ARG FRANKENPHP_IMAGE=dunglas/frankenphp:php8.5-alpine

# Build supercronic in a separate stage to support multiple architectures
FROM golang:1.22-alpine AS supercronic-build
ARG SUPERCRONIC_VERSION=v0.2.29
RUN apk add --no-cache git \
 && go install github.com/aptible/supercronic@${SUPERCRONIC_VERSION}

FROM ${FRANKENPHP_IMAGE}

# OCI labels (overridable via build args)
ARG PROJECT_TITLE="FrankenPHP for Symfony"
ARG PROJECT_DESCRIPTION="FrankenPHP with PHP extensions and Caddy"
ARG PROJECT_LICENSE="MIT"
ARG VERSION="8.5-alpine"
ARG VCS_REF=""
ARG BUILD_DATE=""

LABEL \
  org.opencontainers.image.title="$PROJECT_TITLE" \
  org.opencontainers.image.description="$PROJECT_DESCRIPTION" \
  org.opencontainers.image.licenses="$PROJECT_LICENSE" \
  org.opencontainers.image.version="$VERSION" \
  org.opencontainers.image.revision="$VCS_REF" \
  org.opencontainers.image.created="$BUILD_DATE"

# Copy Caddy configuration
COPY --chmod=644 Caddyfile /etc/caddy/Caddyfile

# Install PHP extensions
RUN install-php-extensions \
    apcu \
    bz2 \
    dom \
    exif \
    fileinfo \
    gd \
    intl \
    opcache \
    pcntl \
    pdo \
    pdo_mysql \
    pdo_sqlite \
    session \
    simplexml \
    xml \
    xsl \
    zip

# Install packages in a single layer
RUN apk add --no-cache \
      git \
      openssh-client \
      rsync \
      curl \
      tzdata \
      shadow \
      su-exec

# Bake SSH key from BuildKit secret into image (for internal/private use cases).
RUN --mount=type=secret,id=id_rsa \
    mkdir -p /home/www-data/.ssh \
 && cp /run/secrets/id_rsa /home/www-data/.ssh/id_rsa \
 && chmod 700 /home/www-data/.ssh \
 && chmod 600 /home/www-data/.ssh/id_rsa \
 && touch /home/www-data/.ssh/known_hosts \
 && ssh-keyscan -t rsa,ecdsa,ed25519 -H bitbucket.org >> /home/www-data/.ssh/known_hosts \
 && ssh-keyscan -t rsa,ecdsa,ed25519 -H github.com >> /home/www-data/.ssh/known_hosts \
 && chown -R www-data:www-data /home/www-data/.ssh

# Composer (deterministic): use official binary
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

# Use a non-volume path for Composer cache/home and make it writable
ENV COMPOSER_HOME=/var/www/.composer
RUN mkdir -p "$COMPOSER_HOME" && chmod 0777 "$COMPOSER_HOME"

# Supervisord healthcheck script (optional) and supercronic
COPY --chmod=755 healthcheck-supervisor /usr/local/bin/healthcheck-supervisor
# Add supercronic from build stage
COPY --from=supercronic-build /go/bin/supercronic /usr/local/bin/supercronic

# Base php ini
COPY --chmod=644 docker-base.ini /usr/local/etc/php/conf.d/docker-base.ini

# Utility scripts
COPY --chmod=755 wait-for /usr/local/bin/wait-for
COPY --chmod=755 entrypoint-cron /usr/local/bin/entrypoint-cron
COPY --chmod=755 entrypoint-chuid /usr/local/bin/entrypoint-chuid
ENTRYPOINT ["entrypoint-chuid"]

ENV SERVER_NAME=:80

# Default app healthcheck tries /health first, then falls back to root
# You can override this from docker-compose to use the supervisor healthcheck if needed.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -fsS http://127.0.0.1/health || curl -fsS http://127.0.0.1/ || exit 1

CMD ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]
