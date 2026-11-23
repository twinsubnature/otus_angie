#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

case "${1:-}" in
    before) phase=before; port=18082; expected_server=nginx ;;
    preview) phase=preview; port=18083; expected_server=Angie ;;
    after) phase=after; port=18082; expected_server=Angie ;;
    *) echo "Usage: bash lab/check.sh before|preview|after" >&2; exit 2 ;;
esac

mkdir -p "checks/$phase"
base="http://127.0.0.1:$port"

fetch() {
    local route=$1
    local name=$2
    local status
    status=$(curl --silent --show-error --retry 3 --retry-connrefused --max-time 5 \
        --dump-header "checks/$phase/$name.headers" --output "checks/$phase/$name.body" \
        --write-out '%{http_code}' "$base$route")
    if [[ $status != 200 ]]; then
        printf '%s returned HTTP %s\n' "$base$route" "$status" >&2
        return 1
    fi
    grep -Ei "^server: $expected_server([/[:space:]]|$)" "checks/$phase/$name.headers"
}

fetch / home
fetch /migration-probe.txt static
cmp nginx/html/index.html "checks/$phase/home.body"
cmp lab/site/migration-probe.txt "checks/$phase/static.body"
grep -Ei '^cache-control: .*immutable' "checks/$phase/static.headers"

curl --fail --silent --show-error --max-time 5 \
    -H 'Accept-Encoding: br' -D "checks/$phase/brotli.headers" -o /dev/null \
    "$base/migration-probe.txt"
grep -Ei '^content-encoding: br[[:space:]]*$' "checks/$phase/brotli.headers"

if [[ $phase != before ]]; then
    cmp checks/before/home.body "checks/$phase/home.body"
    cmp checks/before/static.body "checks/$phase/static.body"
    echo 'Тела ответов Nginx и Angie совпадают байт в байт'
fi
printf '%s: HTTP 200, главная страница, статика, Cache-Control и Brotli проверены\n' "$phase"
