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

See [docs/DESIGN.md](docs/DESIGN.md) for how it works.
