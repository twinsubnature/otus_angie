# Установка Angie в Docker с модулями Brotli и Zstandard

## 1. Файлы проекта

В каталоге `~/angie-lab` используются следующие файлы:

- `Dockerfile`
- `angie.conf`
- `modules.conf`
- `site.conf`
- `html/test.txt`

## 2. Создание `angie.conf`

> **Примечание:** в исходном документе этот фрагмент обрывается внутри блока `http`, а завершающий маркер `EOF` отсутствует. Ниже сохранён исходный фрагмент; это не полный конфигурационный файл.

```bash
cd ~/angie-lab

cat > angie.conf <<'EOF'
include /etc/angie/compression-modules.conf;

user angie;
worker_processes auto;
pid /tmp/angie.pid;

error_log /dev/stderr notice;

events {
    worker_connections 1024;
}

http {
    include /etc/angie/mime.types;
    default_type application/octet-stream;

    access_log /dev/stdout;
    sendfile on;
```

## 3. Создание `Dockerfile`

Команда для записи файла:

```bash
cat > ~/angie-lab/Dockerfile
```

Содержимое файла:

```dockerfile
FROM docker.angie.software/angie:1.12.4-ubuntu

COPY modules.conf /etc/angie/compression-modules.conf
COPY angie.conf /etc/angie/angie.conf
COPY site.conf /etc/angie/site.conf
COPY html/ /usr/share/angie/html/

RUN angie -t

EXPOSE 8081

CMD ["angie", "-g", "daemon off;"]
```

## 4. Сборка Docker-образа

```bash
cd ~/angie-lab
sudo docker build --pull -t angie-brotli-zstd:local .
```

## 5. Запуск контейнера

```bash
sudo docker run -d \
    --name angie-compression \
    --restart unless-stopped \
    -p 127.0.0.1:8080:8081 \
    angie-brotli-zstd:local
```

## 6. Проверка контейнера

### Состояние контейнера

```bash
sudo docker ps -a
```

Пример вывода:

```text
CONTAINER ID   IMAGE                     COMMAND                  CREATED          STATUS          PORTS                              NAMES
cb2446b6b0a5   angie-brotli-zstd:local   "angie -g 'daemon of…"   35 seconds ago   Up 35 seconds   80/tcp, 127.0.0.1:8080->8081/tcp   angie-compression
```

### Конфигурация и журналы

```bash
sudo docker exec angie-compression angie -t
sudo docker logs --tail 50 angie-compression
```

Пример вывода:

```text
angie: the configuration file /etc/angie/angie.conf syntax is ok
angie: configuration file /etc/angie/angie.conf test is successful
2026/11/17 18:33:56 [notice] 1#1: using the "epoll" event method
2026/11/17 18:33:56 [notice] 1#1: Angie/1.12.4
2026/11/17 18:33:56 [notice] 1#1: built on Fri, 16 Oct 2026 09:37:01 GMT
2026/11/17 18:33:56 [notice] 1#1: OS: Linux 6.6.87.2-microsoft-standard-WSL2
2026/11/17 18:33:56 [notice] 1#1: getrlimit(RLIMIT_NOFILE): 1024:1048576
2026/11/17 18:33:56 [notice] 1#1: start worker processes
2026/11/17 18:33:56 [notice] 1#1: start worker process 7
2026/11/17 18:33:56 [notice] 1#1: start worker process 8
2026/11/17 18:33:56 [notice] 1#1: start worker process 9
2026/11/17 18:33:56 [notice] 1#1: start worker process 10
2026/11/17 18:33:56 [notice] 1#1: start worker process 11
2026/11/17 18:33:56 [notice] 1#1: start worker process 12
2026/11/17 18:33:56 [notice] 1#1: start worker process 13
2026/11/17 18:33:56 [notice] 1#1: start worker process 14
```

## 7. Проверка сжатия

Тестовый адрес: <http://localhost:8080/test.txt>.

Задайте адрес в переменной:

```bash
URL=http://localhost:8080/test.txt
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
curl -sS -D - -o /dev/null -H 'Accept-Encoding: br' http://localhost:8080/test.txt
```

Пример ответа:

```http
HTTP/1.1 200 OK
Server: Angie/1.12.4
Date: Tue, 17 Nov 2026 18:48:40 GMT
Content-Type: text/plain
Last-Modified: Tue, 17 Nov 2026 17:06:26 GMT
Transfer-Encoding: chunked
Connection: keep-alive
ETag: W/"6afc8992-16760"
Vary: Accept-Encoding
Content-Encoding: br
```

**Zstandard:**

```bash
curl -sS -D - -o /dev/null -H 'Accept-Encoding: zstd' http://localhost:8080/test.txt
```

Пример ответа:

```http
HTTP/1.1 200 OK
Server: Angie/1.12.4
Date: Tue, 17 Nov 2026 18:51:24 GMT
Content-Type: text/plain
Last-Modified: Tue, 17 Nov 2026 17:06:26 GMT
Transfer-Encoding: chunked
Connection: keep-alive
ETag: W/"6afc8992-16760"
Vary: Accept-Encoding
Content-Encoding: zstd
```
