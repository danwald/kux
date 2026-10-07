#!/usr/bin/env bats

load helpers

setup() {
	kux_setup
}

@test "EKS and GKE names shorten; colliding EKS names get the account id" {
	run kux _aliases
	assert_success
	assert_output_contains "prod@111111111111	arn:aws:eks:us-east-1:111111111111:cluster/prod"
	assert_output_contains "prod@222222222222	arn:aws:eks:eu-west-1:222222222222:cluster/prod"
	assert_output_contains "staging	arn:aws:eks:us-east-1:111111111111:cluster/staging"
	assert_output_contains "dev	gke_myproj_us-central1-a_dev"
	assert_output_contains "kind-kind	kind-kind"
}

@test "same account and name in two regions falls back to the sanitised full name" {
	cat >"$HOME/.kube/config" <<'YAML'
apiVersion: v1
kind: Config
contexts:
- name: arn:aws:eks:us-east-1:111111111111:cluster/prod
  context: {cluster: a, user: a}
- name: arn:aws:eks:eu-west-1:111111111111:cluster/prod
  context: {cluster: b, user: b}
YAML
	run kux _aliases
	assert_success
	assert_output_contains "arn_aws_eks_us-east-1_111111111111_cluster_prod	"
	assert_output_contains "arn_aws_eks_eu-west-1_111111111111_cluster_prod	"
}

@test "other names are made filename-safe" {
	cat >"$HOME/.kube/config" <<'YAML'
apiVersion: v1
kind: Config
contexts:
- name: team/ops:blue
  context: {cluster: a, user: a}
YAML
	run kux _aliases
	assert_equal "$output" "team_ops_blue	team/ops:blue"
}

@test "kux ctx piped lists one alias per line" {
	run kux ctx
	assert_success
	assert_equal "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" 5
	assert_output_contains "staging"
	assert_output_not_contains "arn:aws"
}

@test "resolve: exact real name, exact alias, unique substring" {
	run kux _resolve arn:aws:eks:us-east-1:111111111111:cluster/staging
	assert_equal "$output" "staging	arn:aws:eks:us-east-1:111111111111:cluster/staging"
	run kux _resolve dev
	assert_equal "$output" "dev	gke_myproj_us-central1-a_dev"
	run kux _resolve stag
	assert_equal "$output" "staging	arn:aws:eks:us-east-1:111111111111:cluster/staging"
}

@test "resolve: ambiguous substring errors and lists candidates" {
	run kux _resolve prod
	assert_failure
	assert_output_contains "ambiguous"
	assert_output_contains "prod@111111111111"
	assert_output_contains "prod@222222222222"
}

@test "resolve: no match errors" {
	run kux _resolve nope
	assert_failure
	assert_output_contains "no context matches 'nope'"
}

@test "enumeration ignores a per-shell KUBECONFIG and uses the original" {
	printf 'apiVersion: v1\nkind: Config\ncontexts:\n- name: only\n  context: {cluster: x, user: x}\n' >"$BATS_TEST_TMPDIR/one.yaml"
	KUBECONFIG="$BATS_TEST_TMPDIR/one.yaml" KUX_ORIG_KUBECONFIG="$HOME/.kube/config" run kux ctx
	assert_output_contains "staging"
	assert_output_not_contains "only"
}
