# tmux-kiro-usage

Show your Kiro CLI credit usage in the tmux status bar.

![tmux status bar showing Kiro usage](./screenshots/tmux-kiro-usage.png)

By default, `#{kiro_usage}` displays the used and total credits:

```text
156.67/2000
```

The built-in parser supports `kiro-cli 2.16.0`. You can provide a custom
parser to change the displayed text or support a different Kiro CLI version.

## Requirements

- tmux
- Bash
- An authenticated `kiro-cli` available in the tmux server's `PATH`

## Installation

### TPM

Add the placeholder and plugin before the TPM initialization line in your
tmux configuration:

```tmux
set -ag status-right ' Kiro #{kiro_usage}'

set -g @plugin 'hanool/tmux-kiro-usage'

# Keep TPM initialization at the bottom of the file.
run '~/.tmux/plugins/tpm/tpm'
```

Press `prefix + I` to install the plugin, then reload the configuration:

```shell
tmux source-file ~/.tmux.conf
```

### Manual installation

```shell
git clone https://github.com/hanool/tmux-kiro-usage.git \
  ~/.tmux/plugins/tmux-kiro-usage
```

```tmux
set -ag status-right ' Kiro #{kiro_usage}'
run-shell '~/.tmux/plugins/tmux-kiro-usage/kiro-usage.tmux'
```

## Usage

Add `#{kiro_usage}` anywhere in `status-left` or `status-right`. The plugin
replaces the placeholder with a background command that fetches Kiro usage.

```tmux
set -ag status-right ' Kiro #{kiro_usage}'
```

Usage is cached for 300 seconds by default. Change the refresh interval with
`@kiro_usage_refresh_interval`:

```tmux
set -g @kiro_usage_refresh_interval 60  # refresh every minute
```

Set it to `0` to disable caching. Failures are displayed and cached as `N/A`
for the same interval.

## Customize the output

A custom parser lets you format the status text however you want. It also lets
you use this plugin with a Kiro CLI version that the built-in parser does not
support.

### 1. Inspect the Kiro output

Run the same command used by the plugin:

```shell
kiro-cli chat --no-interactive "/usage" 2>&1
```

For `kiro-cli 2.16.0`, the relevant line looks like this:

```text
Credits (156.67 of 2000 covered in plan)
```

The values will change as you use Kiro.

### 2. Create a parser

A parser reads the raw Kiro output from stdin and prints the one line that
should appear in the tmux status bar. For example, create
`~/.config/tmux/kiro-usage-parser.sh` with the following content:

```bash
#!/usr/bin/env bash

sed -nE 's/.*Credits.*\(([0-9]+([.][0-9]+)?) of ([0-9]+([.][0-9]+)?) covered in plan\).*/\1\/\3/p'
```

Make it executable:

```shell
chmod +x ~/.config/tmux/kiro-usage-parser.sh
```

The parser may use Bash, awk, sed, Python, or any other command available on
your system. It only needs to accept stdin and print a nonempty result.

### 3. Test the parser

Test the parser before adding it to tmux:

```shell
kiro-cli chat --no-interactive "/usage" 2>&1 |
  ~/.config/tmux/kiro-usage-parser.sh
```

Expected output:

```text
156.67/2000
```

### 4. Configure tmux

Set `@kiro_usage_parser` to the parser command:

```tmux
set -g @kiro_usage_parser "$HOME/.config/tmux/kiro-usage-parser.sh"
```

Then reload tmux:

```shell
tmux source-file ~/.tmux.conf
tmux refresh-client -S
```

The plugin passes the combined stdout and stderr from Kiro to the parser's
stdin. It displays the parser's last nonempty output line. A nonzero exit code
or empty output is displayed as `N/A`. Setting a custom parser bypasses the
built-in Kiro CLI version check.

## Bundled parser examples

Example parsers are installed with the plugin at:

```text
~/.tmux/plugins/tmux-kiro-usage/examples/kiro_usage_parser.sh
```

The full implementation is available in
[`examples/kiro_usage_parser.sh`](./examples/kiro_usage_parser.sh). It provides
the following modes.

### Smooth usage bar

Test it directly:

```shell
kiro-cli chat --no-interactive "/usage" 2>&1 |
  ~/.tmux/plugins/tmux-kiro-usage/examples/kiro_usage_parser.sh bar
```

Configure it:

```tmux
set -g @kiro_usage_parser "$HOME/.tmux/plugins/tmux-kiro-usage/examples/kiro_usage_parser.sh bar"
```

Output:

```text
▊░░░░░░░░░ 156.67/2000
```

### Used credits only

This mode removes the decimal portion without rounding.

Test it directly:

```shell
kiro-cli chat --no-interactive "/usage" 2>&1 |
  ~/.tmux/plugins/tmux-kiro-usage/examples/kiro_usage_parser.sh used-only
```

Configure it:

```tmux
set -g @kiro_usage_parser "$HOME/.tmux/plugins/tmux-kiro-usage/examples/kiro_usage_parser.sh used-only"
```

Output:

```text
159
```

### Full Credits line

Test it directly:

```shell
kiro-cli chat --no-interactive "/usage" 2>&1 |
  ~/.tmux/plugins/tmux-kiro-usage/examples/kiro_usage_parser.sh credits
```

Configure it:

```tmux
set -g @kiro_usage_parser "$HOME/.tmux/plugins/tmux-kiro-usage/examples/kiro_usage_parser.sh credits"
```

Output:

```text
Credits (156.67 of 2000 covered in plan)
```

To return to the default `used/total` output, remove the
`@kiro_usage_parser` setting from your configuration and unset the current
tmux option:

```shell
tmux set-option -gu @kiro_usage_parser
tmux refresh-client -S
```

## Troubleshooting

### The status shows `N/A`

Check Kiro first:

```shell
kiro-cli --version
kiro-cli chat --no-interactive "/usage" 2>&1
```

If you configured a parser, run the parser pipeline directly. This shows parser
errors that tmux normally hides:

```shell
kiro-cli chat --no-interactive "/usage" 2>&1 |
  ~/.config/tmux/kiro-usage-parser.sh
```

For a bundled parser, verify that the installed plugin contains the example:

```shell
test -x ~/.tmux/plugins/tmux-kiro-usage/examples/kiro_usage_parser.sh
```

If the file is missing, update the plugin with `prefix + U` or run:

```shell
git -C ~/.tmux/plugins/tmux-kiro-usage pull --ff-only
```

After fixing the command or parser, wait for the configured refresh interval
or remove the cached result before refreshing the status bar:

```shell
rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/tmux-kiro-usage/usage"
tmux refresh-client -S
```

The tmux server must also be able to find `kiro-cli`:

```shell
tmux show-environment -g PATH
command -v kiro-cli
```

### The placeholder is still visible

Inspect the expanded status option:

```shell
tmux show-option -gqv status-right
```

If `#{kiro_usage}` has not been replaced, run the plugin entrypoint and refresh
the status bar:

```shell
tmux run-shell ~/.tmux/plugins/tmux-kiro-usage/kiro-usage.tmux
tmux refresh-client -S
```

## Development

```shell
bats test
shellcheck kiro-usage.tmux scripts/*.sh examples/*.sh test/bin/*
```

Tests use a fake Kiro CLI and do not access a real account.

## License

[MIT](LICENSE)
