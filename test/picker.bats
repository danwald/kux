#!/usr/bin/env bats

load helpers

setup() {
	kux_setup
	export KUX_FORCE_TTY=1
}

fake_fzf() {
	cat >"$FAKEBIN/fzf" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$KUX_TEST_FZF_ARGS"
grep -m1 "$KUX_TEST_FZF_PICK"
SH
	chmod +x "$FAKEBIN/fzf"
	unset KUX_NO_FZF
	export KUX_TEST_FZF_ARGS="$BATS_TEST_TMPDIR/fzf.args"
}

@test "select fallback: ctx picker switches to the chosen number" {
	export KUX_TTY="$BATS_TEST_TMPDIR/tty"
	n="$(KUX_FORCE_TTY= kux ctx | grep -n '^staging$' | cut -d: -f1)"
	echo "$n" >"$KUX_TTY"
	run in_shell zsh 'kux ctx 2>/dev/null; kubectl config current-context'
	assert_success
	assert_output_contains "cluster/staging"
}

@test "select fallback: ns picker sets the chosen namespace" {
	export KUX_TTY="$BATS_TEST_TMPDIR/tty"
	echo 3 >"$KUX_TTY"
	run in_shell bash 'kux ns 2>/dev/null; kubectl config view --minify -o jsonpath="{..namespace}"'
	assert_equal "$output" "payments"
}

@test "fzf: ctx picker shows alias and real name, switches on the pick" {
	fake_fzf
	export KUX_TEST_FZF_PICK='^dev	'
	run in_shell zsh 'kux ctx 2>/dev/null; kubectl config current-context'
	assert_output_contains "gke_myproj_us-central1-a_dev"
	grep -q -- '--with-nth=1,2' "$KUX_TEST_FZF_ARGS"
}

@test "fzf: ns picker binds ctrl-r to a cache refresh" {
	fake_fzf
	export KUX_TEST_FZF_PICK='^default$'
	run in_shell zsh 'kux ns 2>/dev/null; kubectl config view --minify -o jsonpath="{..namespace}"'
	assert_equal "$output" "default"
	grep -q -- 'ctrl-r:reload(.*_nslist --refresh)' "$KUX_TEST_FZF_ARGS"
}

@test "cancelled picker changes nothing" {
	fake_fzf
	export KUX_TEST_FZF_PICK='^no-such-line$'
	run in_shell zsh 'k=$KUBECONFIG; kux ctx; [[ $k == $KUBECONFIG ]] && echo UNCHANGED'
	assert_output_contains "UNCHANGED"
}

@test "piped output never opens a picker" {
	unset KUX_FORCE_TTY
	fake_fzf
	run kux ctx
	assert_success
	[ ! -f "$KUX_TEST_FZF_ARGS" ]
}
