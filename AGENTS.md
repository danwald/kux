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
- `write_overlay` refuses while the overlay holds foreign clusters/users; only `kux promote`
  passes `KUX_CLOBBER=1`, after merging them into the real config.
- `gc_sweep` must skip dot-dirs (in-progress inits) and the caller's own id; BSD `ps -p a,b`
  prints nothing if one pid is out of range (see `live_procs`).
- BSD tools: `sed -i ''`, `touch -t STAMP FILE` (options before operands), `stat -f`.

## 3.1 Where to test what

| Feature | Test file |
|---|---|
| alias derivation, name resolution | `test/aliases.bats` |
| init, shim, per-shell state, heal | `test/init.bats` |
| pin / toggle / projections | `test/ctx.bats` |
| namespaces + cache | `test/ns.bats` |
| fzf / `select` picker | `test/picker.bats` |
| prompt segment + markers | `test/prompt.bats` |
| status, unset, refresh, promote | `test/commands.bats` |
| sweep + exit hooks | `test/gc.bats` |

## 4. Glossary

| Term | Meaning |
|---|---|
| overlay | Per-shell kubeconfig fragment, first in `KUBECONFIG`; holds ctx + namespace |
| projection / cluster file | `~/.kube/clusters/<alias>.yaml`, one context extracted from the real config |
| pinned / unpinned | `KUBECONFIG` = overlay + projection / overlay + original list |
| alias | Short, filename-safe context name derived per DESIGN §5 |

## 5. Versioning

`KUX_VERSION` in `bin/kux` is the only version; releases are `vX.Y.Z` git tags.
