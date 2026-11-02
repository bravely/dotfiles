#!/usr/bin/env bats
#
# Tests for dot_local/bin/executable_gh-repo-profile, which applies my standard
# GitHub settings profile to a repo. What matters is what it would send to GitHub,
# so the tests read the stubbed gh's record of writes and the ruleset body it was
# given. The stub answers reads from a healthy-world default; tests change one
# thing at a time with `stub gh route`.

bats_require_minimum_version 1.5.0
load harness

REPO=bravely/example

# Every call that would change something on GitHub.
writes() { stub gh calls | grep -E '^(repo edit|api .*-X (PUT|POST))' || true; }

# The ruleset JSON the script sent, and one jq query over it.
ruleset() { stub gh sent | jq -r "$1"; }
rule_types() { ruleset '[.rules[].type] | sort | join(" ")'; }

ALL_RULES="deletion non_fast_forward pull_request required_linear_history required_signatures required_status_checks"

@test "--help prints usage and exits 0, even without gh or jq" {
  hide gh jq
  run gh-repo-profile --help
  [ "$status" -eq 0 ]
  [[ $output == "Usage: gh-repo-profile [options] OWNER/REPO"* ]] || false
}

@test "no repo prints usage on stderr and exits 1" {
  run --separate-stderr gh-repo-profile
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ $stderr == "Usage: gh-repo-profile"* ]] || false
  [ -z "$(stub gh calls)" ]
}

@test "an unknown option exits 1 and names it" {
  run gh-repo-profile --frobnicate "$REPO"
  [ "$status" -eq 1 ]
  [[ $output == *"unknown option: --frobnicate"* ]] || false
  [ -z "$(stub gh calls)" ]
}

@test "a second repo exits 1" {
  run gh-repo-profile bravely/one bravely/two
  [ "$status" -eq 1 ]
  [[ $output == *"more than one repo given"* ]] || false
}

@test "--ci-check without a name exits 1" {
  run gh-repo-profile "$REPO" --ci-check
  [ "$status" -eq 1 ]
  [[ $output == *"--ci-check needs a check name"* ]] || false
}

@test "--ci-check= with an empty name exits 1" {
  run gh-repo-profile --ci-check= "$REPO"
  [ "$status" -eq 1 ]
  [[ $output == *"needs a non-empty name"* ]] || false
}

@test "a name that is not OWNER/REPO exits 1 before touching GitHub" {
  for bad in example bravely/example/extra; do
    run gh-repo-profile "$bad"
    [ "$status" -eq 1 ]
    [[ $output == *"expected OWNER/REPO"* ]] || false
  done
  [ -z "$(stub gh calls)" ]
}

@test "OWNER/REPO, an https URL, an ssh address, a trailing slash and .git all name the same repo" {
  for form in "$REPO" "https://github.com/$REPO" "https://github.com/$REPO/" "https://github.com/$REPO.git" "git@github.com:$REPO.git"; do
    run gh-repo-profile --dry-run "$form"
    [ "$status" -eq 0 ]
    [[ $output == *"applying the profile to $REPO "* ]] || false
  done
  [ "$(stub gh calls | grep -c "^api repos/$REPO$")" -eq 5 ]
}

@test "refuses when gh is not installed" {
  hide gh
  run gh-repo-profile "$REPO"
  [ "$status" -eq 1 ]
  [[ $output == *"gh is not installed"* ]] || false
}

@test "refuses when jq is not installed" {
  hide jq
  run gh-repo-profile "$REPO"
  [ "$status" -eq 1 ]
  [[ $output == *"jq is not installed"* ]] || false
}

@test "refuses when gh is not logged in" {
  stub gh logged-out
  run gh-repo-profile "$REPO"
  [ "$status" -eq 1 ]
  [[ $output == *"gh is not authenticated"* ]] || false
  [ -z "$(writes)" ]
}

@test "refuses a repo it cannot read" {
  stub gh route-fails repo
  run gh-repo-profile "$REPO"
  [ "$status" -eq 1 ]
  [[ $output == *"cannot read $REPO"* ]] || false
  [ -z "$(writes)" ]
}

@test "refuses a repo it has no admin on, and changes nothing" {
  stub gh route repo <<<'{"default_branch": "main", "permissions": {"admin": false}}'
  run gh-repo-profile "$REPO"
  [ "$status" -eq 1 ]
  [[ $output == *"you need admin on $REPO"* ]] || false
  [ -z "$(writes)" ]
}

@test "sets squash-only merging, auto-merge and update-branch, no wiki, delete on merge" {
  run gh-repo-profile "$REPO"
  [ "$status" -eq 0 ]
  [ "$(writes | head -1)" = "repo edit $REPO --enable-wiki=false --enable-merge-commit=false --enable-rebase-merge=false --enable-squash-merge --enable-auto-merge --allow-update-branch --delete-branch-on-merge" ]
}

@test "turns on Dependabot vulnerability alerts" {
  run gh-repo-profile "$REPO"
  [[ $(writes) == *"api --silent -X PUT repos/$REPO/vulnerability-alerts"* ]] || false
}

@test "a failure to enable alerts warns and carries on to the ruleset" {
  stub gh fail "api --silent -X PUT repos/$REPO/vulnerability-alerts" 1 'HTTP 403'
  run gh-repo-profile "$REPO"
  [ "$status" -eq 0 ]
  [[ $output == *"could not enable Dependabot vulnerability alerts"* ]] || false
  [[ $(writes) == *"-X POST repos/$REPO/rulesets"* ]] || false
}

@test "a failed repo edit exits 1 and goes no further" {
  stub gh fail 'repo edit' 1 'HTTP 403'
  run gh-repo-profile "$REPO"
  [ "$status" -eq 1 ]
  [[ $output == *"gh repo edit failed"* ]] || false
  [ "$(writes | wc -l | tr -d ' ')" -eq 1 ]
}

@test "creates the Safe Main ruleset when the repo has none" {
  run gh-repo-profile "$REPO"
  [ "$status" -eq 0 ]
  [[ $output == *"creating the ruleset"* ]] || false
  [[ $(writes) == *"api --silent -X POST repos/$REPO/rulesets --input -"* ]] || false
  [ "$(ruleset .name)" = "Safe Main" ]
}

@test "updates the ruleset in place when Safe Main already exists" {
  stub gh route rulesets <<<'[{"id": 7, "name": "Other"}, {"id": 42, "name": "Safe Main"}]'
  run gh-repo-profile "$REPO"
  [ "$status" -eq 0 ]
  [[ $output == *"updating the existing ruleset (#42)"* ]] || false
  [[ $(writes) == *"api --silent -X PUT repos/$REPO/rulesets/42 --input -"* ]] || false
  [[ $(writes) != *"-X POST"* ]] || false
}

@test "the ruleset guards the default branch and lets nobody bypass it" {
  run gh-repo-profile "$REPO"
  [ "$(ruleset .enforcement)" = active ]
  [ "$(ruleset '.conditions.ref_name.include | join(",")')" = "~DEFAULT_BRANCH" ]
  [ "$(ruleset '.bypass_actors | length')" -eq 0 ]
}

@test "the ruleset blocks deletion and force-push, and requires linear history, signatures and a PR" {
  run gh-repo-profile "$REPO"
  [ "$(rule_types)" = "$ALL_RULES" ]
}

@test "the ruleset's pull request rule needs no approvals and allows only squash" {
  run gh-repo-profile "$REPO"
  [ "$(ruleset '.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count')" -eq 0 ]
  [ "$(ruleset '.rules[] | select(.type == "pull_request") | .parameters.allowed_merge_methods | join(",")')" = squash ]
}

@test "the ruleset requires the ci check by default" {
  run gh-repo-profile "$REPO"
  [ "$(ruleset '.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[0].context')" = ci ]
}

@test "--ci-check NAME requires NAME instead, with a space or an equals sign" {
  stub gh route contents/.github/workflows/ci.yml <<<$'jobs:\n  build:\n    runs-on: macos-latest'
  for flag in "--ci-check build" "--ci-check=build"; do
    # shellcheck disable=SC2086
    run gh-repo-profile $flag "$REPO"
    [ "$status" -eq 0 ]
    [ "$(ruleset '.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[0].context')" = build ]
  done
}

@test "--no-status-check drops only the status check rule, and does not look at the repo's workflows" {
  run gh-repo-profile --no-status-check "$REPO"
  [ "$status" -eq 0 ]
  [ "$(rule_types)" = "deletion non_fast_forward pull_request required_linear_history required_signatures" ]
  [[ $(stub gh calls) != *contents* ]] || false
}

@test "--no-signatures drops only the signed-commits rule" {
  run gh-repo-profile --no-signatures "$REPO"
  [ "$status" -eq 0 ]
  [ "$(rule_types)" = "deletion non_fast_forward pull_request required_linear_history required_status_checks" ]
}

@test "a failed ruleset write exits 1" {
  stub gh fail "api --silent -X POST repos/$REPO/rulesets" 1 'HTTP 422'
  run gh-repo-profile "$REPO"
  [ "$status" -eq 1 ]
  [[ $output == *'failed to apply the "Safe Main" ruleset'* ]] || false
}

@test "the default branch comes from the repo, not an assumption" {
  stub gh route repo <<<'{"default_branch": "trunk", "permissions": {"admin": true}}'
  run gh-repo-profile "$REPO"
  [[ $output == *"(default branch: trunk)"* ]] || false
  [[ $output == *"trunk now requires signed commits"* ]] || false
}

@test "no warning when a workflow defines a job with the required id" {
  run gh-repo-profile "$REPO"
  [[ $output == *"'ci' matches a job id in .github/workflows/ci.yml"* ]] || false
  [[ $output != *"  ! "* ]] || false
}

@test "warns, and still applies, when the repo has no workflows at all" {
  stub gh route-fails contents/.github/workflows
  run gh-repo-profile "$REPO"
  [ "$status" -eq 0 ]
  [[ $output == *"$REPO has no .github/workflows, so the 'ci' check can never report"* ]] || false
  [[ $(writes) == *"-X POST repos/$REPO/rulesets"* ]] || false
}

@test "warns, and still applies, when no workflow defines the required job" {
  stub gh route contents/.github/workflows/ci.yml <<<$'jobs:\n  build:\n    runs-on: macos-latest'
  run gh-repo-profile "$REPO"
  [ "$status" -eq 0 ]
  [[ $output == *"no workflow in $REPO defines a job with id 'ci'"* ]] || false
  [[ $(writes) == *"-X POST repos/$REPO/rulesets"* ]] || false
}

@test "reports which expected secrets are not set, and how to set them" {
  run gh-repo-profile "$REPO"
  [[ $output == *"CLAUDE_CODE_OAUTH_TOKEN is not set -- claude.yml, claude-code-review.yml needs it: gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo $REPO"* ]] || false
  [[ $output == *"FLY_API_TOKEN is not set -- deploy.yml needs it: gh secret set FLY_API_TOKEN --repo $REPO"* ]] || false
}

@test "reports the secrets that are set" {
  stub gh route actions/secrets <<<'{"total_count": 1, "secrets": [{"name": "FLY_API_TOKEN"}]}'
  run gh-repo-profile "$REPO"
  [[ $output == *"FLY_API_TOKEN is set"* ]] || false
  [[ $output == *"CLAUDE_CODE_OAUTH_TOKEN is not set"* ]] || false
}

@test "--dry-run reads from GitHub but writes nothing" {
  run gh-repo-profile --dry-run "$REPO"
  [ "$status" -eq 0 ]
  [[ $output == *"--dry-run, nothing will be changed"* ]] || false
  [ -z "$(writes)" ]
  [[ $(stub gh calls) == *"api repos/$REPO"* ]] || false
}

@test "--dry-run prints the repo edit it would run" {
  run gh-repo-profile --dry-run "$REPO"
  [[ $output == *"would run: gh repo edit $REPO --enable-wiki=false --enable-merge-commit=false"* ]] || false
  [[ $output == *"would run: gh api --silent -X PUT repos/$REPO/vulnerability-alerts"* ]] || false
}

@test "--dry-run prints the ruleset it would send, as valid JSON that matches a real run's" {
  run gh-repo-profile --dry-run "$REPO"
  [[ $output == *"would run: gh api -X POST repos/$REPO/rulesets --input - with:"* ]] || false
  shown=$(sed -n '/ --input - with:$/,/^$/p' <<<"$output" | sed '1d' | sed 's/^      //')
  run gh-repo-profile "$REPO"
  [ "$(jq -S . <<<"$shown")" = "$(stub gh sent | jq -S .)" ]
}

@test "--dry-run says it would update the existing ruleset when there is one" {
  stub gh route rulesets <<<'[{"id": 42, "name": "Safe Main"}]'
  run gh-repo-profile --dry-run "$REPO"
  [[ $output == *"would run: gh api -X PUT repos/$REPO/rulesets/42 --input - with:"* ]] || false
  [ -z "$(writes)" ]
}

@test "--dry-run honours --no-signatures in the ruleset it prints" {
  run gh-repo-profile --dry-run --no-signatures "$REPO"
  [[ $output != *required_signatures* ]] || false
  [[ $output == *required_linear_history* ]] || false
}
