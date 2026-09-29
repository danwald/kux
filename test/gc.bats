#!/usr/bin/env bats

load helpers

setup() {
	kux_setup
	ROOT="$XDG_STATE_HOME/kux/shells"
	mkdir -p "$ROOT"
}

# fake_state ID META — a state dir as another shell would have left it.
fake_state() {
	mkdir -p "$ROOT/$1"
	printf '%s\n' "$2" >"$ROOT/$1/meta"
}

live_meta() {
	printf '%s\t%s' "$1" "$(LC_ALL=C ps -o lstart= -p "$1" | awk '{ $1 = $1; print }')"
}

@test "init sweeps dirs of dead shells and pid-reused shells, keeps live ones" {
	fake_state 99999999-1 "$(printf '99999999\tMon Jan  1 00:00:00 2001')"
	fake_state "$$-2" "$(printf '%s\tMon Jan  1 00:00:00 2001' "$$")"
	fake_state "$$-3" "$(live_meta $$)"
	sleep 0 &
	local dead=$!
	wait
	fake_state "$dead-6" "$(printf "%s\tMon Jan  1 00:00:00 2001" "$dead")"
	fake_state 12345-nometa ""
	mkdir -p "$ROOT/.4-5.tmp"
	run in_shell zsh 'true'
	assert_success
	[ ! -d "$ROOT/99999999-1" ]
	[ ! -d "$ROOT/$$-2" ]
	[ -d "$ROOT/$$-3" ]
	[ ! -d "$ROOT/$dead-6" ]
	[ ! -d "$ROOT/12345-nometa" ]
	[ -d "$ROOT/.4-5.tmp" ]
}

@test "kux gc keeps the current shell and reports a count" {
	fake_state 99999999-1 "$(printf '99999999\tx')"
	run in_shell zsh 'mkdir -p "$(dirname "$KUX_STATE")/99999998-1"; kux gc; [[ -f "$KUX_STATE/overlay.yaml" ]] && echo kept'
	assert_success
	assert_output_contains "removed 1 stale shell state dir(s)"
	assert_output_contains "kept"
}

@test "zsh: exiting the shell removes its state dir" {
	run in_shell zsh 'print -r -- "$KUX_STATE"; true'
	assert_success
	[ -n "$output" ]
	[ ! -d "$output" ]
}

@test "bash: exiting the shell removes its state dir" {
	run in_shell bash 'echo "$KUX_STATE"; true'
	assert_success
	[ -n "$output" ]
	[ ! -d "$output" ]
}

@test "bash: an existing EXIT trap is left alone" {
	run /bin/bash --norc --noprofile -c 'trap "echo mytrap" EXIT; eval "$(kux init bash)"; echo "$KUX_STATE"; true'
	assert_success
	assert_output_contains "mytrap"
	local lines_=($output)
	[ -d "${lines_[0]}" ]
}

@test "a subshell exiting does not remove the parent's state" {
	run in_shell bash '(exit 0); zsh -f -c "exit 0"; [[ -d "$KUX_STATE" ]] && echo alive; true'
	assert_output_contains "alive"
}

@test "a nested shell that inherits KUX_ID leaves the parent's state on exit" {
	run in_shell zsh 'p="$KUX_STATE"; zsh -f -c "eval \"\$(kux init zsh)\"; true"; [[ -d "$p" ]] && echo alive; true'
	assert_output_contains "alive"
}
