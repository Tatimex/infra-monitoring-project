#!/usr/bin/env bash
#
# check_api.sh — проверка доступности API.
# Использование: ./check_api.sh <URL>
# Код возврата: 0 — API доступен (HTTP 200), 1 — недоступен или ошибка.

set -u

# 1. Проверка аргументов
if [ "$#" -ne 1 ]; then
  echo "Использование: $0 <URL>" >&2
  echo "Пример: $0 https://httpbin.org/status/200" >&2
  exit 1
fi

URL="$1"

# 2. Валидация формата URL регулярным выражением
if ! [[ "$URL" =~ ^https?://[^[:space:]]+$ ]]; then
  echo "Ошибка: некорректный URL '$URL' (должен начинаться с http:// или https://)" >&2
  exit 1
fi

# 3. HTTP-запрос: тело выбрасываем, забираем только код ответа
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
                 --max-time 10 --retry 3 --retry-delay 2 "$URL")

# 4. Проверка кода и вывод статуса
if [ "$HTTP_CODE" = "200" ]; then
  echo "API доступен"
  exit 0
else
  echo "API недоступен, код ответа: $HTTP_CODE"
  exit 1
fi