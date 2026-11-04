#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ghost_exile_settings.sh"

APP_ID="1807080"
APP_NAME="Ghost Exile"
TARGET_LANG="russian"
TARGET_LANG_HEX="7275737369616e"
TARGET_GAME_LANG_DWORD="00000001"
GAME_LANG_REG_KEY='GameOptions.General.Language_h2372230879'
DEFAULT_BOTTLE_PATH="$HOME/Library/Application Support/CrossOver/Bottles/Steam"
CROSSOVER_ROOT="/Applications/CrossOver.app/Contents/SharedSupport/CrossOver"
WINE_SERVER="$CROSSOVER_ROOT/bin/wineserver"
DEFAULT_STEAM_APP_BUNDLE="$HOME/Applications/CrossOver/Steam/Steam.app"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

BOTTLE_PATH="$DEFAULT_BOTTLE_PATH"
DRY_RUN=0
CHECK_ONLY=0
KILL_STEAM=0
START_STEAM=0

say() {
  printf '%s\n' "$*"
}

fail() {
  printf 'Ошибка: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Использование:
  $(basename "$0") [--check | --dry-run] [--kill-steam] [--start-steam] [--bottle PATH]

Что делает:
  1. Проверяет bottle Steam в CrossOver
  2. Переключает язык Ghost Exile (AppID $APP_ID) на '$TARGET_LANG'
  3. Правит:
     - steamapps/appmanifest_$APP_ID.acf
     - userdata/*/config/localconfig.vdf
     - user.reg -> $GAME_LANG_REG_KEY=dword:$TARGET_GAME_LANG_DWORD
  4. Делает резервные копии перед изменениями

Опции:
  --check         Показать сборку Steam и языки игры без изменений
  --dry-run       Только показать, что будет изменено
  --kill-steam    Закрыть Steam bottle перед изменениями
  --start-steam   После правок открыть Steam через CrossOver
  --bottle PATH   Нестандартный путь к bottle Steam
  --help          Показать эту справку
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
    return
  fi

  cp "$file" "$backup"
}

stop_steam_bottle() {
  say "Закрываю Steam bottle в CrossOver..."

  if [ "$DRY_RUN" -eq 1 ]; then
    say "[dry-run] would run: WINEPREFIX=\"$BOTTLE_PATH\" \"$WINE_SERVER\" -k"
    return
  fi

  if [ -x "$WINE_SERVER" ]; then
    WINEPREFIX="$BOTTLE_PATH" "$WINE_SERVER" -k >/dev/null 2>&1 || true
  fi

  pkill -f 'steam\.exe' >/dev/null 2>&1 || true
  sleep 2
}

patch_manifest() {
  local manifest="$1"
  local english_count
  local russian_count

  english_count="$(perl -0ne 'my $n = () = /"language"\s*"english"/g; print $n;' "$manifest")"
  russian_count="$(perl -0ne 'my $n = () = /"language"\s*"russian"/g; print $n;' "$manifest")"

  if [ "$english_count" -eq 0 ]; then
    say "appmanifest: переключать нечего, найдено russian=$russian_count"
    return
  fi

  backup_file "$manifest"

  if [ "$DRY_RUN" -eq 1 ]; then
    say "[dry-run] appmanifest: english -> russian ($english_count вх.)"
    return
  fi

  perl -0pi -e 's/("language"\s*")english(")/${1}russian${2}/g' "$manifest"
  say "appmanifest: язык переключён на russian"
}

localconfig_has_english() {
  local file="$1"
  grep -Eq "\"$APP_ID\"[[:space:]]+\"[^\"]*656e676c697368" "$file"
}

localconfig_has_russian() {
  local file="$1"
  grep -Eq "\"$APP_ID\"[[:space:]]+\"[^\"]*${TARGET_LANG_HEX}" "$file"
}

patch_localconfig() {
  local file="$1"

  if ! grep -q "\"$APP_ID\"" "$file"; then
    return
  fi

  if ! localconfig_has_english "$file"; then
    if localconfig_has_russian "$file"; then
      say "localconfig: уже содержит russian -> $file"
    fi
    return
  fi

  backup_file "$file"

  if [ "$DRY_RUN" -eq 1 ]; then
    say "[dry-run] localconfig: english(hex) -> ${TARGET_LANG_HEX} в $file"
    return
  fi

  perl -0pi -e 's/("1807080"\s+"[^"]*?)656e676c697368([^"]*")/${1}7275737369616e${2}/g' "$file"
  say "localconfig: язык переключён на russian -> $file"
}

patch_user_reg() {
  local file="$1"
  local current_value

  [ -f "$file" ] || return

  current_value="$(
    perl -ne 'print lc($1) if /"GameOptions\.General\.Language_h2372230879"=dword:([0-9a-fA-F]{8})/' "$file"
  )"

  if [ -z "$current_value" ]; then
    say "user.reg: ключ $GAME_LANG_REG_KEY не найден, пропускаю"
    return
  fi

  if [ "$current_value" = "$TARGET_GAME_LANG_DWORD" ]; then
    say "user.reg: внутренний язык игры уже выставлен в Russian -> $file"
    return
  fi

  backup_file "$file"

  if [ "$DRY_RUN" -eq 1 ]; then
    say "[dry-run] user.reg: dword:$current_value -> dword:$TARGET_GAME_LANG_DWORD в $file"
    return
  fi

  perl -0pi -e 's/("GameOptions\.General\.Language_h2372230879"=dword:)[0-9a-fA-F]{8}/${1}00000001/g' "$file"
  say "user.reg: внутренний язык игры переключён на Russian -> $file"
}

fix_lorenote_ukr_fallback() {
  local source_dir="$1"
  local target_dir="$2"

  if [ ! -d "$source_dir" ]; then
    say "LoreNote fallback: исходная папка не найдена, пропускаю -> $source_dir"
    return
  fi

  if [ -d "$target_dir" ]; then
    say "LoreNote fallback: папка UKR уже существует -> $target_dir"
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    say "[dry-run] LoreNote fallback: copy $source_dir -> $target_dir"
    return
  fi

  mkdir -p "$target_dir"
  cp -R "$source_dir"/. "$target_dir"/
  say "LoreNote fallback: создана папка UKR из RU -> $target_dir"
}

ensure_alias_dir() {
  local label="$1"
  local source_dir="$2"
  local target_dir="$3"

  if [ ! -d "$source_dir" ]; then
    say "$label: исходная папка не найдена, пропускаю -> $source_dir"
    return
  fi

  if [ -d "$target_dir" ]; then
    say "$label: папка уже существует -> $target_dir"
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    say "[dry-run] $label: copy $source_dir -> $target_dir"
    return
  fi

  mkdir -p "$target_dir"
  cp -R "$source_dir"/. "$target_dir"/
  say "$label: создан alias -> $target_dir"
}

fix_language_aliases() {
  local lorenote_ru_dir="$1"
  local ouija_ru_dir="$2"
  local streaming_assets_root="$3"
  local code

  for code in UKR POL GER FR IT SP CH TUR HUNG; do
    ensure_alias_dir "LoreNote fallback ($code)" \
      "$lorenote_ru_dir" \
      "$streaming_assets_root/LoreNote/$code"
  done

  for code in POL HUNG; do
    ensure_alias_dir "Ouija fallback ($code)" \
      "$ouija_ru_dir" \
      "$streaming_assets_root/Ouija/$code"
  done
}

start_steam() {
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ -d "$DEFAULT_STEAM_APP_BUNDLE" ]; then
      say "[dry-run] would run: open \"$DEFAULT_STEAM_APP_BUNDLE\""
    else
      say "[dry-run] would run: open -a CrossOver"
    fi
    return
  fi

  if [ -d "$DEFAULT_STEAM_APP_BUNDLE" ]; then
    open "$DEFAULT_STEAM_APP_BUNDLE"
    return
  fi

  open -a CrossOver
}

while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK_ONLY=1 ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --kill-steam)
      KILL_STEAM=1
      ;;
    --start-steam)
      START_STEAM=1
      ;;
    --bottle)
      shift
      [ $# -gt 0 ] || fail "для --bottle нужен путь"
      BOTTLE_PATH="$1"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "неизвестная опция: $1"
      ;;
  esac
  shift
done

[ -d "$BOTTLE_PATH" ] || fail "bottle не найден: $BOTTLE_PATH"

locate_game "$BOTTLE_PATH"
USER_REG="$BOTTLE_PATH/user.reg"
LORENOTE_RU_DIR="$STEAM_ROOT/steamapps/common/GhostExile/GhostExile_Data/StreamingAssets/LoreNote/RU"
LORENOTE_UKR_DIR="$STEAM_ROOT/steamapps/common/GhostExile/GhostExile_Data/StreamingAssets/LoreNote/UKR"
OUIJA_RU_DIR="$STEAM_ROOT/steamapps/common/GhostExile/GhostExile_Data/StreamingAssets/Ouija/RU"
STREAMING_ASSETS_ROOT="$STEAM_ROOT/steamapps/common/GhostExile/GhostExile_Data/StreamingAssets"

[ -d "$STEAM_ROOT" ] || fail "Steam не найден внутри bottle: $STEAM_ROOT"
[ -f "$MANIFEST" ] || fail "appmanifest игры не найден: $MANIFEST"
if [ "$CHECK_ONLY" -eq 1 ]; then
  report_game_settings "$BOTTLE_PATH"
  exit 0
fi
[ -f "$USER_REG" ] || fail "реестр bottle не найден: $USER_REG"

say "Bottle: $BOTTLE_PATH"
say "Игра: $APP_NAME ($APP_ID)"
say "Целевой язык: $TARGET_LANG"

if steam_is_running; then
  if [ "$KILL_STEAM" -eq 1 ]; then
    stop_steam_bottle
    if [ "$DRY_RUN" -eq 0 ] && steam_is_running; then
      fail "Steam всё ещё запущен. Закрой его вручную и повтори."
    fi
  elif [ "$DRY_RUN" -eq 1 ]; then
    say "[dry-run] Steam сейчас запущен; в обычном режиме скрипт бы остановился здесь"
  else
    fail "Steam запущен. Закрой CrossOver/Steam или запусти скрипт с --kill-steam."
  fi
fi

patch_manifest "$MANIFEST"

LOCALCONFIG_COUNT=0
while IFS= read -r localconfig; do
  LOCALCONFIG_COUNT=$((LOCALCONFIG_COUNT + 1))
  patch_localconfig "$localconfig"
done < <(find "$STEAM_ROOT/userdata" -type f -path '*/config/localconfig.vdf' 2>/dev/null | sort)

if [ "$LOCALCONFIG_COUNT" -eq 0 ]; then
  say "localconfig: пользовательские конфиги Steam не найдены, пропускаю"
fi

if ! patch_game_settings "$BOTTLE_PATH"; then
  patch_user_reg "$USER_REG"
fi
fix_lorenote_ukr_fallback "$LORENOTE_RU_DIR" "$LORENOTE_UKR_DIR"
fix_language_aliases "$LORENOTE_RU_DIR" "$OUIJA_RU_DIR" "$STREAMING_ASSETS_ROOT"

if [ "$START_STEAM" -eq 1 ]; then
  start_steam
fi

say ""
say "Готово."
say "Если Steam был открыт во время прошлых запусков, лучше полностью перезапустить bottle перед стартом игры."
