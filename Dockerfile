# You can pin a specific FrankenPHP tag by overriding this ARG at build time.
# Example: docker build --build-arg FRANKENPHP_IMAGE=dunglas/frankenphp:1.3.1-alpine .
ARG FRANKENPHP_IMAGE=dunglas/frankenphp:php8.3-alpine

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
ARG VERSION="8.3-alpine"
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

# Secure Composer install (pin version via ARG if desired)
ARG COMPOSER_VERSION=2.7.7
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
 && php -r "copy('https://composer.github.io/installer.sig', 'composer-setup.sig');" \
 && php -r "if (trim(file_get_contents('composer-setup.sig')) !== hash_file('SHA384', 'composer-setup.php')) { fwrite(STDERR, 'Invalid installer signature'.PHP_EOL); exit(1); }" \
 && php composer-setup.php --quiet --install-dir=/usr/local/bin --filename=composer --version=${COMPOSER_VERSION} \
 && rm composer-setup.php composer-setup.sig

# Install packages in a single layer
RUN apk add --no-cache \
      git \
      openssh-client \
      rsync \
      curl \
      tzdata \
      shadow \
      su-exec

# Supervisord healthcheck script (optional) and supercronic
COPY --chmod=755 healthcheck-supervisor /usr/local/bin/healthcheck-supervisor
# Add supercronic from build stage
COPY --from=supercronic-build /go/bin/supercronic /usr/local/bin/supercronic

# Base php ini
COPY --chmod=644 docker-base.ini /usr/local/etc/php/conf.d/docker-base.ini

# Composer cache
ENV COMPOSER_HOME=/home/www-data/.composer
VOLUME ["/home/www-data/.composer"]

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
