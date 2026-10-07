# kux

Per-shell Kubernetes context and namespace for zsh and bash. Every terminal, tmux pane, and
the tools you run from it (`kubectl`, `helm`, `k9s`, …) see only the cluster you picked in *that*
shell. It works purely through `KUBECONFIG`, so nothing needs wrapping.

## Install

```bash
git clone https://github.com/danwald/kux ~/src/kux
make -C ~/src/kux install            # symlinks ~/.local/bin/kux
echo 'eval "$(kux init zsh)"' >> ~/.zshrc   # or: eval "$(kux init bash)" in ~/.bashrc
```

Requires `kubectl`. Uses `fzf` for the picker when installed.

## Usage

```bash
kux                  # this shell's context, namespace, mode and any warnings
kux ctx              # fzf picker (or a numbered menu); `kux ctx | grep prod` lists aliases
kux ctx staging      # pin this shell: exact name, alias, or a unique substring of an alias
kux ctx -            # back to the previous context
kux ns               # namespace picker (ctrl-r re-fetches), cached for 5 minutes
kux ns payments      # set this shell's namespace; `kux ns -` toggles back
kux unset            # unpin: all contexts visible again, as in a new shell
kux refresh          # regenerate the cluster file after the real kubeconfig changed
kux promote          # move clusters/users a cloud CLI wrote into this shell into ~/.kube/config
kux status --json    # for scripts
```

Aliases are short: `arn:aws:eks:us-east-1:111111111111:cluster/prod` becomes `prod`, or
`prod@111111111111` when two accounts both have a `prod`. `gke_proj_zone_dev` becomes `dev`.

A new shell starts **unpinned**: it sees your whole kubeconfig and its current context, but
`kubectl config use-context` / `set-context` in it only affect that shell. `kux ctx` pins it to
one context, so tools in that shell cannot reach any other cluster.

### Prompt

The shim adds `☸ <alias>:<namespace>` to `RPROMPT` (zsh) or prefixes `PS1` with it (bash).
Markers after it are problems, and each one says how to fix it:

| Marker | Fix |
|---|---|
| `?` | state lost; the next `kux` command recreates it |
| `!promote` | something wrote cluster credentials into this shell's config: `kux promote` |
| `!stale` | your kubeconfig changed since this shell pinned: `kux refresh` |
| `!edited` | `KUBECONFIG` was changed by hand: `kux ctx …` or `kux unset` |

To place it yourself, use `eval "$(kux init zsh --no-prompt)"` and put `$(kux_prompt)` (or
`$_KUX_PROMPT`, updated before each prompt) where you want it, e.g. in a starship `custom`
module or `PROMPT='…$(kux_prompt)…'` with `setopt prompt_subst`.

### Environment

| Variable | Default | |
|---|---|---|
| `KUX_NS_TTL` | `300` | namespace cache lifetime, seconds |
| `KUX_CLUSTERS_DIR` | `~/.kube/clusters` | where per-context cluster files live |
| `XDG_STATE_HOME` | `~/.local/state` | per-shell state lives under `kux/shells/` |

## Development

```bash
brew install bats-core shellcheck shfmt
make check
```

See [docs/DESIGN.md](docs/DESIGN.md) for how it works.
