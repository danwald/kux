#!/usr/bin/env bats

load helpers

setup() {
	kux_setup
}

@test "zsh: RPROMPT shows alias and namespace" {
	run in_shell zsh '_kux_precmd; print -r -- "$RPROMPT"; kux ctx staging 2>/dev/null; kux ns web 2>/dev/null; _kux_precmd; print -r -- "$RPROMPT"'
	assert_success
	local lines_=($output)
	assert_equal "${lines_[0]} ${lines_[1]}" "☸ kind-kind:kube-system"
	assert_equal "${lines_[2]} ${lines_[3]}" "☸ staging:web"
}

@test "zsh: unset namespace renders as default" {
	run in_shell zsh 'kux ctx dev 2>/dev/null; _kux_precmd; print -r -- "$RPROMPT"'
	assert_equal "$output" "☸ dev:default"
}

@test "zsh: an existing RPROMPT is kept after the kux segment" {
	run zsh -f -c 'RPROMPT="%T"; eval "$(kux init zsh)"; _kux_precmd; _kux_precmd; print -r -- "$RPROMPT"'
	assert_equal "$output" "☸ kind-kind:kube-system %T"
}

@test "zsh: --no-prompt leaves RPROMPT alone but exposes kux_prompt" {
	run zsh -f -c 'eval "$(kux init zsh --no-prompt)"; _kux_precmd; print -r -- "[$RPROMPT]"; kux_prompt'
	assert_equal "$output" "[]
☸ kind-kind:kube-system"
}

@test "bash: PS1 is prefixed once, however often the hook runs or init re-runs" {
	run /bin/bash --norc --noprofile -c 'PS1="\$ "; eval "$(kux init bash)"; eval "$(kux init bash)"; _kux_precmd; _kux_precmd; printf "%s\n" "$PS1"; printf "%s\n" "$PROMPT_COMMAND" | grep -c _kux_precmd'
	assert_equal "$output" '[☸ kind-kind:kube-system] $ 
1'
}

@test "bash: existing PROMPT_COMMAND is preserved" {
	run /bin/bash --norc --noprofile -c 'PROMPT_COMMAND="echo hi;"; eval "$(kux init bash)"; eval "$PROMPT_COMMAND"'
	assert_success
	assert_output_contains "hi"
}

@test "steady state: the prompt hook runs no kux process" {
	cat >"$FAKEBIN/kux-logged" <<SH
#!/bin/bash
echo "\$*" >>"$BATS_TEST_TMPDIR/kux.calls"
exec "$REPO_ROOT/bin/kux" "\$@"
SH
	chmod +x "$FAKEBIN/kux-logged"
	run in_shell zsh '_kux_precmd; _KUX_BIN='"$FAKEBIN/kux-logged"'; _kux_precmd; _kux_precmd; print -r -- "$RPROMPT"'
	assert_output_contains "☸ kind-kind"
	[ ! -f "$BATS_TEST_TMPDIR/kux.calls" ]
}

@test "an external namespace change is picked up" {
	run in_shell zsh '_kux_precmd; sleep 1; kubectl config set-context --current --namespace=zz >/dev/null; _kux_precmd; print -r -- "$RPROMPT"'
	assert_equal "$output" "☸ kind-kind:zz"
}

@test "an external use-context is shown and the overlay stanza repaired" {
	cp "$HOME/.kube/config" "$BATS_TEST_TMPDIR/before"
	run in_shell zsh 'sleep 1; kubectl config use-context gke_myproj_us-central1-a_dev >/dev/null; _kux_precmd; print -r -- "$RPROMPT"; kubectl config set-context --current --namespace=q >/dev/null'
	assert_equal "$output" "☸ dev:default"
	cmp "$BATS_TEST_TMPDIR/before" "$HOME/.kube/config"
}

@test "missing overlay shows ☸ ? and the next kux command heals it" {
	run in_shell zsh 'rm -rf "$KUX_STATE"; _kux_precmd; print -r -- "$RPROMPT"; kux ns x 2>&1; _kux_precmd; print -r -- "$RPROMPT"'
	assert_output_contains "☸ ?"
	assert_output_contains "state for this shell was lost"
	assert_output_contains "☸ kind-kind:x"
}

@test "a lost pinned shell heals back to its cluster file" {
	run in_shell zsh 'kux ctx staging 2>/dev/null; rm -rf "$KUX_STATE"; kux ns y 2>&1; kubectl config current-context'
	assert_output_contains "restored context arn:aws:eks:us-east-1:111111111111:cluster/staging"
	assert_equal "$(printf '%s\n' "$output" | tail -1)" "arn:aws:eks:us-east-1:111111111111:cluster/staging"
}

@test "clusters written into the overlay show !promote and block kux rewrites" {
	run in_shell zsh 'sleep 1; kubectl config set-cluster newc --server=https://new.example >/dev/null; _kux_precmd; print -r -- "$RPROMPT"; kux ns z'
	assert_output_contains "☸ kind-kind:kube-system !promote"
	assert_output_contains "run 'kux promote' first"
}

@test "!stale when the real config is newer than the cluster file" {
	run in_shell zsh 'kux ctx staging 2>/dev/null; _kux_precmd; print -r -- "$RPROMPT"; touch -t 203001010000 "$HOME/.kube/config"; _kux_precmd; print -r -- "$RPROMPT"'
	local lines_=($output)
	assert_equal "${lines_[2]}" "☸"
	assert_equal "${lines_[3]} ${lines_[4]}" "staging:default !stale"
	assert_equal "${#lines_[@]}" 5
}

@test "!edited when KUBECONFIG is changed by hand" {
	run in_shell bash 'export KUBECONFIG="$HOME/.kube/config"; _kux_precmd; printf "%s\n" "$PS1"'
	assert_output_contains "!edited"
}

@test "prompt text is inert: shell metacharacters in names are neutralised" {
	cat >"$HOME/.kube/config" <<'YAML'
apiVersion: v1
kind: Config
current-context: 'a$(touch pwned)%b'
contexts:
- name: 'a$(touch pwned)%b'
  context: {cluster: x, user: x}
YAML
	run /bin/bash --norc --noprofile -c 'cd "$BATS_TEST_TMPDIR"; eval "$(kux init bash)"; _kux_precmd; printf "%s\n" "$PS1"'
	assert_output_contains "a_(touch pwned)_b"
	[ ! -f "$BATS_TEST_TMPDIR/pwned" ]
}
