#!/usr/bin/env bats

load helpers

setup() {
	kux_setup
}

@test "bare kux without the shim reports it and the kubectl context" {
	run kux
	assert_success
	assert_output_contains "shell integration not loaded (context: kind-kind)"
}

@test "bare kux in a shell shows context, namespace and mode" {
	run in_shell zsh 'kux; kux ctx staging 2>/dev/null; kux ns web 2>/dev/null; kux'
	assert_success
	assert_output_contains "mode:      unpinned"
	assert_output_contains "context:   staging (arn:aws:eks:us-east-1:111111111111:cluster/staging)"
	assert_output_contains "namespace: web"
	assert_output_contains "mode:      pinned ($HOME/.kube/clusters/staging.yaml)"
	assert_output_not_contains "warning:"
}

@test "status --json is valid JSON with the pinned state" {
	command -v python3 >/dev/null || skip "python3 needed to parse JSON"
	run in_shell zsh 'kux ctx staging 2>/dev/null; kux status --json'
	assert_success
	printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["shell"] and d["pinned"], d
assert d["alias"] == "staging" and d["namespace"] == "default", d
assert d["markers"] == [], d
'
}

@test "status --json without the shim" {
	run kux status --json
	assert_equal "$output" '{"shell":false,"context":"kind-kind"}'
}

@test "status lists warnings for stale and edited" {
	run in_shell zsh 'kux ctx staging 2>/dev/null; touch -t 203001010000 "$HOME/.kube/config"; export KUBECONFIG=x; kux status --json'
	assert_output_contains '"markers":["!stale","!edited"]'
}

@test "kux unset returns to the unpinned state and ctx - goes back" {
	run in_shell zsh 'kux ctx staging 2>/dev/null; kux unset 2>/dev/null; print -r -- "$KUBECONFIG"; print -r -- "${KUX_CLUSTER_FILE-none}"; kubectl config current-context; kux ctx - 2>/dev/null; kubectl config current-context'
	assert_success
	local lines_=($output)
	assert_equal "${lines_[0]}" "$HOME/.local/state/kux/shells/${lines_[0]#"$HOME/.local/state/kux/shells/"}"
	case "${lines_[0]}" in *"/overlay.yaml:$HOME/.kube/config") ;; *) false ;; esac
	assert_equal "${lines_[1]}" "none"
	assert_equal "${lines_[2]}" "kind-kind"
	assert_equal "${lines_[3]}" "arn:aws:eks:us-east-1:111111111111:cluster/staging"
}

@test "kux refresh regenerates the cluster file, clears !stale, keeps the namespace" {
	run in_shell zsh 'kux ctx staging 2>/dev/null; kux ns web 2>/dev/null
		sed -i "" "s|https://staging.example:6443|https://staging3.example:6443|" "$HOME/.kube/config"
		touch -t 203001010000 "$HOME/.kube/config"; touch -t 202001010000 "$KUX_CLUSTER_FILE"
		_kux_precmd; print -r -- "$RPROMPT"; kux refresh 2>/dev/null; touch -t 202101010000 "$HOME/.kube/config"
		_kux_precmd; print -r -- "$RPROMPT"'
	assert_output_contains "☸ staging:web !stale"
	assert_equal "$(printf '%s\n' "$output" | tail -1)" "☸ staging:web"
	grep -q staging3.example "$HOME/.kube/clusters/staging.yaml"
}

@test "kux refresh after the context is removed from the real config fails clearly" {
	run in_shell zsh 'kux ctx dev 2>/dev/null; KUBECONFIG="$HOME/.kube/config" kubectl config delete-context gke_myproj_us-central1-a_dev >/dev/null; kux refresh'
	assert_failure
	assert_output_contains "no longer in"
}

@test "kux refresh when unpinned clears the namespace cache" {
	run in_shell zsh 'kux ns >/dev/null; kux refresh 2>/dev/null; kux ns >/dev/null'
	assert_equal "$(wc -l <"$KUX_TEST_API_LOG" | tr -d ' ')" 2
}

@test "kux promote with nothing foreign is a no-op" {
	cp "$HOME/.kube/config" "$BATS_TEST_TMPDIR/before"
	run in_shell zsh 'kux promote'
	assert_success
	assert_output_contains "nothing to promote"
	cmp "$BATS_TEST_TMPDIR/before" "$HOME/.kube/config"
}

@test "kux promote moves a cloud-CLI-style write into the real config (unpinned)" {
	run in_shell zsh 'kubectl config set-cluster newc --server=https://new.example >/dev/null
		kubectl config set-credentials newu --token=T >/dev/null
		kubectl config set-context newctx --cluster=newc --user=newu >/dev/null
		kubectl config use-context newctx >/dev/null
		kux promote; sleep 1; _kux_precmd; print -r -- "$RPROMPT"; kubectl config current-context'
	assert_success
	assert_output_contains "promoted into $HOME/.kube/config"
	assert_output_contains "☸ newctx:default"
	assert_output_not_contains "!promote"
	KUBECONFIG="$HOME/.kube/config" run kubectl config get-contexts -o name
	assert_output_contains "newctx"
	assert_output_contains "kind-kind"
	[ -f "$HOME/.kube/config.kux-bak" ]
	cmp "$HOME/.kube/config.kux-bak" "$FIXTURES/kubeconfig.yaml"
}

@test "kux promote while pinned keeps the shell on its cluster" {
	run in_shell zsh 'kux ctx staging 2>/dev/null
		kubectl config set-cluster newc --server=https://new.example >/dev/null
		kubectl config set-credentials newu --token=T >/dev/null
		kubectl config set-context newctx --cluster=newc --user=newu >/dev/null
		kubectl config use-context newctx >/dev/null
		kux promote >/dev/null; kubectl config current-context; kubectl config get-contexts -o name | wc -l | tr -d " "'
	assert_success
	local lines_=($output)
	assert_equal "${lines_[0]}" "arn:aws:eks:us-east-1:111111111111:cluster/staging"
	assert_equal "${lines_[1]}" "1"
	KUBECONFIG="$HOME/.kube/config" run kubectl config get-contexts -o name
	assert_output_contains "newctx"
}
