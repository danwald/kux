#!/usr/bin/env bats

load helpers

setup() {
	kux_setup
}

api_calls() {
	if [ -f "$KUX_TEST_API_LOG" ]; then wc -l <"$KUX_TEST_API_LOG" | tr -d ' '; else echo 0; fi
}

@test "kux ns piped lists namespaces, then serves them from cache" {
	run in_shell zsh 'kux ns; kux ns'
	assert_success
	assert_output_contains "kube-system"
	assert_output_not_contains "namespace/"
	assert_equal "$(api_calls)" 1
}

@test "kux ns --refresh bypasses the cache" {
	run in_shell zsh 'kux ns >/dev/null; kux ns --refresh >/dev/null'
	assert_equal "$(api_calls)" 2
}

@test "the cache is per context" {
	run in_shell zsh 'kux ns >/dev/null; kux ctx staging 2>/dev/null; kux ns >/dev/null'
	assert_equal "$(api_calls)" 2
}

@test "unreachable cluster falls back to a stale cache with a warning" {
	run in_shell zsh 'kux ns >/dev/null'
	export KUX_TEST_NS_FAIL=1 KUX_NS_TTL=0
	run in_shell zsh 'kux ns'
	assert_success
	assert_output_contains "showing cached namespaces"
	assert_output_contains "payments"
}

@test "unreachable cluster with no cache fails" {
	export KUX_TEST_NS_FAIL=1
	run in_shell zsh 'kux ns'
	assert_failure
	assert_output_contains "cannot list namespaces"
}

@test "kux ns <name> sets this shell's namespace only" {
	cp "$HOME/.kube/config" "$BATS_TEST_TMPDIR/before"
	run in_shell zsh 'kux ns web 2>/dev/null; kubectl config view --minify -o jsonpath="{..namespace}"'
	assert_equal "$output" "web"
	cmp "$BATS_TEST_TMPDIR/before" "$HOME/.kube/config"
	run in_shell zsh 'kubectl config view --minify -o jsonpath="{..namespace}"'
	assert_equal "$output" "kube-system"
}

@test "kux ns works when pinned (bash)" {
	run in_shell bash 'kux ctx staging 2>/dev/null; kux ns api 2>/dev/null; kubectl config view --minify -o jsonpath="{..namespace}"'
	assert_equal "$output" "api"
}

@test "kux ns - toggles per context" {
	run in_shell zsh 'kux ctx staging 2>/dev/null; kux ns a 2>/dev/null; kux ns b 2>/dev/null
		kux ctx dev 2>/dev/null; kux ns c 2>/dev/null; kux ns d 2>/dev/null
		kux ctx staging 2>/dev/null; kux ns - 2>/dev/null; kubectl config view --minify -o jsonpath="{..namespace}"; echo
		kux ctx dev 2>/dev/null; kux ns - 2>/dev/null; kubectl config view --minify -o jsonpath="{..namespace}"'
	local lines_=($output)
	assert_equal "${lines_[0]}" "a"
	assert_equal "${lines_[1]}" "c"
}

@test "kux ns - without history fails" {
	run in_shell zsh 'kux ns -'
	assert_failure
	assert_output_contains "no previous namespace"
}

@test "kux ns after an external use-context repairs the overlay stanza" {
	cp "$HOME/.kube/config" "$BATS_TEST_TMPDIR/before"
	run in_shell zsh 'kubectl config use-context gke_myproj_us-central1-a_dev >/dev/null; kux ns x 2>/dev/null; kubectl config view --minify -o jsonpath="{.contexts[0].context.cluster} {..namespace}"'
	assert_equal "$output" "gke_myproj_us-central1-a_dev x"
	cmp "$BATS_TEST_TMPDIR/before" "$HOME/.kube/config"
}

@test "kux ns <name> without the shim fails" {
	run kux ns web
	assert_failure
	assert_output_contains "shell integration not loaded"
}
