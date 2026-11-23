# Миграция Nginx → Angie в Docker. Версия 2

Во второй лабораторной переносим сайт из архива,приложенного к задаче. Сначала запускаем Nginx, затем проверяем Angie на отдельном порту и переключаем исходный URL. В рабочем каталоге сохраняем исходные конфиги и результаты сравнения.

| Этап | Сервис Compose | Адрес на хосте |
| --- | --- | --- |
| Исходный Nginx | `nginx` | `http://127.0.0.1:18082/` |
| Проверка Angie | `angie-check` | `http://127.0.0.1:18083/` |
| Angie после переключения | `angie-live` | `http://127.0.0.1:18082/` |

## 1. Скачиваем и распаковываем файлы

- [nginx_conf.tar] — исходные конфиги Nginx и HTML. У присланного файла расширение `.tar`.
- [nginx-angie-migration-kit.zip] — `compose.yaml`, адаптированные конфиги обоих веб-серверов, тестовый бэкенд и скрипт проверки.

распаковка

```bash
mkdir -p "$HOME/nginx-angie-migration" &&
tar --keep-old-files -xf nginx_conf.tar -C "$HOME/nginx-angie-migration" &&
unzip -n nginx-angie-migration-kit.zip -d "$HOME/nginx-angie-migration"
```

```bash
cd ~/nginx-angie-migration &&
ls -l compose.yaml nginx/nginx.conf nginx/sites-available/default nginx/html/index.html lab/check.sh
```

Исходные файлы остаются в `nginx/`. Контейнерные версии конфигов лежат в `lab/`.

## 2. Проверим и при необходимости запустим Docker

Нужны Docker Engine, Compose v2 и `curl`. Первый запуск загружает образы и пакеты для сборки Nginx.

```bash
sudo docker version
sudo docker compose version
```

Если `docker version` показывает разделы `Client` и `Server`, переходим к шагу 3. 
Если клиент сообщает, что `/var/run/docker.sock` не найден, проверяем, работает ли systemd.

```bash
ps -p 1 -o comm=
```

### Ubuntu с systemd

Если команда выводит `systemd`, запускаем службу Docker стандартным способом.

```bash
sudo systemctl start docker &&
sudo docker version
```

При ошибке запуска смотрим журнал, командой `sudo journalctl -u docker -b -n 50 --no-pager`.

### Ubuntu без systemd, в том числе WSL 2 - мой вариант

Если Docker Engine установлен внутри Ubuntu, открываем два терминала этого дистрибутива. 
В первом запусти демон и оставь терминал открытым. 
В этом режиме лабораторная будет выполнена на стенде.

```bash
sudo dockerd
```

Проверяем `sudo docker version`. После появления раздела `Server` 
выполняем все оставшиеся команды во втором терминале. 
Если используем WSL, то посмотреть его версию, в PowerShell выполни `wsl -l -v` и посмотри колонку `VERSION` у Ubuntu.

## 3. Подготовим сайт и проверим Compose

Тестовый бэкенд отдаёт `index.html` из архива. Отдельный текстовый файл нужен для проверки выдачи статики, заголовка кеширования и Brotli.

```bash
cd ~/nginx-angie-migration &&
mkdir -p lab/site &&
cp nginx/html/index.html nginx/html/50x.html lab/site/ &&
awk 'BEGIN { for (i=0; i<100; i++) print "Archive migration: static file and Brotli." }' \
  > lab/site/migration-probe.txt
```

```bash
sudo docker compose -f ./compose.yaml --profile '*' config -q
```

При успешной проверке `config -q` ничего не печатает. 
Если получаем `no configuration file provided` или сообщение, что `compose.yaml` не найден, 
проверяем `pwd` и `ls -l compose.yaml`. 
Файл появляется после распаковки ZIP-комплекта на шаге 1.

## 4. Запускаем Nginx и сохраняем его ответы

Порты `18082` и `18083` участвуют в этой лабораторной. 
Если какой-то из них занят, смотрим, какой контейнер его использует. 
Например, для `18082` выполняем `sudo docker ps --filter publish=18082`.

```bash
sudo docker compose -f ./compose.yaml up -d --build nginx &&
sudo docker compose -f ./compose.yaml exec -T nginx nginx -t -c /opt/migration/nginx.conf &&
bash lab/check.sh before
```

В выполненной проверке ответил `Server: nginx/1.28.3`. 
Скрипт получил `200 OK` 
для главной страницы и файла `/migration-probe.txt`, 
проверил `Cache-Control` и `Content-Encoding: br`. 
Эталонные заголовки и тела ответов сохранились в `checks/before/`.

```text
before: HTTP 200, главная страница, статика, Cache-Control и Brotli проверены
```

## 5. Проверяем Angie на временном порту

Nginx продолжает обслуживать `18082`. 
Запустим Angie на `18083` и сравним ответы.

```bash
sudo docker compose -f ./compose.yaml up -d angie-check &&
sudo docker compose -f ./compose.yaml exec -T angie-check angie -t -c /opt/migration/angie.conf &&
bash lab/check.sh preview
```

```text
Server: Angie/1.12.5
Content-Encoding: br
Тела ответов Nginx и Angie совпадают байт в байт
preview: HTTP 200, главная страница, статика, Cache-Control и Brotli проверены
```

`cmp` сравнивает сохранённые  ответы. Код `0` и отсутствие вывода от самой команды означают побайтовое совпадение. HTTP-статус, заголовок сервера, кеширование и Brotli скрипт проверяет отдельно.

## 6. Переключаем исходный порт на Angie

После успешной проверки `preview` останови Nginx и запусти рабочий Angie на том же порту.

```bash
sudo docker compose -f ./compose.yaml --profile source stop nginx &&
sudo docker compose -f ./compose.yaml up -d angie-live &&
bash lab/check.sh after
```

Фактический результат после переключения.

```text
Server: Angie/1.12.5
Server: Angie/1.12.5
Cache-Control: max-age=31536000, public, no-transform, immutable
Content-Encoding: br
Тела ответов Nginx и Angie совпадают байт в байт
after: HTTP 200, главная страница, статика, Cache-Control и Brotli проверены
```

После успешной проверки остановим временный Angie на `18083`.

```bash
sudo docker compose -f ./compose.yaml --profile preview stop angie-check
```

## 7. Проверим рабочий сайт в браузере

1. Откроем [http://127.0.0.1:18082/](http://127.0.0.1:18082/).
2. Нажимаем **F12**, на вкладке **Network / Сеть** и обновляем страницу.
3. Выбераем основной запрос `GET /` и откроем **Headers / Заголовки**. 
Надпись «Welcome to nginx!» на самой странице берётся из исходного HTML. 
Сервер определяется по заголовку ответа.

| Что проверили | Фактический результат |
| --- | --- |
| Статус запроса | `200 OK` |
| `Server` | `Angie/1.12.5` |
| `Content-Type` | `text/html` |
| `Content-Encoding` | `br` |
| `Vary` | `Accept-Encoding` |

## Откат и остановка стенда

Если проверка после переключения не прошла, остановим рабочий Angie и вернем Nginx на `18082`.
если надо.

```bash
sudo docker compose -f ./compose.yaml --profile live stop angie-live
sudo docker compose -f ./compose.yaml up -d nginx &&
curl -i --max-time 5 http://127.0.0.1:18082/
```

Для диагностики посмотрим статусы и последние строки журналов проекта.

```bash
sudo docker compose -f ./compose.yaml --profile '*' ps -a
sudo docker compose -f ./compose.yaml --profile '*' logs --tail=60
```

Чтобы завершить работу, остановим контейнеры этого проекта. 
Если Docker запускался вручную и больше не нужен, 
 **Ctrl+C** в терминале с `dockerd`.

```bash
sudo docker compose -f ./compose.yaml --profile '*' stop
```

## Что проверено при переносе

Главный маршрут из архива проксируется на четыре HTTP-слушателя с портами `9000–9003`. В Compose сохранены порты и веса, а адрес `127.0.0.1` заменён на имя сервиса `backend`. Все четыре тестовых слушателя отдают исходную HTML-страницу. Оба веб-сервера используют общий конфиг сайта `lab/site.conf`, а типы файлов и правила статики читают из исходного каталога `nginx/`.
