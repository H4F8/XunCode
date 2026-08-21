#!/usr/bin/env bash
# Генерирует markdown-описание релиза из истории коммитов.
# Использование: release_notes.sh <тег>          (по умолчанию GITHUB_REF_NAME)
# Вывод: stdout. Секции формируются из Conventional Commits:
#   feat -> «Новое», fix -> «Исправления», perf -> «Производительность»,
#   остальное (refactor/ci/chore/docs/build/test и без префикса) -> «Другое».
set -euo pipefail

TAG="${1:-${GITHUB_REF_NAME:?}}"
REPO="${GITHUB_REPOSITORY:-H4F8/XunCode}"

# Предыдущий тег — ближайший предок текущего по истории коммитов
PREV=$(git describe --tags --abbrev=0 "${TAG}^" 2>/dev/null || true)
RANGE="$TAG"
[ -n "$PREV" ] && RANGE="$PREV..$TAG"

capitalize() {
  printf '%s%s' "$(printf '%s' "${1:0:1}" | tr 'a-z' 'A-Z')" "${1:1}"
}

emit_section() {
  local title="$1" body="$2"
  [ -z "$body" ] && return 0
  printf '## %s\n\n%s\n' "$title" "$body"
}

feat_body="" fix_body="" perf_body="" other_body=""

# Регулярка в переменной: bash 5.2 не парсит \( в инлайн-паттерне [[ =~ ]]
conventional_re='^([a-zA-Z]+)(\([^)]*\))?(!)?:[[:space:]]*(.+)$'

while IFS= read -r subj; do
  [ -z "$subj" ] && continue
  case "$subj" in Merge\ *|Revert\ \"*) continue ;; esac
  if [[ "$subj" =~ $conventional_re ]]; then
    type="${BASH_REMATCH[1]}"
    breaking=""
    [ -n "${BASH_REMATCH[3]}" ] && breaking="**Критично:** "
    clean=$(capitalize "${BASH_REMATCH[4]}")
    entry="- ${breaking}${clean}"$'\n'
    case "$type" in
      feat) feat_body+="$entry" ;;
      fix)  fix_body+="$entry" ;;
      perf) perf_body+="$entry" ;;
      *)    other_body+="$entry" ;;
    esac
  else
    other_body+="- $(capitalize "$subj")"$'\n'
  fi
done < <(git log --pretty=format:%s "$RANGE")

{
  echo "# XunCode ${TAG#v}"
  echo ""
  emit_section "Новое" "$feat_body"
  emit_section "Исправления" "$fix_body"
  emit_section "Производительность" "$perf_body"
  emit_section "Другое" "$other_body"
  if [ -n "$PREV" ]; then
    echo "**Полный список изменений:** https://github.com/${REPO}/compare/${PREV}...${TAG}"
  fi
}
