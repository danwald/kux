# AGENTS.md — kux

Per-shell kubectl context/namespace isolation, in shell. **Read `docs/DESIGN.md` first**; it is
the spec and records the kubectl behaviours the code depends on (§3).

## 1. Layout

| Path | What |
|---|---|
| `bin/kux` | The whole tool: bash-3.2 executable + embedded zsh/bash shims (`kux init`) |
| `test/*.bats` | bats-core suite, one file per feature |
| `test/helpers.bash` | Isolated `HOME`, fixture kubeconfig, fake `kubectl get namespaces`, `in_shell` |
| `test/fixtures/kubeconfig.yaml` | EKS (incl. an alias collision), GKE, kind contexts |

## 2. Commands

```bash
make check      # shellcheck + shfmt -d + bats
make fmt        # shfmt -w (tabs, per .editorconfig)
make install    # symlink into ~/.local/bin
make bump BUMP=minor
```

## 3. Rules #shell #compat

- `bin/kux` must run on **macOS `/bin/bash` 3.2**: no associative arrays, `mapfile`, `${x,,}`,
  `declare -n`, or `|&`. Use `awk` for anything table-shaped.
- The shims (heredocs in `bin/kux`) run in the user's interactive shell on **every prompt**:
  no forks in the steady state; only builtins and `[[ -nt ]]` tests.
- Never `eval` the executable's stdout in the shim for normal commands; env changes go through
  `$KUX_STATE/env` (see DESIGN §2).
- Any `kubectl config view --minify` must set `KUBECONFIG` to the original list explicitly.
- The overlay must always contain a full stanza for its `current-context` (DESIGN §3.3).

## 4. Glossary

| Term | Meaning |
|---|---|
| overlay | Per-shell kubeconfig fragment, first in `KUBECONFIG`; holds ctx + namespace |
| projection / cluster file | `~/.kube/clusters/<alias>.yaml`, one context extracted from the real config |
| pinned / unpinned | `KUBECONFIG` = overlay + projection / overlay + original list |
| alias | Short, filename-safe context name derived per DESIGN §5 |

## 5. Versioning

`KUX_VERSION` in `bin/kux` is the only version; releases are `vX.Y.Z` git tags.
