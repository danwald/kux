# kux — design

Per-shell Kubernetes context and namespace isolation. Every client-go tool (`kubectl`, `helm`,
`k9s`, …) sees the same view because kux works only through `KUBECONFIG`.

Decided through a grilling session on 2026-09-29. This document is the reference spec; change it
deliberately.

## 1. Scope

| In v1 | Out of v1 |
|---|---|
| Per-shell ctx + ns, zsh and bash | Fan-out across clusters, `kux exec` |
| Built-in prompt segment | Prod guardrails / styling |
| Picker (`fzf`, `select` fallback) | tmux status line, inherit-on-split |
| Derived aliases, no config file | fish, nushell |
| `git clone` + symlink install | CI, Homebrew, release tarballs |

## 2. Architecture

- `bin/kux` — one bash-3.2 executable. `kux init zsh|bash` prints a shim (embedded heredoc).
- The shim defines a `kux` shell function. It runs the executable, then sources
  `$KUX_STATE/env` if the executable left one (pending environment changes). stdout is never
  `eval`ed, so listing, piping and the picker work normally.
- Hard dependency: `kubectl`. Optional: `fzf`.

### 2.1 Files

| Path | Purpose |
|---|---|
| `~/.kube/config` (or the original `KUBECONFIG` list) | Source of truth, managed by your tooling |
| `~/.kube/clusters/<alias>.yaml` | Projection: single-context file, `0600`, via `kubectl config view --raw --minify --flatten` |
| `$XDG_STATE_HOME/kux/shells/<id>/` | Per-shell state (see below) |
| `$XDG_CACHE_HOME/kux/ns/<cksum>` | Namespace list per real context name (first line: fetch epoch), TTL `KUX_NS_TTL` = 300 s, shared |

Per-shell state directory:

| File | Contents |
|---|---|
| `overlay.yaml` | `current-context` + **one full context stanza** (cluster, user, namespace) |
| `meta` | `<pid><TAB><ps lstart>` of the owning shell — liveness |
| `cluster_file` | Path of the projection when pinned; absent when unpinned |
| `prev_ctx` | Previous real context name (for `kux ctx -`) |
| `ns/<alias>`, `prevns/<alias>` | Remembered current / previous namespace per context |
| `prompt` | One line of prompt text, written by kux |
| `env` | Pending exports for the shim; deleted once sourced |

### 2.2 `KUBECONFIG` states

| State | `KUBECONFIG` | Visible contexts |
|---|---|---|
| Unpinned (new shell, after `kux unset`) | `overlay:<original>` | all |
| Pinned (`kux ctx X`) | `overlay:~/.kube/clusters/<alias>.yaml` | only X |

`KUX_ORIG_KUBECONFIG` holds the original value (`$HOME/.kube/config` if it was unset). Every
state is recomputed from it, so re-running init is idempotent.

## 3. kubectl facts this design rests on (verified on kubectl 1.36)

1. Writes (`use-context`, `set-context`, `set-cluster`, `aws eks update-kubeconfig`) go to the
   **first** file in `KUBECONFIG`, or to the file already defining the entry.
2. Context entries do **not** deep-merge. An overlay stanza must restate `cluster` and `user`.
3. If the overlay has no stanza for the current context, `set-context --current --namespace`
   rewrites the **real** config. The overlay therefore always carries that stanza, and prompt
   refresh repairs an overlay whose `current-context` points elsewhere (after an external
   `use-context`).
4. There is no namespace environment variable; namespace must live in a file.
5. `--minify` against a `KUBECONFIG` that already contains an overlay minifies the overlay.
   Projection always runs with `KUBECONFIG` set to the original list.

## 4. Commands

| Command | Behaviour |
|---|---|
| `kux` | Print state (context, alias, namespace, pinned/unpinned, markers) |
| `kux ctx` | Picker on a TTY, else one alias per line |
| `kux ctx <name>` / `kux ctx -` | Pin to a context / previous context |
| `kux ns` | Picker on a TTY (ctrl-r refreshes), else one namespace per line |
| `kux ns <name>` / `kux ns -` | Set namespace (not validated) / previous namespace for this context |
| `kux unset` | Back to the unpinned state a new shell starts in |
| `kux refresh` | Regenerate this shell's projection and drop its namespace cache |
| `kux promote` | Move foreign `clusters:`/`users:`/contexts from the overlay into the real config |
| `kux status [--json]` | State, machine-readable with `--json` |
| `kux init zsh\|bash [--no-prompt]` | Print the shim |
| `kux --version` | Version |
| `kux gc` (hidden) | Sweep dead shells' state |

Name resolution: exact real name → exact alias → unique substring of an alias → error listing the
candidates. Ambiguity is never resolved silently.

## 5. Aliases

| Context form | Alias | On collision |
|---|---|---|
| `arn:aws:eks:<region>:<acct>:cluster/<name>` | `<name>` | `<name>@<acct>` |
| `gke_<project>_<zone>_<name>` | `<name>` | `<name>@<project>` |
| anything else | name with `/` and `:` → `_` | full sanitised name |

Collisions are computed over the whole list every time. If a disambiguated alias still collides
(same account, same name, different region) it falls back to the full sanitised name.

## 6. Prompt

zsh prepends to `RPROMPT`, bash prepends `[…] ` to `PS1`, both idempotent (a prompt changed by
another tool becomes the new base); `--no-prompt` skips that and
leaves `$_KUX_PROMPT` for manual placement. Steady state costs **no process**: the hook reads
`prompt` with the `read` builtin and runs only `test`-style checks.

Text: `☸ <alias>:<namespace>` (namespace `default` when unset), followed by markers:

| Marker | Meaning | Fix |
|---|---|---|
| `☸ ?` | Overlay missing (swept, reboot) | next `kux` command self-heals |
| `!promote` | Something wrote `clusters:`/`users:` into the overlay | `kux promote` |
| `!stale` | Original kubeconfig is newer than this shell's projection | `kux refresh` |
| `!edited` | `KUBECONFIG` was changed by hand; kux leaves it alone | `kux ctx …` / `kux unset` |

The hook forks `kux _prompt` only when the overlay is newer than `prompt` (an external write).
That refresh also repairs a `current-context` left without a stanza by an external `use-context`.
While `!promote` is showing, kux refuses to rewrite the overlay so nothing is lost.
`\ $ ` %` in names are replaced with `_` in the prompt text so it is inert in both shells.

## 7. Lifetime

- Shell id: random, minted at init. `KUX_PID` records the owning shell. A shell that inherits
  `KUX_ID` from its parent (nested shell, tmux server env) mints its own.
- Liveness sweep on every init and `kux gc`: remove a state dir when no process matches the
  recorded pid **and** start time (defeats PID reuse). Exit hooks (`zshexit`, bash `EXIT` trap if
  none is set) are only a fast path.

## 8. Known limitations

- `-nt` has one-second resolution; an external overlay write in the same second as kux's own
  prompt write is picked up on the next change.
- Projection files are keyed by alias. If an alias is reassigned to a different context (the
  original cluster deleted and a same-named one added), a shell still pinned to the old one sees
  the new file after a refresh. EKS/GKE cluster and user names are the full ARN/ID, so kubectl
  fails loudly rather than talking to the wrong cluster.
- `kux promote` rewrites the real config via `kubectl config view --raw`: comments and key order
  are not preserved. A backup is written to `<config>.kux-bak`.
