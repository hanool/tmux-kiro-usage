#!/usr/bin/env bash

readonly DEFAULT_REFRESH_INTERVAL="300"
readonly ACP_TIMEOUT="20"
readonly INITIALIZE_REQUEST='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{},"clientInfo":{"name":"tmux-kiro-usage","version":"3"}}}'
readonly GET_USAGE_REQUEST='{"jsonrpc":"2.0","id":2,"method":"_kiro/account/getUsage","params":{}}'

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
    printf 'default:acp-v3\n'
    return
  fi

  printf -v escaped_parser '%q' "$parser"
  printf 'custom-acp-v3:%s\n' "$escaped_parser"
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

# Skips notifications until the JSON-RPC response with the given id arrives.
read_response() {
  local input_fd="$1"
  local id="$2"
  local id_regex="\"id\":[[:space:]]*${id}[,}]"
  local line

  while IFS= read -r -t "$ACP_TIMEOUT" line <&"$input_fd"; do
    if [[ "$line" =~ $id_regex ]]; then
      printf '%s\n' "$line"
      return
    fi
  done

  return 1
}

stop_server() {
  local pid="$1"
  local _

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.2
  done
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
}

# Starts a short-lived CLI V3 ACP server and prints the raw getUsage response.
request_usage() {
  local response
  local status=1
  local server_pid
  local acp_in
  local acp_out

  command -v kiro-cli >/dev/null 2>&1 || return 1

  coproc ACP { exec kiro-cli acp --agent-engine=v3 --auth-method=cli 2>/dev/null; }
  server_pid="$ACP_PID"
  acp_out="${ACP[0]}"
  acp_in="${ACP[1]}"

  if printf '%s\n' "$INITIALIZE_REQUEST" 2>/dev/null 1>&"$acp_in" &&
    read_response "$acp_out" 1 > /dev/null &&
    printf '%s\n' "$GET_USAGE_REQUEST" 2>/dev/null 1>&"$acp_in" &&
    response="$(read_response "$acp_out" 2)"; then
    status=0
  fi

  exec {acp_in}>&-
  stop_server "$server_pid"

  [ "$status" -eq 0 ] || return 1
  printf '%s\n' "$response"
}

parse_credits() {
  local response="$1"
  local breakdown_regex='\{[^{}]*"resourceType":[[:space:]]*"CREDIT"[^{}]*\}'
  local used_regex='"used":[[:space:]]*([0-9]+([.][0-9]+)?)[,}]'
  local limit_regex='"limit":[[:space:]]*([0-9]+([.][0-9]+)?)[,}]'
  local breakdown
  local used

  [[ "$response" =~ $breakdown_regex ]] || return 1
  breakdown="${BASH_REMATCH[0]}"

  [[ "$breakdown" =~ $used_regex ]] || return 1
  used="${BASH_REMATCH[1]}"
  [[ "$breakdown" =~ $limit_regex ]] || return 1

  printf '%s/%s\n' "$used" "${BASH_REMATCH[1]}"
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
  local response
  local parsed_output

  response="$(request_usage)" || return 1

  if [ -n "$parser" ]; then
    parsed_output="$(printf '%s\n' "$response" | /bin/sh -c "$parser")" || return 1
  else
    parsed_output="$(parse_credits "$response")" || return 1
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

  if [ "${1:-}" = "--raw" ]; then
    request_usage
    return
  fi

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

main "$@"
