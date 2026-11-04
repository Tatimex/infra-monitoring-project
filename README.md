# infra-monitoring-project

Система мониторинга доступности API-сервиса (echo-сервер), анализа логов
и контейнеризированная среда развёртывания.

## Структура проекта

```
.
├── .github/workflows/ci.yml   # CI: проверка скриптов и smoke-тест Docker
├── nginx/default.conf         # конфиг reverse proxy
├── check_api.sh               # мониторинг доступности API
├── analyze_logs.sh            # генерация и анализ access.log
├── docker-compose.yml         # стек: api (http-echo) + proxy (nginx)
├── traffic/                   # дамп трафика Wireshark
└── README.md
```

## Требования

- Linux, bash 4+, curl, grep, awk, sed
- Docker Engine + Docker Compose v2

## Быстрый старт

```bash
git clone git@github.com:Tatimex/infra-monitoring-project.git
cd infra-monitoring-project
chmod +x *.sh
docker compose up -d
./check_api.sh http://localhost:80
```

## Скрипты

### check_api.sh — проверка доступности API

```bash
./check_api.sh https://httpbin.org/status/200   # API доступен, exit 0
./check_api.sh https://httpbin.org/status/500   # API недоступен, код ответа: 500, exit 1
```

- принимает URL первым аргументом, проверяет его формат регулярным выражением;
- код возврата: `0` — HTTP 200, `1` — любой другой код или ошибка;
- `000` в выводе — сервер не ответил (DNS, сеть, таймаут).

### analyze_logs.sh — анализ логов

```bash
./analyze_logs.sh                  # access.log, 300 строк
./analyze_logs.sh my.log 1000      # свой файл и число строк
```

Генерирует тестовый access.log и выводит: общее число запросов, топ-3 IP,
количество ответов 4xx и 5xx, распределение по HTTP-методам.

## Docker Compose

```bash
docker compose up -d       # запуск
docker compose ps          # статус контейнеров
curl http://localhost:80   # -> Monitoring Service Active
docker compose logs -f     # логи
docker compose down        # остановка
```

- `api` — hashicorp/http-echo на порту 8080, доступен только во внутренней сети `monitoring-net`;
- `proxy` — nginx:alpine, опубликован на порту 80 хоста, проксирует запросы на `api:8080`.

## CI/CD

GitHub Actions (`.github/workflows/ci.yml`) на каждый Pull Request в `main`:
1. `bash -n` — проверка синтаксиса скриптов;
2. `check_api.sh https://httpbin.org/status/200` — ожидается код возврата 0;
3. негативный тест (404 → код 1), запуск `analyze_logs.sh`;
4. валидация и smoke-тест docker compose стека.

## Деплой на удалённый сервер (SSH / SCP)

В примерах сервер — `203.0.113.10`, пользователь — `deploy`.

### 1. Генерация SSH-ключа

```bash
ssh-keygen -t ed25519 -C "deploy@infra-monitoring" -f ~/.ssh/deploy_key
```

- `-t ed25519` — современный, быстрый и стойкий алгоритм;
- `-f` — путь к ключу: приватный `deploy_key` остаётся у вас,
  публичный `deploy_key.pub` кладётся на сервер;
- рекомендуется задать passphrase.

### 2. Копирование публичного ключа на сервер

```bash
ssh-copy-id -i ~/.ssh/deploy_key.pub deploy@203.0.113.10
```

Команда дописывает ключ в `~/.ssh/authorized_keys` на сервере
(последний раз потребуется пароль). Проверка входа по ключу:

```bash
ssh -i ~/.ssh/deploy_key deploy@203.0.113.10
```

Для удобства — `~/.ssh/config`:

```
Host monitoring
    HostName 203.0.113.10
    User deploy
    IdentityFile ~/.ssh/deploy_key
```

После этого достаточно `ssh monitoring`, `scp file monitoring:/path`.

### 3. Передача проекта

**Вариант А — архив + scp:**

```bash
git archive --format=tar.gz -o /tmp/infra-monitoring-project.tar.gz HEAD
scp -i ~/.ssh/deploy_key /tmp/infra-monitoring-project.tar.gz deploy@203.0.113.10:/tmp/
ssh -i ~/.ssh/deploy_key deploy@203.0.113.10 \
  "mkdir -p ~/infra-monitoring-project && tar -xzf /tmp/infra-monitoring-project.tar.gz -C ~/infra-monitoring-project"
```

`git archive` упаковывает только файлы под контролем git — без `.git`, логов и временных файлов.

**Вариант Б — tar + ssh потоком (без промежуточного файла):**

```bash
tar -czf - --exclude=.git --exclude='*.log' . | \
  ssh -i ~/.ssh/deploy_key deploy@203.0.113.10 \
  "mkdir -p ~/infra-monitoring-project && tar -xzf - -C ~/infra-monitoring-project"
```

`tar -czf -` пишет архив в stdout, ssh передаёт поток на сервер,
`tar -xzf -` на сервере распаковывает его из stdin.

### 4. Запуск на сервере

```bash
ssh -i ~/.ssh/deploy_key deploy@203.0.113.10 \
  "cd ~/infra-monitoring-project && chmod +x *.sh && docker compose pull && docker compose up -d && docker compose ps"
./check_api.sh http://203.0.113.10
```

### Рекомендации по безопасности

- в `/etc/ssh/sshd_config` на сервере: `PasswordAuthentication no`, `PermitRootLogin no`;
- права на ключ: `chmod 600 ~/.ssh/deploy_key`;
- отдельный ключ под деплой, не основной личный.