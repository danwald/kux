#!/usr/bin/env bats

load helpers

setup() {
	kux_setup
}

@test "--version prints the version line" {
	run kux --version
	assert_success
	assert_equal "$output" "kux $(sed -n 's/^KUX_VERSION="\(.*\)"$/\1/p' "$REPO_ROOT/bin/kux")"
}

@test "help lists the commands" {
	run kux help
	assert_success
	assert_output_contains "kux ctx"
	assert_output_contains "kux init zsh|bash"
}

@test "unknown command fails with a message" {
	run kux frobnicate
	assert_failure
	assert_output_contains "unknown command: frobnicate"
}

@test "runs under macOS bash 3.2" {
	head -1 "$REPO_ROOT/bin/kux" | grep -qx '#!/bin/bash'
}
