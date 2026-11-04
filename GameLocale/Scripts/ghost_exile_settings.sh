# Shared by both Wine launchers. The old registry preference remains the
# fallback for builds that do not have the new settings file.
patch_game_settings() {
  local prefix="$1" profile file status temp
  local found=0

  for profile in "$prefix"/drive_c/users/*; do
    file="$profile/AppData/LocalLow/LostOneTeam/GhostExile/ge_settings.gs"
    [ -f "$file" ] || continue
    found=1
    if perl "$SCRIPT_DIR/ghost_exile_settings.pl" check "$file"; then
      say "ge_settings.gs: интерфейс и распознавание речи уже на русском -> $file"
      continue
    else
      status=$?
    fi
    case "$status" in
      1) ;;
      2)
        say "ge_settings.gs: неизвестный формат. Выбери русский язык интерфейса и распознавания речи в игре -> $file"
        continue
        ;;
      *) fail "не удалось прочитать настройки: $file" ;;
    esac

    backup_file "$file" || fail "не удалось создать резервную копию: $file"
    if [ "$DRY_RUN" -eq 1 ]; then
      say "[dry-run] ge_settings.gs: интерфейс и распознавание речи -> русский ($file)"
      continue
    fi

    temp="$(mktemp "$file.tmp.XXXXXX")" || fail "не удалось создать временный файл: $file"
    if ! cp -p "$file" "$temp" ||
       ! perl "$SCRIPT_DIR/ghost_exile_settings.pl" patch "$temp" ||
       ! mv -f "$temp" "$file"; then
      rm -f "$temp"
      fail "не удалось обновить настройки: $file"
    fi
    say "ge_settings.gs: интерфейс и распознавание речи переключены на русский -> $file"
  done

  if [ "$found" -eq 0 ]; then
    say "ge_settings.gs: файл не найден. Для Ghost Exile 2.x запусти игру один раз, закрой её и повтори."
    return 1
  fi
}

locate_game() {
  STEAM_ROOT="$1/drive_c/Program Files (x86)/Steam"
  MANIFEST="$STEAM_ROOT/steamapps/appmanifest_${APP_ID}.acf"
  [ -f "$MANIFEST" ] || fail "манифест Ghost Exile не найден: $MANIFEST"
}

report_game_settings() {
  local prefix="$1" build profile file status
  local found=0
  build="$(perl -ne 'if (/^\s*"buildid"\s*"([0-9]+)"/i) { print $1; exit }' "$MANIFEST")"
  say "Установка: $prefix"
  say "Сборка Steam: ${build:-не указана}"

  for profile in "$prefix"/drive_c/users/*; do
    file="$profile/AppData/LocalLow/LostOneTeam/GhostExile/ge_settings.gs"
    [ -f "$file" ] || continue
    found=1
    say "Настройки: $file"
    if perl "$SCRIPT_DIR/ghost_exile_settings.pl" report "$file"; then
      continue
    else
      status=$?
    fi
    [ "$status" -eq 2 ] || fail "не удалось прочитать настройки: $file"
    say "Статус: неизвестный формат настроек"
  done
  if [ "$found" -eq 0 ]; then
    say "Статус: файл настроек не найден. Для Ghost Exile 2.x сначала запусти игру один раз."
  fi
}
