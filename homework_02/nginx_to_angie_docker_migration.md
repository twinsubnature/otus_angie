# Миграция Docker-контейнера с Nginx на Angie

Оба контейнера обслуживают одну и ту же страницу `Migration test page`. 
Сначала Nginx работает на `http://127.0.0.1:18082/`. 
Angie проверяется отдельно на порту `18083`, 
затем занимает исходный порт `18082`. 
Контейнер Nginx сохраняется для отката.

| Назначение | Имя контейнера | Порт Ubuntu | Порт внутри контейнера |
| --- | --- | --- | --- |
| Исходный Nginx | `nginx-migration-src` | `18082` | `80` |
| Проверка Angie | `angie-migration-check` | `18083` | `80` |
| Angie после переключения | `angie-migration-live` | `18082` | `80` |

## 0. Запуск Docker Engine

В терминале Ubuntu проверяю процесс PID 1 и подключение к Docker Engine.

```bash
ps -p 1 -o comm=
sudo docker version
```

Если в выводе Docker есть разделы `Client` и `Server`, переходим к шагу 1. 
Если клиент сообщает об ошибке подключения, запускаем Docker способом, который подходит твоей среде.

### Стандартный запуск в Ubuntu с systemd

Если PID 1 — `systemd`, запусти службу Docker и проверяем подключение. 
Этот способ подходит для обычной установки Ubuntu на компьютере или в виртуальной машине. 
[Запуск Docker через systemd](https://docs.docker.com/engine/daemon/start/#start-with-systemd)

```bash
sudo systemctl start docker &&
sudo docker version
```

Если нужен автозапуск Docker при загрузке Ubuntu, проверяем, включён ли он. 
При статусе `disabled` выполняем `sudo systemctl enable --now docker`. 
[Автозапуск Docker](https://docs.docker.com/engine/install/linux-postinstall/#configure-docker-to-start-on-boot-with-systemd)

```bash
systemctl is-enabled docker
```

Если служба не запустилась, проверяем её состояние и журнал текущей загрузки.

```bash
sudo systemctl status docker --no-pager
sudo journalctl -u docker -b -n 50 --no-pager
```

### Ручной запуск без systemd

На стенде команда Docker уже была установлена, но при первом запуске контейнера возвращает ошибку:
например:
```text
failed to connect to the docker API at unix:///var/run/docker.sock
dial unix /var/run/docker.sock: connect: no such file or directory
```

Это означает, что клиент не нашёл сокет локального демона. 
Если **Docker Engine установлен внутри Ubuntu**, 
PID 1 не является `systemd` и демон ещё не запущен, открываем два терминала Ubuntu. 
В **первом терминале** запускаем демон и оставляем терминал открытым. 
[Ручной запуск Docker Engine](https://docs.docker.com/engine/daemon/start/#start-the-daemon-manually)

```bash
sudo dockerd
```

Во **втором терминале** терминале снова выполняем проверку. 
После появления раздела `Server` продолжаем в этом терминале. 
Если `dockerd` завершился с ошибкой, 
причина будет в его выводе в первом терминале.

```bash
sudo docker version
```

## 1. Подготовливаем страницу и общий конфиг

```bash
mkdir -p ~/angie-docker-migration/html
cd ~/angie-docker-migration

printf '%s\n' 'Migration test page' > html/index.html

cat > default.conf <<'EOF'
server {
    listen 80;
    server_name localhost;

    root /usr/share/migration/html;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF
```

Директива `listen 80` задаёт порт внутри контейнера. 
Привязка к `127.0.0.1` задаётся на стороне Ubuntu через `docker run -p`. 
Если оставить `listen 127.0.0.1:8082` из пакетной установки первого задания,
запросы через опубликованный порт Docker до этого конфигурационного блока не дойдут. 
[Публикация портов в Docker](https://docs.docker.com/engine/network/port-publishing/)

## 2. Запустить Nginx и сохранить исходный ответ

```bash
sudo docker run -d --name nginx-migration-src \
  -p 127.0.0.1:18082:80 \
  --mount "type=bind,src=$PWD/default.conf,dst=/etc/nginx/conf.d/default.conf,readonly" \
  --mount "type=bind,src=$PWD/html,dst=/usr/share/migration/html,readonly" \
  nginx:stable

sudo docker exec nginx-migration-src nginx -t &&
curl -fsS --max-time 5 -D - -o nginx-before.body http://127.0.0.1:18082/ &&
cat nginx-before.body
```

Ожидаются статус `200 OK`, 
заголовок `Server: nginx` 
и текст `Migration test page`. 
Файл `nginx-before.body` нужен для сравнения.

Если повторный `docker run` выдаёт `Conflict` для имени `nginx-migration-src`, 
смотрим статус командой `sudo docker ps -a --filter name=nginx-migration-src`. 
При статусе `Up` выполняем только проверку, начиная с `docker exec`. 
Если исходный контейнер остановлен и порт `18082` свободен, 
запускаем командой `sudo docker start nginx-migration-src`, 
затем повторяем проверку.

## 3. Проверяем Angie на отдельном порту

Angie использует тот же блок `server`, 
но файл подключается по пути `/etc/angie/http.d/default.conf`. 
Образ берём из официального реестра Angie. 
[Образы Angie](https://angie.software/angie/docs/installation/docker/) · 
[Размещение конфигурации Angie](https://angie.software/angie/docs/configuration/first-steps/)

```bash
ANGIE_IMAGE=docker.angie.software/angie:1.12.5-ubuntu

sudo docker run -d --name angie-migration-check \
  -p 127.0.0.1:18083:80 \
  --mount "type=bind,src=$PWD/default.conf,dst=/etc/angie/http.d/default.conf,readonly" \
  --mount "type=bind,src=$PWD/html,dst=/usr/share/migration/html,readonly" \
  "$ANGIE_IMAGE"

sudo docker exec angie-migration-check angie -t &&
curl -fsS --max-time 5 -D - -o angie-check.body http://127.0.0.1:18083/ &&
cmp nginx-before.body angie-check.body &&
echo 'Страницы совпадают'
```

Переходим к переключению, когда Angie вернёт `200 OK` 
с заголовком `Server: Angie/...`. 
Если `cmp` завершится без вывода с кодом `0`, 
тела ответов совпали побайтно. 
```bash
cmp nginx-before.body angie-check.body
echo $?
```
При ошибке запуска смотрим `sudo docker logs angie-migration-check`. 
Nginx на этом этапе ещё обслуживает порт `18082`.

## 4. Переключаем исходный порт на Angie

Остаемся в том же каталоге. 
Docker задаёт публикацию порта при создании контейнера, 
поэтому для порта `18082` создаётся новый контейнер Angie. 
Между остановкой Nginx и запуском Angie будет перерыв в обслуживании.

```bash
ANGIE_IMAGE=docker.angie.software/angie:1.12.5-ubuntu

sudo docker stop nginx-migration-src &&
sudo docker run -d --name angie-migration-live \
  -p 127.0.0.1:18082:80 \
  --mount "type=bind,src=$PWD/default.conf,dst=/etc/angie/http.d/default.conf,readonly" \
  --mount "type=bind,src=$PWD/html,dst=/usr/share/migration/html,readonly" \
  "$ANGIE_IMAGE"
```

```bash
curl -fsS --max-time 5 -D - -o angie-after.body http://127.0.0.1:18082/ &&
cmp nginx-before.body angie-after.body &&
echo 'Страницы совпадают'
```

Критерий успеха — исходный URL отвечает `200 OK`, 
тело совпало, а заголовок `Server` показывает Angie.

## 5. Зафиксируем результат и остановим стенд

Проверка дала такой результат.

| Проверка | Адрес | Заголовок `Server` | Результат |
| --- | --- | --- | --- |
| Исходный Nginx | `127.0.0.1:18082` | `nginx/1.30.7` | `200 OK`, сохранён исходный ответ |
| Тестовый Angie | `127.0.0.1:18083` | `Angie/1.12.5` | `200 OK`, тела совпали |
| Angie после переключения | `127.0.0.1:18082` | `Angie/1.12.5` | `200 OK`, тела совпали |

После переключения остановливаем тестовый контейнер.  
Остановливаем рабочий Angie.

```bash
sudo docker stop angie-migration-check
sudo docker stop angie-migration-live
sudo docker ps
```

Если `docker ps` показывает только заголовки, 
запущенных контейнеров нет. 
Остановленные контейнеры по-прежнему видны через `sudo docker ps -a`. 
Остановка демона, запущенного вручную, 
остановливаем сочетанием **Ctrl+C** в первом терминале. 
[Ручная остановка Docker Engine](https://docs.docker.com/engine/daemon/start/#start-the-daemon-manually)

Для следующего запуска поднимаем Docker Engine, если он остановлен, 
затем выполняем:

```bash
sudo docker start angie-migration-live
```

## Откат к Nginx

Если Angie уже запущен на исходном порту, останавливаем его. 
Затем запускаем сохранённый контейнер Nginx с прежними параметрами.

```bash
sudo docker stop angie-migration-live
sudo docker start nginx-migration-src &&
curl -i --max-time 5 http://127.0.0.1:18082/
```

Если контейнер Angie не успел запуститься и порт `18082` свободен, 
достаточно выполнить `docker start` для Nginx и повторить запрос.

## Что проверить при переносе своего контейнера

Команда `sudo docker inspect ИМЯ_КОНТЕЙНЕРА` показывает порты, 
точки монтирования, сети, команду запуска и политику перезапуска. 
Переносим те параметры, от которых зависит приложение. 
Проверяем пути в `include`, `root` и настройках TLS внутри нового образа. 
Если в исходном конфиге есть Brotli или Zstd, 
проверяем наличие совместимых модулей Angie и их загрузку через `load_module` в главном конфиге. 
Для проксирования дополнительно сравниваем ответы маршрутов, 
которые обращаются к серверу приложения. 
[Образы и модули Angie](https://angie.software/angie/docs/installation/docker/)
