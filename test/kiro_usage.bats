#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export PROJECT_ROOT
  export PATH="$PROJECT_ROOT/test/bin:$PATH"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export FAKE_KIRO_CALL_LOG="$BATS_TEST_TMPDIR/kiro-calls"
  export FAKE_TMUX_SET_LOG="$BATS_TEST_TMPDIR/tmux-set-calls"

  unset FAKE_KIRO_VERSION
  unset FAKE_KIRO_USED
  unset FAKE_KIRO_TOTAL
  unset FAKE_KIRO_USAGE_MODE
  unset TMUX_KIRO_USAGE_PARSER
  unset TMUX_KIRO_USAGE_REFRESH_INTERVAL
  unset TMUX_STATUS_LEFT
  unset TMUX_STATUS_RIGHT
}

@test "parses changing credit values from kiro-cli 2.16.0 ANSI output" {
  export FAKE_KIRO_USED="73.42"
  export FAKE_KIRO_TOTAL="950"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "73.42/950" ]
}

@test "returns N/A for an unsupported kiro-cli version" {
  export FAKE_KIRO_VERSION="2.17.0"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "N/A" ]
  [ "$(wc -l < "$FAKE_KIRO_CALL_LOG")" -eq 1 ]
}

@test "returns N/A when the usage output cannot be parsed" {
  export FAKE_KIRO_USAGE_MODE="malformed"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "N/A" ]
}

@test "returns N/A when kiro-cli fails" {
  export FAKE_KIRO_USAGE_MODE="fail"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "N/A" ]
}

@test "custom parser bypasses the version check and receives raw output" {
  export FAKE_KIRO_VERSION="9.0.0"
  export FAKE_KIRO_USAGE_MODE="custom"
  export FAKE_KIRO_USED="81.5"
  export FAKE_KIRO_TOTAL="3000"
  export TMUX_KIRO_USAGE_PARSER="awk '/Usage credits:/ { print \$3 \"/\" \$5 }'"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "81.5/3000" ]
  [ "$(wc -l < "$FAKE_KIRO_CALL_LOG")" -eq 1 ]
}

@test "custom parser uses its last nonempty output line" {
  export FAKE_KIRO_USAGE_MODE="custom"
  export TMUX_KIRO_USAGE_PARSER="printf 'ignored\\ncustom-result\\n\\n'"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "custom-result" ]
}

@test "returns N/A when the custom parser fails" {
  export FAKE_KIRO_USAGE_MODE="custom"
  export TMUX_KIRO_USAGE_PARSER="false"

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
  [ "$(wc -l < "$FAKE_KIRO_CALL_LOG")" -eq 2 ]
}

@test "caches N/A during the cache interval" {
  export FAKE_KIRO_USAGE_MODE="malformed"

  run "$PROJECT_ROOT/scripts/kiro_usage.sh"
  [ "$output" = "N/A" ]

  export FAKE_KIRO_USAGE_MODE="valid"
  run "$PROJECT_ROOT/scripts/kiro_usage.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "N/A" ]
  [ "$(wc -l < "$FAKE_KIRO_CALL_LOG")" -eq 2 ]
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
  [ "$(wc -l < "$FAKE_KIRO_CALL_LOG")" -eq 4 ]
}

@test "changing the custom parser invalidates its cached value" {
  export FAKE_KIRO_USAGE_MODE="custom"
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
