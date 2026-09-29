# shellcheck shell=bash
# Shared bats setup: an isolated HOME with a fixture kubeconfig and a kubectl wrapper that fakes
# the only API call kux makes (listing namespaces). Everything else goes to the real kubectl.

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
FIXTURES="$REPO_ROOT/test/fixtures"

kux_setup() {
	REAL_KUBECTL="$(command -v kubectl)"
	[ -n "$REAL_KUBECTL" ] || skip "kubectl not installed"
	export REAL_KUBECTL

	export HOME="$BATS_TEST_TMPDIR/home"
	export XDG_STATE_HOME="$HOME/.local/state"
	export XDG_CACHE_HOME="$HOME/.cache"
	mkdir -p "$HOME/.kube"
	cp "$FIXTURES/kubeconfig.yaml" "$HOME/.kube/config"
	chmod 600 "$HOME/.kube/config"
	unset KUBECONFIG KUX_ID KUX_PID KUX_STATE KUX_ORIG_KUBECONFIG KUX_CLUSTER_FILE
	export KUX_NO_FZF=1

	FAKEBIN="$BATS_TEST_TMPDIR/fakebin"
	mkdir -p "$FAKEBIN"
	export KUX_TEST_NAMESPACES="$BATS_TEST_TMPDIR/namespaces"
	export KUX_TEST_API_LOG="$BATS_TEST_TMPDIR/api.log"
	printf '%s\n' default kube-system payments >"$KUX_TEST_NAMESPACES"
	cat >"$FAKEBIN/kubectl" <<'SH'
#!/bin/bash
if [ "${1:-}" = get ] && { [ "${2:-}" = namespaces ] || [ "${2:-}" = ns ]; }; then
	echo "get namespaces ${KUBECONFIG:-}" >> "$KUX_TEST_API_LOG"
	sed 's|^|namespace/|' "$KUX_TEST_NAMESPACES"
	exit 0
fi
exec "$REAL_KUBECTL" "$@"
SH
	chmod +x "$FAKEBIN/kubectl"
	export PATH="$REPO_ROOT/bin:$FAKEBIN:$PATH"
}

# Run a script in a fresh zsh/bash that has loaded the kux shim.
#   in_shell zsh 'kux ctx staging; echo "$KUBECONFIG"'
in_shell() {
	local sh="$1"
	shift
	case "$sh" in
		zsh) zsh -f -c "eval \"\$(kux init zsh)\"; $*" ;;
		bash) /bin/bash --norc --noprofile -c "eval \"\$(kux init bash)\"; $*" ;;
	esac
}

# Minimal assertions (no bats-assert dependency).
assert_success() {
	# shellcheck disable=SC2154
	if [ "$status" -ne 0 ]; then
		printf 'expected success, got %s\noutput:\n%s\n' "$status" "$output" >&2
		return 1
	fi
}

assert_failure() {
	if [ "$status" -eq 0 ]; then
		printf 'expected failure\noutput:\n%s\n' "$output" >&2
		return 1
	fi
}

assert_output_contains() {
	case "$output" in
		*"$1"*) ;;
		*)
			printf 'expected output to contain: %s\noutput:\n%s\n' "$1" "$output" >&2
			return 1
			;;
	esac
}

assert_output_not_contains() {
	case "$output" in
		*"$1"*)
			printf 'expected output NOT to contain: %s\noutput:\n%s\n' "$1" "$output" >&2
			return 1
			;;
	esac
}

assert_equal() {
	if [ "$1" != "$2" ]; then
		printf 'expected: %s\n  actual: %s\n' "$2" "$1" >&2
		return 1
	fi
}
