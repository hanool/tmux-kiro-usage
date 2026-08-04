# tmux-kiro-usage

Show Kiro CLI credit usage in the tmux status bar.

The `#{kiro_usage}` placeholder renders the current values reported by Kiro,
for example `140.08/2000`. The values are fetched dynamically and cached for
five minutes by default.

## Requirements

- tmux
- Bash
- An authenticated `kiro-cli` available in the tmux server's `PATH`

The built-in parser currently supports `kiro-cli 2.16.0`.

## Installation

### TPM

Add the status placeholder and plugin before the TPM initialization line in
your tmux configuration:

```tmux
set -g status-right 'Kiro #{kiro_usage}'
set -g @plugin 'hanool/tmux-kiro-usage'

run '~/.tmux/plugins/tpm/tpm'
```

Press `prefix + I` to install the plugin, then reload the configuration.

### Manual

Clone the repository and load its entrypoint:

```shell
git clone https://github.com/hanool/tmux-kiro-usage.git ~/.tmux/plugins/tmux-kiro-usage
```

```tmux
set -g status-right 'Kiro #{kiro_usage}'
run-shell '~/.tmux/plugins/tmux-kiro-usage/kiro-usage.tmux'
```

## Options

### Refresh interval

Kiro usage is cached for 300 seconds so a short tmux `status-interval` does
not repeatedly invoke the CLI.

```tmux
set -g @kiro_usage_refresh_interval 300
```

Set the interval to `0` to disable caching. Failed requests are displayed and
cached as `N/A` for the same interval.

### Custom parser

If a Kiro CLI release changes the `/usage` output, set
`@kiro_usage_parser` to a shell command. The command receives Kiro's raw
terminal output, with stdout and stderr combined and ANSI escape sequences
preserved, through stdin. Its last nonempty output line becomes the status
value.

A custom parser bypasses the built-in Kiro CLI version check. An empty result
or nonzero parser exit status is displayed as `N/A`. The parser is trusted
configuration and is executed with `/bin/sh -c`.

#### Bundled examples

The bundled parser can display a smooth ten-cell usage bar. It uses partial
block characters for one-eighth-cell precision and appends the current credit
values:

```tmux
set -g @kiro_usage_parser "$HOME/.tmux/plugins/tmux-kiro-usage/examples/kiro_usage_parser.sh bar"
```

```text
▊░░░░░░░░░ 156.67/2000
██░░░░░░░░ 400/2000
```

To restore the complete Credits text without ANSI escape sequences, use the
`credits` mode:

```tmux
set -g @kiro_usage_parser "$HOME/.tmux/plugins/tmux-kiro-usage/examples/kiro_usage_parser.sh credits"
```

```text
Credits (156.67 of 2000 covered in plan)
```

The parser does not include colors, so it follows the surrounding status bar
style. Apply a color in the tmux format if desired:

```tmux
set -g status-right '#[fg=colour141]Kiro #{kiro_usage}#[default]'
```

#### Inline parser

The same parser interface accepts inline shell commands. For example:

```tmux
set -g @kiro_usage_parser "sed -nE 's/.*\(([0-9]+([.][0-9]+)?) of ([0-9]+([.][0-9]+)?) covered in plan\).*/\1\/\3/p'"
```

## Compatibility behavior

Without a custom parser, the plugin:

1. Requires the version command to return exactly `kiro-cli 2.16.0`.
2. Runs `kiro-cli chat --no-interactive "/usage"`.
3. Extracts the two numeric values from `Credits (<used> of <total> covered in plan)`.
4. Displays `N/A` if the CLI, authentication, version check, or parsing fails.

Cache data is stored at
`${XDG_CACHE_HOME:-$HOME/.cache}/tmux-kiro-usage/usage`.

## Troubleshooting

If the command works in a terminal but the plugin displays `N/A`, verify the
tmux server environment:

```shell
tmux show-environment -g PATH
command -v kiro-cli
```

Configure the tmux `PATH` with the directory containing `kiro-cli`, or restart
the tmux server after updating your shell environment.

## Development

Run the test and lint suites with:

```shell
bats test
shellcheck kiro-usage.tmux scripts/*.sh examples/*.sh test/bin/*
```

Tests use a fake Kiro CLI and do not access a real account.

## License

[MIT](LICENSE)
