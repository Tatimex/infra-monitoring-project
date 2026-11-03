#!/usr/bin/env bash
#
# analyze_logs.sh — генерирует тестовый access.log и анализирует его.
# Использование: ./analyze_logs.sh [файл_лога] [кол-во_строк]
# По умолчанию: access.log, 300 строк.

set -euo pipefail

LOG_FILE="${1:-access.log}"
LINES="${2:-300}"

# Проверка аргумента: целое число не меньше 300
if ! [[ "$LINES" =~ ^[0-9]+$ ]] || [ "$LINES" -lt 300 ]; then
  echo "Ошибка: количество строк должно быть целым числом >= 300" >&2
  exit 1
fi

# Регулярное выражение для IPv4: каждый октет 0-255
OCTET='(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
IP_REGEX="^(${OCTET}\.){3}${OCTET}"

generate_log() {
  # IP повторяются разное число раз, чтобы топ был неравномерным
  local ips=(192.168.1.10 192.168.1.10 192.168.1.10 192.168.1.10
             10.0.0.5 10.0.0.5 10.0.0.5
             172.16.0.3 172.16.0.3
             192.168.1.25 203.0.113.42 198.51.100.7)
  local methods=(GET GET GET POST POST PUT DELETE)
  local paths=(/api/users /api/login /api/orders /api/products /health)
  local codes=(200 200 200 200 200 201 204 301 400 401 403 404 500 502 503)

  local i t ip method path code
  for (( i = 0; i < LINES; i++ )); do
    ip=${ips[RANDOM % ${#ips[@]}]}
    method=${methods[RANDOM % ${#methods[@]}]}
    path=${paths[RANDOM % ${#paths[@]}]}
    code=${codes[RANDOM % ${#codes[@]}]}
    t=$(( 10*3600 + 15*60 + i ))        # время: с 10:15:00, +1 сек на запрос
    printf '%s - - [15/Aug/2026:%02d:%02d:%02d] "%s %s HTTP/1.1" %s\n' \
           "$ip" $(( t/3600 )) $(( t%3600/60 )) $(( t%60 )) \
           "$method" "$path" "$code"
  done > "$LOG_FILE"
}

analyze_log() {
  echo "========== Анализ файла: $LOG_FILE =========="

  # 1. Общее количество запросов (строки, начинающиеся с валидного IP)
  local total
  total=$(grep -cE "$IP_REGEX" "$LOG_FILE" || true)
  echo "Общее количество запросов: $total"
  echo

  # 2. Топ-3 IP по числу запросов
  echo "Топ-3 IP-адреса по числу запросов:"
  grep -oE "$IP_REGEX" "$LOG_FILE" \
    | sort | uniq -c | sort -rn | head -n 3 \
    | awk '{ printf "  %d. %-15s — %d запросов\n", NR, $2, $1 }'
  echo

  # 3. Ошибки 4xx и 5xx (код ответа — последнее поле строки, $NF)
  local c4 c5
  c4=$(awk '$NF ~ /^4[0-9][0-9]$/ { n++ } END { print n+0 }' "$LOG_FILE")
  c5=$(awk '$NF ~ /^5[0-9][0-9]$/ { n++ } END { print n+0 }' "$LOG_FILE")
  echo "Запросов с кодами 4xx: $c4"
  echo "Запросов с кодами 5xx: $c5"
  echo

  # 4. Дополнительно: распределение по HTTP-методам (через sed)
  echo "Распределение по HTTP-методам:"
  sed -E 's/^[^"]*"([A-Z]+) .*/\1/' "$LOG_FILE" \
    | sort | uniq -c | sort -rn \
    | awk '{ printf "  %-7s %d\n", $2, $1 }'
}

generate_log
echo "Сгенерирован файл $LOG_FILE ($LINES строк). Пример строк:"
head -n 2 "$LOG_FILE"
echo
analyze_log