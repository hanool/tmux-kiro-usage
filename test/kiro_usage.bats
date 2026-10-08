#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export PROJECT_ROOT
  export PATH="$PROJECT_ROOT/test/bin:$PATH"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export FAKE_KIRO_CALL_LOG="$BATS_TEST_TMPDIR/kiro-calls"
  export FAKE_TMUX_SET_LOG="$BATS_TEST_TMPDIR/tmux-set-calls"

  unset FAKE_KIRO_USED
  unset FAKE_KIRO_TOTAL
  unset FAKE_KIRO_USAGE_MODE
  unset TMUX_KIRO_USAGE_PARSER
  unset TMUX_KIRO_USAGE_REFRESH_INTERVAL
  unset TMUX_STATUS_LEFT
  unset TMUX_STATUS_RIGHT
}

@test "parses changing credit values from the ACP getUsage response" {
  export FAKE_KIRO_USED="73.42"
  export FAKE_KIRO_TOTAL="950"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "73.42/950" ]
  [ "$(cat "$FAKE_KIRO_CALL_LOG")" = "acp --agent-engine=v3 --auth-method=cli" ]
}

@test "base parser does not require awk or cksum" {
  awk() { return 97; }
  cksum() { return 98; }
  export -f awk cksum

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "140.08/2000" ]
}

@test "raw mode prints the getUsage response" {
  export FAKE_KIRO_USED="12.5"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh" --raw

  [ "$status" -eq 0 ]
  [[ "$output" == '{"jsonrpc":"2.0","id":2,"result":'* ]]
  [[ "$output" == *'"used":12.5,"limit":2000'* ]]
}

@test "returns N/A when the response has no credit breakdown" {
  export FAKE_KIRO_USAGE_MODE="no-credit"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "N/A" ]
}

@test "returns N/A when getUsage returns a JSON-RPC error" {
  export FAKE_KIRO_USAGE_MODE="error"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "N/A" ]
}

@test "returns N/A when the ACP server exits early" {
  export FAKE_KIRO_USAGE_MODE="exit"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "N/A" ]
}

@test "returns N/A when kiro-cli is missing" {
  mkdir -p "$BATS_TEST_TMPDIR/no-kiro"
  ln -s "$PROJECT_ROOT/test/bin/tmux" "$BATS_TEST_TMPDIR/no-kiro/tmux"
  export PATH="$BATS_TEST_TMPDIR/no-kiro:/usr/bin:/bin"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "N/A" ]
}

@test "custom parser receives the raw getUsage response" {
  export FAKE_KIRO_USED="81.5"
  export FAKE_KIRO_TOTAL="3000"
  export TMUX_KIRO_USAGE_PARSER="sed -nE 's/.*\"used\":([0-9.]+),\"limit\":([0-9.]+).*/\\1 of \\2/p'"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "81.5 of 3000" ]
}

@test "custom parser uses its last nonempty output line" {
  export TMUX_KIRO_USAGE_PARSER="printf 'ignored\\ncustom-result\\n\\n'"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "custom-result" ]
}

@test "returns N/A when the custom parser fails" {
  export TMUX_KIRO_USAGE_PARSER="false"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "N/A" ]
}

@test "bundled bar parser renders fractional blocks and credit values" {
  export FAKE_KIRO_USED="156.67"
  export FAKE_KIRO_TOTAL="2000"
  export TMUX_KIRO_USAGE_PARSER="$PROJECT_ROOT/examples/kiro_usage_parser.sh bar"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "▊░░░░░░░░░ 156.67/2000" ]
}

@test "bundled bar parser renders complete blocks at exact boundaries" {
  export FAKE_KIRO_USED="400"
  export FAKE_KIRO_TOTAL="2000"
  export TMUX_KIRO_USAGE_PARSER="$PROJECT_ROOT/examples/kiro_usage_parser.sh bar"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "██░░░░░░░░ 400/2000" ]
}

@test "bundled used-only parser removes the decimal portion" {
  export FAKE_KIRO_USED="159.99"
  export FAKE_KIRO_TOTAL="2000"
  export TMUX_KIRO_USAGE_PARSER="$PROJECT_ROOT/examples/kiro_usage_parser.sh used-only"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "159" ]
}

@test "bundled used-only parser preserves integer values" {
  export FAKE_KIRO_USED="159"
  export FAKE_KIRO_TOTAL="2000"
  export TMUX_KIRO_USAGE_PARSER="$PROJECT_ROOT/examples/kiro_usage_parser.sh used-only"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "159" ]
}

@test "bundled credits parser prints a plain Credits line" {
  export FAKE_KIRO_USED="156.67"
  export FAKE_KIRO_TOTAL="2000"
  export TMUX_KIRO_USAGE_PARSER="$PROJECT_ROOT/examples/kiro_usage_parser.sh credits"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "Credits (156.67 of 2000 covered in plan)" ]
}

@test "bundled parser returns N/A without a credit breakdown" {
  export FAKE_KIRO_USAGE_MODE="no-credit"
  export TMUX_KIRO_USAGE_PARSER="$PROJECT_ROOT/examples/kiro_usage_parser.sh credits"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "N/A" ]
}

@test "reuses a successful value during the cache interval" {
  export FAKE_KIRO_USED="10"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"
  [ "$output" = "10/2000" ]

  export FAKE_KIRO_USED="20"
  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "10/2000" ]
  [ "$(wc -l < "$FAKE_KIRO_CALL_LOG")" -eq 1 ]
}

@test "caches N/A during the cache interval" {
  export FAKE_KIRO_USAGE_MODE="no-credit"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"
  [ "$output" = "N/A" ]

  export FAKE_KIRO_USAGE_MODE="valid"
  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "N/A" ]
  [ "$(wc -l < "$FAKE_KIRO_CALL_LOG")" -eq 1 ]
}

@test "zero refresh interval disables the cache" {
  export TMUX_KIRO_USAGE_REFRESH_INTERVAL="0"
  export FAKE_KIRO_USED="10"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"
  [ "$output" = "10/2000" ]

  export FAKE_KIRO_USED="20"
  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "20/2000" ]
  [ "$(wc -l < "$FAKE_KIRO_CALL_LOG")" -eq 2 ]
}

@test "ignores a value cached by the v2 plugin" {
  mkdir -p "$XDG_CACHE_HOME/tmux-kiro-usage"
  printf '%s\ndefault:2.16.0\nstale\n' "$(date +%s)" > "$XDG_CACHE_HOME/tmux-kiro-usage/usage"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "140.08/2000" ]
}

@test "changing the custom parser invalidates its cached value" {
  export TMUX_KIRO_USAGE_PARSER="printf 'first'"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"
  [ "$output" = "first" ]

  export TMUX_KIRO_USAGE_PARSER="printf 'second'"
  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "second" ]
  [ "$(wc -l < "$FAKE_KIRO_CALL_LOG")" -eq 2 ]
}

@test "plugin entrypoint replaces the placeholder in both status options" {
  export TMUX_STATUS_LEFT='left #{kiro_usage}'
  export TMUX_STATUS_RIGHT='right #{kiro_usage}'

  run "$PROJECT_ROOT/kiro-usage.tmux"

  [ "$status" -eq 0 ]
  expected_command="#($PROJECT_ROOT/scripts/kiro_usage.sh)"
  mapfile -t calls < "$FAKE_TMUX_SET_LOG"
  [ "${calls[0]}" = $'status-left\tleft '"$expected_command" ]
  [ "${calls[1]}" = $'status-right\tright '"$expected_command" ]
}
