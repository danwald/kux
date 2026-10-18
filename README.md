# kux

`kubectl config use-context` is global: switch to prod in one terminal and **every** terminal is
now on prod. kux gives each shell its own Kubernetes context and namespace, so everything you run
in a terminal (`kubectl`, `helm`, `k9s`, …) talks only to the cluster you picked in *that*
terminal. Works in zsh and bash, including each tmux pane, with no wrappers around any tool.

```
tab 1 $ kux ctx prod                       ☸ prod:default
tab 2 $ kux ctx staging                    ☸ staging:default
tab 2 $ kux ns web                         ☸ staging:web
tab 1 $ kubectl get pods                   # still prod, default namespace
```

## Install

```bash
git clone https://github.com/danwald/kux ~/src/kux
make -C ~/src/kux install            # symlinks ~/.local/bin/kux
echo 'eval "$(kux init zsh)"' >> ~/.zshrc   # or: eval "$(kux init bash)" in ~/.bashrc
```

Requires `kubectl`. Uses `fzf` for the picker when installed.

## Usage

Two terms first:

- **Unpinned**: how every new shell starts. It sees your whole kubeconfig and its current context,
  but `kubectl config use-context` / `set-context` / `kux ns` only change *this* shell.
- **Pinned**: after `kux ctx <name>`. The shell sees only that one cluster, so nothing in it can
  reach any other cluster by mistake.

```bash
kux                  # this shell's context, namespace, mode and any warnings
kux ctx              # fzf picker (or a numbered menu); `kux ctx | grep prod` lists aliases
kux ctx staging      # pin this shell: exact name, alias, or a unique substring of an alias
kux ctx -            # back to the previous context
kux ns               # namespace picker (ctrl-r re-fetches), cached for 5 minutes
kux ns payments      # set this shell's namespace; `kux ns -` toggles back
kux unset            # unpin: back to how a new shell starts
kux refresh          # update this shell's cluster file after your kubeconfig changed
kux promote          # move credentials a cloud CLI wrote into this shell into ~/.kube/config
kux status --json    # for scripts
```

Context names get short **aliases**: `arn:aws:eks:us-east-1:111111111111:cluster/prod` becomes
`prod`, or `prod@111111111111` when two accounts both have a `prod`. `gke_proj_zone_dev` becomes
`dev`.

### Prompt

The shim adds `☸ <alias>:<namespace>` to `RPROMPT` (zsh) or prefixes `PS1` with it (bash).
Markers after it are problems, and each one says how to fix it:

| Marker | Fix |
|---|---|
| `?` | state lost; the next `kux` command recreates it |
| `!promote` | something wrote cluster credentials into this shell's config: `kux promote` |
| `!stale` | your kubeconfig changed since this shell pinned: `kux refresh` |
| `!edited` | `KUBECONFIG` was changed by hand: `kux ctx …` or `kux unset` |

To place it yourself, use `eval "$(kux init zsh --no-prompt)"` (or `bash`) and put
`$(kux_prompt)` (or `$_KUX_PROMPT`, updated before each prompt) where you want it, e.g. in a
starship `custom` module or `PROMPT='…$(kux_prompt)…'` with `setopt prompt_subst`. To skip it
only inside tmux: `eval "$(kux init zsh ${TMUX:+--no-prompt})"`.

### tmux status line

tmux runs status-line commands outside your shells, so tools like
[kube-tmux](https://github.com/jonmosco/kube-tmux) see the global context. Point them at the
focused pane's kux state via `#{pane_pid}` instead:

```
#(d=$(ls -d $HOME/.local/state/kux/shells/#{pane_pid}-* 2>/dev/null | head -1); KUBECONFIG=${d:+$d/overlay.yaml:}${KUBECONFIG:-$HOME/.kube/config} $TMUX_PLUGIN_MANAGER_PATH/kube-tmux/kube.tmux)
```

Keep it on one line. Panes without kux fall back to the normal `KUBECONFIG`. It shows the real
context name, updates every `status-interval`, and follows the pane's first shell (not nested
ones). It assumes shells start with `~/.kube/config`.

## How it works

Everything goes through the `KUBECONFIG` variable, which every Kubernetes tool already reads.

1. `kux init` gives each shell a small private kubeconfig, the **overlay**, and sets
   `KUBECONFIG=<overlay>:~/.kube/config`.
2. kubectl writes changes to the **first** file in `KUBECONFIG`. So `use-context`, `set-context
   --namespace` and `kux ns` change this shell's overlay, never your real config.
3. `kux ctx prod` copies just that context into `~/.kube/clusters/prod.yaml` and sets
   `KUBECONFIG=<overlay>:~/.kube/clusters/prod.yaml`. Other clusters are no longer in reach.
4. The prompt reads a small file kux keeps up to date, so it costs no extra process per prompt.

[docs/DESIGN.md](docs/DESIGN.md) has the full design and the kubectl behaviours it relies on.

### What it touches

| Path | What | Lifetime |
|---|---|---|
| `~/.local/state/kux/shells/<id>/` | per-shell overlay and state | removed when the shell exits; leftovers swept by the next new shell |
| `~/.kube/clusters/<alias>.yaml` | one context copied from your kubeconfig (includes its credentials) | kept, reused by every shell pinned to it |
| `~/.cache/kux/ns/` | namespace lists for the picker | refetched after `KUX_NS_TTL` |
| `~/.kube/config` | read only | changed only by `kux promote`, which backs it up to `config.kux-bak` first |

### Environment

| Variable | Default | |
|---|---|---|
| `KUX_NS_TTL` | `300` | namespace cache lifetime, seconds |
| `KUX_CLUSTERS_DIR` | `~/.kube/clusters` | where per-context cluster files live |
| `XDG_STATE_HOME` | `~/.local/state` | per-shell state lives under `kux/shells/` |

## Uninstall

Remove the `kux init` line from your rc file, then:

```bash
make -C ~/src/kux uninstall          # removes ~/.local/bin/kux and ~/.local/state/kux
```

Removing the state matters: nothing sweeps it once kux is gone, and anything that looks up a
shell's state by pid (e.g. the tmux status line) could match a stale entry. `~/.kube/clusters/`
and `~/.cache/kux/` are left in place; delete them too if nothing else uses them.

## Development

```bash
brew install bats-core shellcheck shfmt kubernetes-cli
make check
```

CI runs `make check` on macOS for every PR and push to `main`.
