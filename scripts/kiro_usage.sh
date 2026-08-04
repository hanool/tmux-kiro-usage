#!/usr/bin/env bash

readonly SUPPORTED_KIRO_VERSION="2.16.0"
readonly DEFAULT_REFRESH_INTERVAL="300"

get_tmux_option() {
  local option="$1"
  local default_value="${2:-}"
  local value

  value="$(tmux show-option -gqv "$option" 2>/dev/null)"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$default_value"
  fi
}

get_refresh_interval() {
  local interval

  interval="$(get_tmux_option "@kiro_usage_refresh_interval" "$DEFAULT_REFRESH_INTERVAL")"
  case "$interval" in
    '' | *[!0-9]*) printf '%s\n' "$DEFAULT_REFRESH_INTERVAL" ;;
    *) printf '%s\n' "$interval" ;;
  esac
}

get_cache_key() {
  local parser="$1"
  local checksum

  if [ -z "$parser" ]; then
    printf 'default:%s\n' "$SUPPORTED_KIRO_VERSION"
    return
  fi

  checksum="$(printf '%s' "$parser" | cksum | awk '{ print $1 ":" $2 }')"
  printf 'custom:%s\n' "$checksum"
}

read_cache() {
  local cache_file="$1"
  local expected_key="$2"
  local refresh_interval="$3"
  local cached_at
  local cached_key
  local cached_value
  local now
  local age

  [ -r "$cache_file" ] || return 1

  {
    IFS= read -r cached_at
    IFS= read -r cached_key
    IFS= read -r cached_value
  } < "$cache_file"

  case "$cached_at" in
    '' | *[!0-9]*) return 1 ;;
  esac
  [ "$cached_key" = "$expected_key" ] || return 1

  now="$(date +%s)"
  age=$((now - cached_at))
  [ "$age" -ge 0 ] && [ "$age" -lt "$refresh_interval" ] || return 1

  printf '%s\n' "${cached_value:-N/A}"
}

write_cache() {
  local cache_dir="$1"
  local cache_file="$2"
  local cache_key="$3"
  local value="$4"
  local temporary_file

  umask 077
  mkdir -p "$cache_dir" 2>/dev/null || return

  temporary_file="$cache_file.$$"
  if printf '%s\n%s\n%s\n' "$(date +%s)" "$cache_key" "$value" > "$temporary_file" &&
    mv -f "$temporary_file" "$cache_file"; then
    return
  fi

  rm -f "$temporary_file"
}

parse_2_16_0() {
  awk '
    index($0, "Credits") && index($0, "covered in plan") {
      line = $0
      sub(/^.*\(/, "", line)
      sub(/\).*$/, "", line)

      if (split(line, parts, /[[:space:]]+of[[:space:]]+/) != 2) {
        next
      }

      used = parts[1]
      total = parts[2]
      sub(/[[:space:]]+covered[[:space:]]+in[[:space:]]+plan$/, "", total)

      number = "^[0-9]+([.][0-9]+)?$"
      if (used ~ number && total ~ number) {
        result = used "/" total
        matches++
      }
    }

    END {
      if (matches == 1) {
        print result
      }
    }
  '
}

last_nonempty_line() {
  awk 'NF { line = $0 } END { sub(/\r$/, "", line); if (line != "") print line }'
}

fetch_usage() {
  local parser="$1"
  local raw_output
  local parsed_output
  local version

  command -v kiro-cli >/dev/null 2>&1 || return 1

  if [ -z "$parser" ]; then
    version="$(kiro-cli --version 2>/dev/null)" || return 1
    [ "$version" = "kiro-cli $SUPPORTED_KIRO_VERSION" ] || return 1
  fi

  raw_output="$(kiro-cli chat --no-interactive "/usage" 2>&1)" || return 1

  if [ -n "$parser" ]; then
    parsed_output="$(printf '%s\n' "$raw_output" | /bin/sh -c "$parser")" || return 1
  else
    parsed_output="$(printf '%s\n' "$raw_output" | parse_2_16_0)"
  fi

  printf '%s\n' "$parsed_output" | last_nonempty_line
}

main() {
  local parser
  local refresh_interval
  local cache_key
  local cache_dir
  local cache_file
  local cached_value
  local value

  parser="$(get_tmux_option "@kiro_usage_parser")"
  refresh_interval="$(get_refresh_interval)"
  cache_key="$(get_cache_key "$parser")"
  cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-kiro-usage"
  cache_file="$cache_dir/usage"

  if cached_value="$(read_cache "$cache_file" "$cache_key" "$refresh_interval")"; then
    printf '%s\n' "$cached_value"
    return
  fi

  value="$(fetch_usage "$parser")"
  if [ -z "$value" ]; then
    value="N/A"
  fi

  write_cache "$cache_dir" "$cache_file" "$cache_key" "$value"
  printf '%s\n' "$value"
}

main
