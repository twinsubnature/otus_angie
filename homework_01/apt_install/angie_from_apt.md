# Установка Angie из пакетов с модулями Brotli и Zstandard

## 1. Подготовка общих файлов для проекта

```bash
mkdir -p ~/angie-lab/html
cd ~/angie-lab
```

## 2. Создание файла модулей `modules.conf`

```bash
cat > modules.conf <<'EOF'
load_module modules/ngx_http_brotli_filter_module.so;
load_module modules/ngx_http_brotli_static_module.so;

load_module modules/ngx_http_zstd_filter_module.so;
load_module modules/ngx_http_zstd_static_module.so;
EOF
```

## 3. Создание конфигурационного файла `site.conf`

```bash
cat > site.conf <<'EOF'
server {
    listen 8081;
    server_name _;
    root /usr/share/angie/html;

    brotli on;
    brotli_comp_level 5;
    brotli_min_length 256;
    brotli_static on;
    brotli_types
        text/plain text/css text/javascript
        application/javascript application/json
        application/xml image/svg+xml;

    zstd on;
    zstd_comp_level 3;
    zstd_min_length 256;
    zstd_static on;
    zstd_types
        text/plain text/css text/javascript
        application/javascript application/json
        application/xml image/svg+xml;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF
```

## 4. Создание тестового файла с наполнением

```bash
awk 'BEGIN {
    for (i = 0; i < 2000; i++)
        print "Angie compression test: Brotli and Zstandard."
}' > html/test.txt
```

## 5. Установка пакетов из репозитория

```bash
sudo apt update
sudo apt install -y ca-certificates curl

sudo install -d -m 0755 /etc/apt/keyrings

sudo curl -fsSL \
    https://angie.software/keys/angie-signing.gpg \
    -o /etc/apt/keyrings/angie-signing.gpg

sudo chmod 0644 /etc/apt/keyrings/angie-signing.gpg

echo "deb [signed-by=/etc/apt/keyrings/angie-signing.gpg] https://download.angie.software/angie/$(. /etc/os-release && echo "$ID/$VERSION_ID $VERSION_CODENAME") main" \
    | sudo tee /etc/apt/sources.list.d/angie.list

sudo apt update
sudo apt install -y angie angie-module-brotli angie-module-zstd
```

## 6. Подключение конфигурации и модулей

```bash
cd ~/angie-lab

sudo cp -a /etc/angie/angie.conf /etc/angie/angie.conf.bak

sudo install -m 0644 modules.conf /etc/angie/compression-modules.conf
sudo install -d -m 0755 /etc/angie/http.d
sudo install -m 0644 site.conf /etc/angie/http.d/compression-demo.conf

sudo install -d -m 0755 /usr/share/angie/html
sudo install -m 0644 html/test.txt /usr/share/angie/html/test.txt

sudo sed -i \
    '1iinclude /etc/angie/compression-modules.conf;' \
    /etc/angie/angie.conf
```

## 7. Проверка конфигурации, запуск и автозапуск Angie

```bash
sudo angie -t &&
sudo systemctl enable --now angie &&
sudo systemctl reload angie

systemctl status angie --no-pager
```

## 8. Тестовый адрес

<http://localhost:8081/test.txt>

Пример страницы приветствия из исходных заметок:

```text
Welcome to Angie!
If you see this page, the Angie web server is successfully installed and working. Further configuration is required.

For online documentation and support please refer to angie.software.

Thank you for using Angie.
```

## 9. Проверка сжатия

Задайте адрес в переменной:

```bash
URL=http://localhost:8081/test.txt
```

Пример содержимого тестового файла:

```text
Angie compression test: Brotli and Zstandard.
Angie compression test: Brotli and Zstandard.
Angie compression test: Brotli and Zstandard.
Angie compression test: Brotli and Zstandard.
Angie compression test: Brotli and Zstandard.
Angie compression test: Brotli and Zstandard.
Angie compression test: Brotli and Zstandard.
Angie compression test: Brotli and Zstandard.
```

### Запросы через переменную `URL`

```bash
# Brotli
curl -sS -D - -o /dev/null \
    -H 'Accept-Encoding: br' "$URL"

# Zstandard
curl -sS -D - -o /dev/null \
    -H 'Accept-Encoding: zstd' "$URL"
```

Примеры HTTP-ответов:

```http
HTTP/1.1 200 OK
Server: Angie/1.12.4
Date: Tue, 17 Nov 2026 18:45:31 GMT
Content-Type: text/plain
Last-Modified: Tue, 17 Nov 2026 17:08:04 GMT
Transfer-Encoding: chunked
Connection: keep-alive
ETag: W/"6afc89f4-16760"
Vary: Accept-Encoding
Content-Encoding: br

HTTP/1.1 200 OK
Server: Angie/1.12.4
Date: Tue, 17 Nov 2026 18:45:31 GMT
Content-Type: text/plain
Last-Modified: Tue, 17 Nov 2026 17:08:04 GMT
Transfer-Encoding: chunked
Connection: keep-alive
ETag: W/"6afc89f4-16760"
Vary: Accept-Encoding
Content-Encoding: zstd
```

### Запросы с явным адресом

**Brotli:**

```bash
curl -sS -D - -o /dev/null -H 'Accept-Encoding: br' http://localhost:8081/test.txt
```

Пример ответа:

```http
HTTP/1.1 200 OK
Server: Angie/1.12.4
Date: Tue, 17 Nov 2026 18:48:27 GMT
Content-Type: text/plain
Last-Modified: Tue, 17 Nov 2026 17:08:04 GMT
Transfer-Encoding: chunked
Connection: keep-alive
ETag: W/"6afc89f4-16760"
Vary: Accept-Encoding
Content-Encoding: br
```

**Zstandard:**

```bash
curl -sS -D - -o /dev/null -H 'Accept-Encoding: zstd' http://localhost:8081/test.txt
```

Пример ответа:

```http
HTTP/1.1 200 OK
Server: Angie/1.12.4
Date: Tue, 17 Nov 2026 18:51:17 GMT
Content-Type: text/plain
Last-Modified: Tue, 17 Nov 2026 17:08:04 GMT
Transfer-Encoding: chunked
Connection: keep-alive
ETag: W/"6afc89f4-16760"
Vary: Accept-Encoding
Content-Encoding: zstd
```

## 10. Дополнительные команды

### Остановка и отключение автозапуска

```bash
sudo systemctl disable --now angie
```

Проверка:

```bash
systemctl is-active angie
systemctl is-enabled angie
```

### Остановка службы

```bash
sudo systemctl stop angie
```

Проверка:

```bash
systemctl is-active angie
```
