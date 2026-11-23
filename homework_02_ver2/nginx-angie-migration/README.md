# Миграция сайта из nginx_conf.tar с Nginx на Angie в Docker

В этой лабораторной исходный сайт берётся из `nginx_conf.tar`. Сначала Nginx отвечает на `http://127.0.0.1:18082/`, затем тот же сайт проверяется через Angie на `18083`. После проверки Angie занимает исходный порт `18082`.

## 1. Распаковать архив сайта и комплект лабораторной

Выполняй команды в Ubuntu из каталога, где лежат `nginx_conf.tar` и `nginx-angie-migration-kit.zip`. Нужны работающий Docker Engine, Compose v2, `curl` и `unzip`. Первая сборка скачивает образы и пакеты.

```bash
sudo docker compose version
sudo docker info
```

Если Docker не запущен, на Ubuntu с systemd используй `sudo systemctl start docker`. Для локального Docker Engine без systemd запусти `sudo dockerd` в отдельном терминале и оставь его открытым. Команды лабораторной выполняй во втором терминале. [Запуск Docker Engine](https://docs.docker.com/engine/daemon/start/)

```bash
mkdir -p "$HOME/nginx-angie-migration"
tar --keep-old-files -xf nginx_conf.tar -C "$HOME/nginx-angie-migration"
unzip -n nginx-angie-migration-kit.zip -d "$HOME/nginx-angie-migration"
```

Если `~/nginx-angie-migration/nginx/nginx.conf` уже существует после распаковки того же архива, пропусти команду `tar`.

```bash
cd "$HOME/nginx-angie-migration"
ls -l nginx/nginx.conf nginx/sites-available/default nginx/html/index.html

mkdir -p lab/site
cp nginx/html/index.html nginx/html/50x.html lab/site/
awk 'BEGIN { for (i=0; i<100; i++) print "Archive migration: static file and Brotli." }' \
  > lab/site/migration-probe.txt

sudo docker compose --profile '*' config -q
```

Каталог `nginx/` содержит исходные файлы. В `lab/` лежат конфиги для контейнеров, общий виртуальный хост и тестовый бэкенд.

## 2. Запустить исходный Nginx

```bash
sudo docker compose up -d --build nginx &&
sudo docker compose exec -T nginx nginx -t -c /opt/migration/nginx.conf &&
bash lab/check.sh before
```

Порт `18082` должен быть свободен. Если его занимает контейнер из предыдущей лабораторной, проверь это командой `sudo docker ps --filter publish=18082` и останови именно тот контейнер.

Проверка ожидает `HTTP 200` от Nginx для `/` и `/migration-probe.txt`. Она сохраняет тела и заголовки в `checks/before/`. Главная страница сверяется с `nginx/html/index.html`. Для статического файла дополнительно проверяются `Cache-Control: … immutable` и `Content-Encoding: br` при запросе с `Accept-Encoding: br`.

## 3. Проверить Angie на отдельном порту

```bash
sudo docker compose up -d angie-check &&
sudo docker compose exec -T angie-check angie -t -c /opt/migration/angie.conf &&
bash lab/check.sh preview
```

Angie отвечает на `18083`, а Nginx продолжает слушать `18082`. Код `0` команды `cmp` означает, что тела ответов совпали байт в байт. Скрипт проверяет также заголовок `Server: Angie/…`, статику и Brotli.

## 4. Переключить исходный порт на Angie

После успешной проверки на `18083` останови исходный Nginx и запусти рабочий контейнер Angie.

```bash
sudo docker compose stop nginx &&
sudo docker compose up -d angie-live &&
bash lab/check.sh after
```

Миграция проверена, когда исходный URL на `18082` возвращает `200 OK` от Angie, а главная страница и статика совпадают с сохранёнными ответами Nginx. После этого останови временный экземпляр на `18083`.

```bash
sudo docker compose stop angie-check
```

## Откат, диагностика и завершение

Для отката останови рабочий Angie, верни Nginx на `18082` и проверь заголовок ответа.

```bash
sudo docker compose --profile live stop angie-live
sudo docker compose up -d nginx &&
curl -i --max-time 5 http://127.0.0.1:18082/
```

При ошибке запуска посмотри статусы и журналы сервисов проекта.

```bash
sudo docker compose --profile '*' ps -a
sudo docker compose --profile '*' logs --tail=60
```

Чтобы завершить лабораторную, останови контейнеры этого проекта.

```bash
sudo docker compose --profile '*' stop
```

## Что перенесено из архива

| Из архива | В лабораторной |
| --- | --- |
| Четыре HTTP-бэкенда `127.0.0.1:9000–9003` | Те же порты и веса за именем `backend` в сети Compose. Все четыре слушателя отдают HTML из архива. |
| `mime.types`, `static.conf`, `static-avif.conf` | Подключаются из оригинального каталога, смонтированного только для чтения. |
| Gzip, Brotli, директивы прокси и конфигурация кеша | Перенесены в оба варианта главного конфига. Модули Brotli загружаются из пакетов соответствующего сервера. |
| Символическая ссылка `sites-enabled/default` | В архиве она абсолютная. В контейнерах виртуальный хост подключается явной директивой `include /opt/migration/site.conf;`. |
| Маршруты uWSGI и PHP | Директивы сохранены. Самих приложений в архиве нет, поэтому эти маршруты не входят в проверку работоспособности. |

Конфиги не включают Zstd: в исходном архиве его директивы закомментированы. В блоке `location /` директива `proxy_cache one` тоже закомментирована, поэтому проверка проходит через бэкенд и не проверяет попадания в прокси-кеш. Варианты AVIF и WebP сохраняются в конфигурации, но в архиве нет файлов для проверки их выдачи.

[Пакеты Brotli для Nginx в Ubuntu](https://packages.ubuntu.com/source/resolute/libnginx-mod-http-brotli) · [Загрузка Brotli в Angie](https://angie.software/angie/docs/configuration/modules/external-modules/brotli/) · [Образы Angie](https://angie.software/angie/docs/installation/docker/)
