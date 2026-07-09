#!/usr/bin/env python3
# routing: helper  called-by=create-wp.sh
# see DP.SC.159, DP.ROLE.059
"""Вставка строки РП в markdown-таблицу по ИМЕНАМ колонок, а не по их порядку.

Зачем: create-wp.sh раньше собирал строку из фиксированных 6 ячеек в жёстком
порядке. Любой реестр с другой схемой (4 колонки в seed шаблона, 5 или 7 у
пользователя) получал съехавшую таблицу или отказ «не найден заголовок».
Здесь колонки сопоставляются по заголовку, неизвестные заполняются прочерком.

Usage:
    md_table_insert.py <file> <kind> <num> <priority> <title> <repo> <budget> <week>

    kind: registry | weekplan

Exit: 0 — вставлено, 1 — таблица не найдена, 2 — ошибка чтения.
"""
import re
import sys

# Заголовок → семантический ключ. Нормализация: lower, без '*' и пробелов по краям.
HEADER_KEYS = {
    "#": "num", "№": "num", "wp": "num",
    "приоритет": "priority",
    "название": "title", "рп": "title", "работа": "title", "продукт": "title",
    "статус": "status",
    "репо": "repo", "репозиторий": "repo",
    "бюджет": "budget",
    "неделя": "week",
    "🚦": "flag", "флаг": "flag",
    "режим твс": "tvs", "твс": "tvs",
    "источник": "source",
    "дедлайн": "deadline",
    "активация": "activation",
}

FLAG_BY_PRIORITY = {"P1": "🔴", "P2": "🟡", "P3": "🟢", "P4": "⚪", "P5": "⚪"}


def norm(header):
    return header.replace("*", "").strip().lower()


def split_row(line):
    """'| a | b |' → ['a', 'b']"""
    return [c.strip() for c in line.strip().strip("|").split("|")]


def find_table(lines):
    """Первая таблица, у которой в шапке есть и номер, и название.

    Отсекает служебные таблицы вроде «| Статус | Расшифровка |» —
    у них нет колонки-названия.
    """
    for i, line in enumerate(lines):
        # Разделитель: |---|---| , |--|--| , |:-:|-:| — только | - : и пробелы
        if i == 0 or not re.match(r"^\|[\s:|-]+\|\s*$", line.strip()):
            continue
        headers = [norm(h) for h in split_row(lines[i - 1])]
        keys = {HEADER_KEYS.get(h) for h in headers}
        if "num" in keys and "title" in keys:
            return i - 1, i  # (индекс шапки, индекс разделителя)
    return None, None


def number_cell(lines, sep_idx, num, col):
    """Формат номера подсматриваем у соседей по той же колонке: 18 / WP-18 / WP-018.

    Колонка номера не всегда первая — в WeekPlan перед ней стоит светофор.
    """
    for line in lines[sep_idx + 1:]:
        if not line.strip().startswith("|"):
            break
        cells = split_row(line)
        if col >= len(cells):
            continue
        cell = cells[col].replace("*", "").replace("~", "").strip()
        m = re.match(r"^WP-(0*\d+)$", cell)
        if m:
            return "WP-{}".format(str(num).zfill(len(m.group(1))))
        if re.match(r"^\d+$", cell):
            return str(num)
    return str(num)


def main():
    if len(sys.argv) != 9:
        print(__doc__, file=sys.stderr)
        return 2

    path, kind, num, priority, title, repo, budget, week = sys.argv[1:9]

    try:
        with open(path, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except OSError as exc:
        print("   ❌ {}: {}".format(path, exc), file=sys.stderr)
        return 2

    hdr_idx, sep_idx = find_table(lines)
    if sep_idx is None:
        print("   ⚠️  Таблица с колонками «номер» и «название» не найдена — добавить вручную",
              file=sys.stderr)
        return 1

    headers = split_row(lines[hdr_idx])
    keys = [HEADER_KEYS.get(norm(h)) for h in headers]

    values = {
        "num": number_cell(lines, sep_idx, num, keys.index("num")),
        "priority": priority,
        "title": "**{}**".format(title),
        "status": "⏳" if kind == "registry" else "pending",
        "repo": repo or "—",
        "budget": budget,
        "week": week or "—",
        "flag": FLAG_BY_PRIORITY.get(priority, "⚪"),
        "tvs": "текущее",
        "source": "off-plan",
        "deadline": "—",
        "activation": "—",
    }

    cells = [values.get(k, "—") for k in keys]
    lines.insert(sep_idx + 1, "| " + " | ".join(cells) + " |\n")

    with open(path, "w", encoding="utf-8") as f:
        f.writelines(lines)

    print("   ✅ строка WP-{} добавлена ({} колонок)".format(num, len(headers)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
