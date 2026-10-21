#!/bin/sh
# Smoke test for a freshly built image. Fails if the image would break consumers.
# Usage: ./smoke-test.sh <image>

set -eu
IMAGE="$1"

# Extensions every consumer relies on, as listed by `php -m` (case-insensitive)
EXTENSIONS="apcu bz2 dom exif fileinfo gd intl pcntl pdo_mysql pdo_sqlite session simplexml xml xsl zip"

run() {
    docker run --rm --entrypoint "" "$IMAGE" "$@"
}

fail() {
    echo "[smoke-test] FAIL: $*" >&2
    exit 1
}

run php -v || fail "php -v"

MODULES="$(run php -m)"
for EXT in $EXTENSIONS; do
    echo "$MODULES" | grep -qix "$EXT" || fail "extension missing: $EXT"
done
echo "$MODULES" | grep -qix "Zend OPcache" || fail "extension missing: opcache"

run frankenphp version || fail "frankenphp version"
run frankenphp validate --config /etc/caddy/Caddyfile >/dev/null 2>&1 || fail "Caddyfile validation"
run composer --version || fail "composer"
run sh -c 'command -v supercronic' || fail "supercronic"

# Default entrypoint must survive UID/GID remapping
docker run --rm -e UID=1000 -e GID=1000 "$IMAGE" php -r 'exit(0);' || fail "entrypoint-chuid"

echo "[smoke-test] OK: $IMAGE"
