# Миграция тестового сайта с Nginx на Angie

В лабораторной работе на **Ubuntu 26.04** один и тот же HTTP-сайт сначала обслуживал Nginx, затем — пакетный **Angie 1.12.4**. Адрес `http://127.0.0.1:8082/` и содержимое страницы сохранились.

| Что | Где |
| --- | --- |
| Тестовая страница | `/var/www/angie-migration/index.html` |
| Конфиг Nginx | `/etc/nginx/sites-available/angie-migration` |
| Конфиг Angie | `/etc/angie/http.d/angie-migration.conf` |

Команды выполняются в терминале Ubuntu, где установлены оба пакета. Адрес `127.0.0.1` относится к этой же системе.

## 1. Установить Nginx и создать тестовый сайт

```bash
sudo apt update && sudo apt install -y nginx

sudo install -d -m 0755 /var/www/angie-migration
echo 'Migration test page' | sudo tee /var/www/angie-migration/index.html
```

Создать конфиг отдельного сайта.

```bash
sudo tee /etc/nginx/sites-available/angie-migration > /dev/null <<'EOF'
server {
    listen 127.0.0.1:8082;
    server_name localhost;

    root /var/www/angie-migration;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF

sudo ln -s /etc/nginx/sites-available/angie-migration +  /etc/nginx/sites-enabled/angie-migration

sudo nginx -t
```

Если Nginx уже запущен, применить конфигурацию командой `sudo nginx -s reload`. Если он остановлен, запустить его командой `sudo nginx`. После этого проверить исходный ответ.

```bash
curl -i --max-time 5 http://127.0.0.1:8082/
```

Ожидаемый ответ от Nginx — `200 OK`, заголовок `Server: nginx` с возможным указанием версии и текст `Migration test page`.

## 2. Перенести конфиг сайта в Angie

Скопировать блок сайта в каталог, который подключает пакетный Angie. Путь `root` сохраняется, поскольку оба сервера читают одну и ту же страницу на Ubuntu.

```bash
sudo install -m 0644 +  /etc/nginx/sites-available/angie-migration +  /etc/angie/http.d/angie-migration.conf

sudo angie -t &&
sudo angie -T | grep -F 'configuration file /etc/angie/http.d/angie-migration.conf:'
```

Перед переключением проверь, что `angie -t` прошёл успешно и последняя команда показала путь к перенесённому файлу. Если пути в выводе нет, проверь, что внутри блока `http` в `/etc/angie/angie.conf` есть действующая директива `include /etc/angie/http.d/*.conf;` или её эквивалент с относительным путём.

## 3. Переключиться на Angie без systemd

На стенде `systemctl stop nginx` завершился ошибкой `System has not been booted with systemd as init system (PID 1)`. При запуске команд через `&&` эта ошибка прервала цепочку. Для переключения использовались команды самих веб-серверов.

Посмотреть, кто слушает порт `8082`. Если это Nginx, остановить его плавно.

```bash
sudo ss -ltnp 'sport = :8082'
sudo nginx -s quit
sudo ss -ltnp 'sport = :8082'
```

Дождаться, пока последняя команда перестанет показывать слушающий процесс на `8082`. Затем запустить Angie и повторить тот же HTTP-запрос.

```bash
sudo angie &&
curl -i --max-time 5 http://127.0.0.1:8082/
```

## 4. Подтвердить результат

Ключевые строки фактического ответа.

```http
HTTP/1.1 200 OK
Server: Angie/1.12.4
Content-Type: text/html
Content-Length: 20
```

Тело ответа — `Migration test page`. Статус, адрес и содержимое совпали с проверкой до миграции. Заголовок `Server` подтвердил, что запрос обработал **Angie 1.12.4**.

В этой работе Angie запускался вручную через `sudo angie`. Автозапуск не настраивали.

## Откат к Nginx

Если потребуется вернуть Nginx, останови работающий Angie командой `sudo angie -s quit`. Когда `sudo ss -ltnp 'sport = :8082'` покажет, что порт свободен, выполни:

```bash
sudo nginx -t &&
sudo nginx &&
curl -i --max-time 5 http://127.0.0.1:8082/
```

После отката тот же URL снова должен вернуть `200 OK` с заголовком `Server: nginx`.
