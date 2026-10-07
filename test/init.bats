#!/usr/bin/env bats

load helpers

setup() {
	kux_setup
}

@test "init rejects unknown shells" {
	run kux init fish
	assert_failure
	assert_output_contains "usage: kux init zsh|bash"
}

@test "commands that change state need the shim" {
	run kux _require_shell
	assert_failure
}

@test "zsh: new shell is unpinned: overlay first, then the original config" {
	run in_shell zsh 'print -r -- "$KUBECONFIG"; kubectl config current-context; kubectl config view --minify -o jsonpath="{..namespace}"'
	assert_success
	assert_output_contains "/kux/shells/"
	assert_output_contains "/overlay.yaml:$HOME/.kube/config"
	assert_output_contains "kind-kind"
	assert_output_contains "kube-system"
}

@test "bash: new shell is unpinned the same way" {
	run in_shell bash 'echo "$KUBECONFIG"; kubectl config current-context'
	assert_success
	assert_output_contains "/overlay.yaml:$HOME/.kube/config"
	assert_output_contains "kind-kind"
}

@test "state dir holds a 0600 overlay and the owning pid" {
	run in_shell zsh 'print -r -- "$$"; cut -f1 "$KUX_STATE/meta"; stat -f %Lp "$KUX_STATE/overlay.yaml"'
	assert_success
	local lines_=($output)
	assert_equal "${lines_[0]}" "${lines_[1]}"
	assert_equal "${lines_[2]}" "600"
}

@test "kubectl writes in a kux shell never touch the real config" {
	cp "$HOME/.kube/config" "$BATS_TEST_TMPDIR/before"
	run in_shell zsh 'kubectl config set-context --current --namespace=scratch >/dev/null; kubectl config use-context gke_myproj_us-central1-a_dev >/dev/null; kubectl config current-context'
	assert_success
	assert_output_contains "gke_myproj_us-central1-a_dev"
	cmp "$BATS_TEST_TMPDIR/before" "$HOME/.kube/config"
}

@test "two shells are isolated from each other" {
	run in_shell zsh 'kubectl config use-context gke_myproj_us-central1-a_dev >/dev/null; print -r -- "$KUX_ID"'
	local first="$output"
	run in_shell zsh 'kubectl config current-context; print -r -- "$KUX_ID"'
	assert_output_contains "kind-kind"
	assert_output_not_contains "$first"
}

@test "re-running init in the same shell is idempotent" {
	run in_shell zsh 'a=$KUX_ID; k=$KUBECONFIG; eval "$(kux init zsh)"; [[ $a == $KUX_ID && $k == $KUBECONFIG ]] && echo SAME'
	assert_output_contains "SAME"
	run in_shell bash 'a=$KUX_ID; k=$KUBECONFIG; eval "$(kux init bash)"; [[ $a == $KUX_ID && $k == $KUBECONFIG ]] && echo SAME'
	assert_output_contains "SAME"
}

@test "a nested shell mints its own id from the original KUBECONFIG" {
	run in_shell zsh 'print -r -- "$KUX_ID"; zsh -f -c "eval \"\$(kux init zsh)\"; print -r -- \$KUX_ID; print -r -- \$KUBECONFIG"; true'
	assert_success
	local lines_=($output)
	[ "${lines_[0]}" != "${lines_[1]}" ]
	case "${lines_[2]}" in
		*"${lines_[1]}/overlay.yaml:$HOME/.kube/config") ;;
		*) false ;;
	esac
}

@test "an existing KUBECONFIG list is kept after the overlay" {
	cp "$HOME/.kube/config" "$BATS_TEST_TMPDIR/b.yaml"
	export KUBECONFIG="$HOME/.kube/config:$BATS_TEST_TMPDIR/b.yaml"
	run in_shell zsh 'print -r -- "$KUX_ORIG_KUBECONFIG"; print -r -- "$KUBECONFIG"'
	assert_output_contains "$HOME/.kube/config:$BATS_TEST_TMPDIR/b.yaml"
	assert_output_contains "overlay.yaml:$HOME/.kube/config:$BATS_TEST_TMPDIR/b.yaml"
}

@test "an empty kubeconfig still initialises" {
	: >"$HOME/.kube/config"
	run in_shell zsh 'print -r -- "$KUX_ID"'
	assert_success
	[ -n "$output" ]
}
