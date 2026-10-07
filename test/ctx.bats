#!/usr/bin/env bats

load helpers

setup() {
	kux_setup
	CLUSTERS="$HOME/.kube/clusters"
}

@test "kux ctx <name> without the shim fails" {
	run kux ctx staging
	assert_failure
	assert_output_contains "shell integration not loaded"
}

@test "pinning replaces KUBECONFIG with overlay + a single-context projection" {
	run in_shell zsh 'kux ctx staging 2>/dev/null; print -r -- "$KUBECONFIG"; print -r -- "$KUX_CLUSTER_FILE"; kubectl config get-contexts -o name'
	assert_success
	assert_output_contains "/overlay.yaml:$CLUSTERS/staging.yaml"
	assert_equal "$(printf '%s\n' "$output" | tail -1)" "arn:aws:eks:us-east-1:111111111111:cluster/staging"
	assert_output_not_contains "kind-kind"
}

@test "a pinned shell cannot reach other contexts" {
	run in_shell zsh 'kux ctx staging 2>/dev/null; kubectl config use-context kind-kind'
	assert_failure
	assert_output_contains 'no context exists with the name: "kind-kind"'
}

@test "projection is 0600, keeps the exec block, and the real config is untouched" {
	cp "$HOME/.kube/config" "$BATS_TEST_TMPDIR/before"
	run in_shell bash 'kux ctx staging 2>/dev/null'
	assert_success
	assert_equal "$(stat -f %Lp "$CLUSTERS/staging.yaml")" "600"
	grep -q 'get-token' "$CLUSTERS/staging.yaml"
	cmp "$BATS_TEST_TMPDIR/before" "$HOME/.kube/config"
}

@test "the context's namespace from the real config is the starting namespace" {
	run in_shell zsh 'kux ctx prod@111111111111 2>/dev/null; kubectl config view --minify -o jsonpath="{..namespace}"'
	assert_output_contains "payments"
}

@test "kux ctx - toggles back to the previous context" {
	run in_shell zsh 'kux ctx staging 2>/dev/null; kux ctx dev 2>/dev/null; kux ctx - 2>/dev/null; kubectl config current-context; kux ctx - 2>/dev/null; kubectl config current-context'
	assert_success
	local lines_=($output)
	assert_equal "${lines_[0]}" "arn:aws:eks:us-east-1:111111111111:cluster/staging"
	assert_equal "${lines_[1]}" "gke_myproj_us-central1-a_dev"
}

@test "kux ctx - with no history fails" {
	run in_shell zsh 'kux ctx -'
	assert_failure
	assert_output_contains "no previous context"
}

@test "an ambiguous name does not switch" {
	run in_shell zsh 'kux ctx prod; print -r -- "KC=$KUBECONFIG"'
	assert_output_contains "ambiguous"
	assert_output_contains "overlay.yaml:$HOME/.kube/config"
}

@test "a stale projection is regenerated on switch" {
	run in_shell zsh 'kux ctx staging 2>/dev/null'
	touch -t 202001010000 "$CLUSTERS/staging.yaml"
	sed -i '' 's|https://staging.example:6443|https://staging2.example:6443|' "$HOME/.kube/config"
	run in_shell zsh 'kux ctx staging 2>/dev/null'
	grep -q 'staging2.example' "$CLUSTERS/staging.yaml"
}

@test "a projection holding a different context is regenerated" {
	mkdir -p "$CLUSTERS"
	KUBECONFIG="$HOME/.kube/config" kubectl config view --raw --minify --flatten --context=kind-kind >"$CLUSTERS/staging.yaml"
	run in_shell zsh 'kux ctx staging 2>/dev/null; kubectl config current-context'
	assert_output_contains "cluster/staging"
}

@test "switching back to a context restores the namespace it had in this shell" {
	run in_shell zsh 'kux ctx staging 2>/dev/null; kubectl config set-context --current --namespace=web >/dev/null; kux ctx dev 2>/dev/null; kux ctx staging 2>/dev/null; kubectl config view --minify -o jsonpath="{..namespace}"'
	assert_output_contains "web"
}
