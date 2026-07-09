#!/usr/bin/env bash
# routing: helper  skill=wp-new  called-by=haiku
# see DP.SC.159, DP.ROLE.059
# create-wp.sh — атомарное создание РП: context file, archive stub, REGISTRY,
# WeekPlan (Linear — вручную, MCP-доступа у скрипта нет)
# see DP.M.010, DP.ROLE.037
#
# Использование:
#   bash create-wp.sh --title "Название" --budget 5h --priority P3 [--slug slug] [--repo "репо"] [--related "WP-150:dependency,WP-167:продукт"]
#   bash create-wp.sh --title "Название" --budget 5h --priority P3 --no-consent-check
#
# Предусловие: consent state file должен существовать:
#   touch /IWE/.claude/state/wp-consent-{N}
#
# Совместимость: bash 3.2+ (macOS), bash 4+ (Linux)

set -uo pipefail

IWE="${IWE_ROOT:-$HOME/IWE}"
GOV_REPO="${IWE_GOVERNANCE_REPO:-DS-strategy}"
STRATEGY="$IWE/$GOV_REPO"
REGISTRY="$STRATEGY/docs/WP-REGISTRY.md"
INBOX="$STRATEGY/inbox"
STATE_DIR="$IWE/.claude/state"

# --- Параметры ---
TITLE=""
BUDGET=""
PRIORITY="P3"
SLUG=""
REPO=""
RELATED=""
SKIP_CONSENT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)    TITLE="$2";    shift 2 ;;
    --budget)   BUDGET="$2";   shift 2 ;;
    --priority) PRIORITY="$2"; shift 2 ;;
    --slug)     SLUG="$2";     shift 2 ;;
    --repo)     REPO="$2";     shift 2 ;;
    --related)  RELATED="$2";  shift 2 ;;
    --no-consent-check) SKIP_CONSENT=1; shift ;;
    *) echo "Неизвестный флаг: $1" >&2; exit 1 ;;
  esac
done

# --- Валидация ---
if [[ -z "$TITLE" || -z "$BUDGET" ]]; then
  echo "Использование: $0 --title \"Название\" --budget 5h [--priority P3] [--slug slug] [--repo репо] [--related \"WP-NNN:тип\"]" >&2
  exit 1
fi

# --- Найти следующий номер WP ---
WP_NUM=$(python3 - "$REGISTRY" <<'PYEOF' 2>/dev/null
import sys, re
registry = sys.argv[1]
max_num = 0
try:
    with open(registry, "r", encoding="utf-8") as f:
        for line in f:
            # Первая колонка: | 297 | ~~297~~ | **WP-017** | WP-007 |
            # Префикс WP- и ведущие нули опциональны — реестры ведутся по-разному.
            m = re.match(r"^\|\s*(?:\*\*)?~*(?:WP-)?0*(\d+)~*(?:\*\*)?\s*\|", line)
            if m:
                n = int(m.group(1))
                if n > max_num:
                    max_num = n
except Exception as e:
    print(0, file=sys.stderr)
print(max_num + 1)
PYEOF
)

if [[ -z "$WP_NUM" || "$WP_NUM" -le 0 ]]; then
  echo "❌ Не удалось определить следующий номер WP из REGISTRY" >&2
  exit 1
fi

echo "📋 Следующий номер WP: $WP_NUM"

# --- Проверка consent ---
CONSENT_FILE="$STATE_DIR/wp-consent-${WP_NUM}"
if [[ "$SKIP_CONSENT" -eq 0 ]]; then
  if [[ ! -f "$CONSENT_FILE" ]]; then
    echo "🚫 WP Gate: нет согласия пользователя на создание WP-${WP_NUM}" >&2
    echo "   Создайте consent file и повторите:" >&2
    echo "   touch $CONSENT_FILE" >&2
    exit 1
  fi
  echo "✅ Consent: $CONSENT_FILE"
fi

# --- Дата ---
TODAY=$(date +%Y-%m-%d)

# --- Slug из title (если не задан) ---
if [[ -z "$SLUG" ]]; then
  SLUG=$(echo "$TITLE" | python3 -c "
import sys, re, unicodedata
s = sys.stdin.read().strip().lower()
# Транслитерация кириллицы
tr = {
  'а':'a','б':'b','в':'v','г':'g','д':'d','е':'e','ё':'yo','ж':'zh',
  'з':'z','и':'i','й':'j','к':'k','л':'l','м':'m','н':'n','о':'o',
  'п':'p','р':'r','с':'s','т':'t','у':'u','ф':'f','х':'kh','ц':'ts',
  'ч':'ch','ш':'sh','щ':'shch','ъ':'','ы':'y','ь':'','э':'e','ю':'yu','я':'ya'
}
result = ''
for c in s:
    result += tr.get(c, c)
result = re.sub(r'[^a-z0-9]+', '-', result)
result = result.strip('-')[:40]
print(result)
" 2>/dev/null || echo "wp-$(echo "$TITLE" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-' | cut -c1-30)")
fi

WP_FILE="$INBOX/WP-${WP_NUM}-${SLUG}.md"

echo "🚀 Создаю WP-${WP_NUM}: $TITLE"
echo "   Файл: inbox/WP-${WP_NUM}-${SLUG}.md"
echo "   Бюджет: $BUDGET | Приоритет: $PRIORITY"

# --- Сформировать строки таблицы связок ---
RELATED_ROWS="| — | — | — | нет связок |"
if [[ -n "$RELATED" ]]; then
  RELATED_ROWS=""
  IFS=',' read -ra REL_ITEMS <<< "$RELATED"
  for rel_item in "${REL_ITEMS[@]}"; do
    rel_item="${rel_item# }"
    rel_wp="${rel_item%%:*}"
    rel_type="${rel_item#*:}"
    [[ "$rel_wp" == "$rel_type" ]] && rel_type="—"
    RELATED_ROWS+="| ${rel_wp} | 🟡 | ${rel_type} | — |
"
  done
fi

# --- Шаг 1: context file ---
echo ""
echo "1/5 context file..."

cat > "$WP_FILE" <<WPEOF
---
wp: ${WP_NUM}
title: "${TITLE}"
status: pending
priority: ${PRIORITY}
budget: ${BUDGET}
created: ${TODAY}
last_session: ${TODAY}
related: []
---

# WP-${WP_NUM}: ${TITLE}

## Проблема

[Описать неудовлетворённость / проблему, которую решает этот РП]

## Артефакт

[Конкретный результат — существительное-артефакт с критериями]

## Связки с РП

| РП | Сила | Тип | Что передаётся |
|----|------|-----|----------------|
${RELATED_ROWS}

## Фазы реализации

### Ф1 — [Название фазы] (~?h)

- [ ] ...

## Что узнали

[Заполняется при сессиях]

## Осталось

**Что пробовали:** не начат
**Что узнали:** —
  → memory: не нужно
**Что дальше:**
- [ ] Открыть сессию, прочитать задачу, составить план
**Следующий шаг:** Открыть сессию — прочитать задачу, составить план
**Контекст для следующей сессии:** РП только создан, нет контекста
WPEOF

echo "   ✅ $WP_FILE"

# --- Шаг 2: archive/wp-contexts stub (§Закрытия) ---
echo "2/5 archive stub..."

ARCHIVE_DIR="$STRATEGY/archive/wp-contexts"
ARCHIVE_FILE="$ARCHIVE_DIR/WP-${WP_NUM}-${SLUG}.md"

if [[ -f "$ARCHIVE_FILE" ]]; then
  echo "   ⚠️  $ARCHIVE_FILE уже существует — не перезаписываю" >&2
else
  mkdir -p "$ARCHIVE_DIR"
  cat > "$ARCHIVE_FILE" <<EOF
---
type: wp-closure
wp: ${WP_NUM}
title: ${TITLE}
status: pending
created: ${TODAY}
---

# WP-${WP_NUM} — Закрытие

> Заготовка. Заполняется при закрытии РП.

## Что сделано

## Что узнали

## Метрики

| Показатель | План | Факт |
|------------|------|------|
| Бюджет | ${BUDGET} | — |
EOF
  echo "   ✅ $ARCHIVE_FILE"
fi

# --- Шаг 3: WP-REGISTRY.md ---
echo "3/5 WP-REGISTRY.md..."

WEEKPLAN=$(find "$STRATEGY/current" -maxdepth 1 -name "WeekPlan W*.md" 2>/dev/null | sort -r | head -1)
WEEK=$(basename "${WEEKPLAN:-}" 2>/dev/null | sed -n 's/.*\(W[0-9]\{1,2\}\).*/\1/p')

REPO_CELL="${REPO:-$GOV_REPO/inbox/WP-${WP_NUM}-*.md}"
INSERT="$(dirname "$0")/md_table_insert.py"

python3 "$INSERT" "$REGISTRY" registry \
  "$WP_NUM" "$PRIORITY" "$TITLE" "$REPO_CELL" "$BUDGET" "${WEEK:---}"

# --- Шаг 4: WeekPlan ---
echo "4/5 WeekPlan..."

if [[ -n "$WEEKPLAN" ]]; then
  python3 "$INSERT" "$WEEKPLAN" weekplan \
    "$WP_NUM" "$PRIORITY" "$TITLE" "${REPO:-$GOV_REPO}" "$BUDGET" "${WEEK:---}"
else
  echo "   ⚠️  WeekPlan не найден в current/ — добавить вручную" >&2
fi

# --- Шаг 5: Linear ---
echo "5/5 Linear: создать issue вручную или через MCP (create-wp.sh не имеет MCP доступа)"
echo "   ℹ️  Запустить после скрипта: Linear MCP → create_issue title='WP-${WP_NUM} ${TITLE}' teamId=TSR"

# --- Удалить consent file ---
if [[ "$SKIP_CONSENT" -eq 0 && -f "$CONSENT_FILE" ]]; then
  rm -f "$CONSENT_FILE"
  echo ""
  echo "🗑  Consent file удалён: $CONSENT_FILE"
fi

echo ""
echo "✅ WP-${WP_NUM} создан: $TITLE"
echo "   context: inbox/WP-${WP_NUM}-${SLUG}.md"
echo "   Следующий шаг: заполнить «Проблема», «Артефакт», «Фазы» в context file"
echo "   Не забыть: Linear issue + (если ≥3h) Strategy.md маппинг"
