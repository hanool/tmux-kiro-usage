#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

placeholder='\#{kiro_usage}'
usage_command="#($CURRENT_DIR/scripts/kiro_usage.sh)"

update_tmux_option() {
  local option="$1"
  local value

  value="$(tmux show-option -gqv "$option")"
  tmux set-option -gq "$option" "${value//$placeholder/$usage_command}"
}

main() {
  update_tmux_option "status-left"
  update_tmux_option "status-right"
}

main
