#!/usr/bin/env bash

parse_credits() {
  local line
  local matches=0
  local regex='Credits.*\(([0-9]+([.][0-9]+)?)[[:space:]]+of[[:space:]]+([0-9]+([.][0-9]+)?)[[:space:]]+covered[[:space:]]+in[[:space:]]+plan\)'

  while IFS= read -r line; do
    if [[ "$line" =~ $regex ]]; then
      USED_CREDITS="${BASH_REMATCH[1]}"
      TOTAL_CREDITS="${BASH_REMATCH[3]}"
      ((matches += 1))
    fi
  done

  [ "$matches" -eq 1 ]
}

print_bar() {
  awk -v used="$USED_CREDITS" -v total="$TOTAL_CREDITS" '
    BEGIN {
      width = 10
      if (total <= 0) {
        exit 1
      }

      ratio = used / total
      if (ratio < 0) ratio = 0
      if (ratio > 1) ratio = 1

      units = int(ratio * width * 8 + 0.5)
      full = int(units / 8)
      partial = units % 8
      split("▏ ▎ ▍ ▌ ▋ ▊ ▉", partial_blocks, " ")

      for (i = 0; i < full; i++) printf "█"
      occupied = full

      if (partial > 0) {
        printf "%s", partial_blocks[partial]
        occupied++
      }

      for (i = occupied; i < width; i++) printf "░"
      printf " %s/%s\n", used, total
    }
  '
}

main() {
  local mode="${1:-}"

  case "$mode" in
    bar | credits | used-only) ;;
    *)
      printf 'Usage: %s {bar|credits|used-only}\n' "$0" >&2
      return 2
      ;;
  esac

  parse_credits || return 1

  case "$mode" in
    bar) print_bar ;;
    credits) printf 'Credits (%s of %s covered in plan)\n' "$USED_CREDITS" "$TOTAL_CREDITS" ;;
    used-only) printf '%s\n' "${USED_CREDITS%%.*}" ;;
  esac
}

main "$@"
