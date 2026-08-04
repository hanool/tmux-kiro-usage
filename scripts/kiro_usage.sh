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
  local escaped_parser

  if [ -z "$parser" ]; then
    printf 'default:%s\n' "$SUPPORTED_KIRO_VERSION"
    return
  fi

  printf -v escaped_parser '%q' "$parser"
  printf 'custom:%s\n' "$escaped_parser"
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
  local line
  local result
  local matches=0
  local regex='Credits.*\(([0-9]+([.][0-9]+)?)[[:space:]]+of[[:space:]]+([0-9]+([.][0-9]+)?)[[:space:]]+covered[[:space:]]+in[[:space:]]+plan\)'

  while IFS= read -r line; do
    if [[ "$line" =~ $regex ]]; then
      result="${BASH_REMATCH[1]}/${BASH_REMATCH[3]}"
      ((matches += 1))
    fi
  done

  [ "$matches" -eq 1 ] || return 1
  printf '%s\n' "$result"
}

last_nonempty_line() {
  local line
  local result

  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [[ "$line" =~ [^[:space:]] ]]; then
      result="$line"
    fi
  done

  [ -n "$result" ] || return 1
  printf '%s\n' "$result"
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
    parsed_output="$(printf '%s\n' "$raw_output" | parse_2_16_0)" || return 1
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
