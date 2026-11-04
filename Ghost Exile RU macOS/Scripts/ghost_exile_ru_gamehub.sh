#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ghost_exile_settings.sh"

APP_ID="1807080"
APP_NAME="Ghost Exile"
TARGET_LANG_HEX="7275737369616e"
GAME_LANG_REG_KEY='GameOptions.General.Language_h2372230879'
GAME_LANG_REG_SECTION='Software\\LostOneTeam\\GhostExile'
GAMEHUB_APP="/Applications/GameHub.app"
GAMEHUB_ROOT="$HOME/Library/Application Support/com.gamemac.www"
CONTAINERS_ROOT="$GAMEHUB_ROOT/wine-engine/containers/virtual_containers"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

CONTAINER_PATH=""
DRY_RUN=0
CHECK_ONLY=0
KILL_STEAM=0
START_GAMEHUB=0

say() { printf '%s\n' "$*"; }
fail() { printf 'Ошибка: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Использование:
  $(basename "$0") [--check | --dry-run] [--kill-steam] [--start-gamehub] [--container PATH]

Включает русский язык Ghost Exile в Steam-контейнере GameHub.

Опции:
  --check         Показать сборку Steam и языки игры без изменений
  --dry-run         Показать изменения без записи
  --kill-steam      Закрыть Steam перед изменениями
  --start-gamehub   Открыть GameHub после изменений
  --container PATH  Указать virtual container вручную
  --help            Показать эту справку
EOF
}

steam_is_running() {
  pgrep -fal '[s]team\.exe' >/dev/null 2>&1
}

backup_file() {
  local file="$1"
  local backup="${file}.bak.${TIMESTAMP}"
  if [ "$DRY_RUN" -eq 1 ]; then
    say "[dry-run] backup: $file -> $backup"
  else
    cp "$file" "$backup"
  fi
}

find_container() {
  local manifest
  local found=""
  local count=0

  while IFS= read -r manifest; do
    found="${manifest%/drive_c/Program Files (x86)/Steam/steamapps/appmanifest_${APP_ID}.acf}"
    count=$((count + 1))
  done < <(find "$CONTAINERS_ROOT" -type f -name "appmanifest_${APP_ID}.acf" 2>/dev/null | sort)

  [ "$count" -gt 0 ] || fail "контейнер Ghost Exile не найден в GameHub"
  [ "$count" -eq 1 ] || fail "найдено несколько контейнеров Ghost Exile; укажи нужный через --container PATH"
  CONTAINER_PATH="$found"
}

stop_steam() {
  say "Закрываю Steam в GameHub..."
  if [ "$DRY_RUN" -eq 1 ]; then
    say "[dry-run] Steam и его вспомогательные процессы были бы закрыты"
    return
  fi
  pkill -f 'steam\.exe|steamwebhelper\.exe' >/dev/null 2>&1 || true
  sleep 2
}

patch_manifest() {
  local file="$1"
  local count
  count="$(perl -0ne 'my $n = () = /"language"\s*"english"/g; print $n' "$file")"
  if [ "$count" -eq 0 ]; then
    say "appmanifest: english не найден — изменение не требуется"
    return
  fi
  backup_file "$file"
  if [ "$DRY_RUN" -eq 1 ]; then
    say "[dry-run] appmanifest: english -> russian ($count вх.)"
  else
    perl -0pi -e 's/("language"\s*")english(")/${1}russian${2}/g' "$file"
    say "appmanifest: язык переключён на russian"
  fi
}

patch_localconfig() {
  local file="$1"
  grep -q "\"$APP_ID\"" "$file" || return

  if ! grep -Eq "\"$APP_ID\"[[:space:]]+\"[^\"]*656e676c697368" "$file"; then
    if grep -Eq "\"$APP_ID\"[[:space:]]+\"[^\"]*${TARGET_LANG_HEX}" "$file"; then
      say "localconfig: уже содержит russian -> $file"
    fi
    return
  fi

  backup_file "$file"
  if [ "$DRY_RUN" -eq 1 ]; then
    say "[dry-run] localconfig: english(hex) -> russian(hex) в $file"
  else
    perl -0pi -e 's/("1807080"\s+"[^"]*?)656e676c697368([^"]*")/${1}7275737369616e${2}/g' "$file"
    say "localconfig: язык переключён на russian -> $file"
  fi
}

patch_user_reg() {
  local file="$1"
  local current
  current="$(perl -ne 'print lc($1) if /"GameOptions\.General\.Language_h2372230879"=dword:([0-9a-fA-F]{8})/' "$file")"

  if [ "$current" = "00000001" ]; then
    say "user.reg: внутренний язык уже выставлен в Russian"
    return
  fi

  backup_file "$file"
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ -n "$current" ]; then
      say "[dry-run] user.reg: dword:$current -> dword:00000001"
    else
      say "[dry-run] user.reg: будет добавлен ключ русского языка"
    fi
    return
  fi

  if [ -n "$current" ]; then
    perl -0pi -e 's/("GameOptions\.General\.Language_h2372230879"=dword:)[0-9a-fA-F]{8}/${1}00000001/g' "$file"
  elif grep -Fq "[$GAME_LANG_REG_SECTION]" "$file"; then
    REG_SECTION="$GAME_LANG_REG_SECTION" REG_KEY="$GAME_LANG_REG_KEY" perl -0pi -e '
      my $section = quotemeta($ENV{REG_SECTION});
      s/(\[$section\][^\[]*)/$1"$ENV{REG_KEY}"=dword:00000001\n/s;
    ' "$file"
  else
    printf '\n[%s] %s\n#time=0\n"%s"=dword:00000001\n' \
      "$GAME_LANG_REG_SECTION" "$(date +%s)" "$GAME_LANG_REG_KEY" >> "$file"
  fi
  say "user.reg: внутренний язык переключён на Russian"
}

ensure_alias_dir() {
  local label="$1" source="$2" target="$3"
  [ -d "$source" ] || { say "$label: исходная папка не найдена, пропускаю"; return; }
  [ ! -d "$target" ] || { say "$label: уже существует"; return; }
  if [ "$DRY_RUN" -eq 1 ]; then
    say "[dry-run] $label: copy $source -> $target"
  else
    mkdir -p "$target"
    cp -R "$source"/. "$target"/
    say "$label: создан"
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK_ONLY=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --kill-steam) KILL_STEAM=1 ;;
    --start-gamehub) START_GAMEHUB=1 ;;
    --container)
      shift
      [ $# -gt 0 ] || fail "для --container нужен путь"
      CONTAINER_PATH="$1"
      ;;
    --help|-h) usage; exit 0 ;;
    *) fail "неизвестная опция: $1" ;;
  esac
  shift
done

if [ -z "$CONTAINER_PATH" ]; then
  [ -d "$GAMEHUB_ROOT" ] || fail "GameHub не установлен или ещё не запускался"
  find_container
fi
[ -d "$CONTAINER_PATH" ] || fail "контейнер не найден: $CONTAINER_PATH"

locate_game "$CONTAINER_PATH"
USER_REG="$CONTAINER_PATH/user.reg"
GAME_ROOT="$STEAM_ROOT/steamapps/common/GhostExile"
ASSETS="$GAME_ROOT/GhostExile_Data/StreamingAssets"

[ -f "$MANIFEST" ] || fail "манифест Ghost Exile не найден: $MANIFEST"
if [ "$CHECK_ONLY" -eq 1 ]; then
  report_game_settings "$CONTAINER_PATH"
  exit 0
fi
[ -f "$USER_REG" ] || fail "реестр контейнера не найден: $USER_REG"
[ -d "$GAME_ROOT" ] || fail "папка Ghost Exile не найдена: $GAME_ROOT"

say "GameHub container: $CONTAINER_PATH"
say "Игра: $APP_NAME ($APP_ID)"
say "Целевой язык: russian"

if steam_is_running; then
  if [ "$KILL_STEAM" -eq 1 ]; then
    stop_steam
    if [ "$DRY_RUN" -eq 0 ] && steam_is_running; then
      fail "Steam всё ещё запущен. Закрой его вручную и повтори."
    fi
  elif [ "$DRY_RUN" -eq 1 ]; then
    say "[dry-run] Steam запущен; для применения понадобится --kill-steam"
  else
    fail "Steam запущен. Закрой его или используй --kill-steam."
  fi
fi

patch_manifest "$MANIFEST"

LOCALCONFIG_COUNT=0
while IFS= read -r localconfig; do
  LOCALCONFIG_COUNT=$((LOCALCONFIG_COUNT + 1))
  patch_localconfig "$localconfig"
done < <(find "$STEAM_ROOT/userdata" -type f -path '*/config/localconfig.vdf' 2>/dev/null | sort)
[ "$LOCALCONFIG_COUNT" -gt 0 ] || say "localconfig: файлы пользователей Steam не найдены"

if ! patch_game_settings "$CONTAINER_PATH"; then
  patch_user_reg "$USER_REG"
fi

for code in UKR POL GER FR IT SP CH TUR HUNG; do
  ensure_alias_dir "LoreNote fallback ($code)" "$ASSETS/LoreNote/RU" "$ASSETS/LoreNote/$code"
done
for code in POL HUNG; do
  ensure_alias_dir "Ouija fallback ($code)" "$ASSETS/Ouija/RU" "$ASSETS/Ouija/$code"
done

if [ "$START_GAMEHUB" -eq 1 ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    say "[dry-run] GameHub был бы открыт"
  elif [ -d "$GAMEHUB_APP" ]; then
    open "$GAMEHUB_APP"
  else
    say "GameHub.app не найден в /Applications — открой приложение вручную"
  fi
fi

say ""
say "Готово. Запусти Ghost Exile через GameHub и при необходимости нажми Apply в настройках языка."
