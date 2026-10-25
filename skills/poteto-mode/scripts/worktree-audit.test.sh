#!/usr/bin/env bash
set -eu
dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=worktree-audit.sh
. "$dir/worktree-audit.sh" --functions-only

fail() {
	printf '%s\n' "$1" >&2
	exit 1
}

assert_bucket() {
	got=$(audit_bucket "$1" "$2" "$3" "$4")
	[ "$got" = "$5" ] || fail "bucket dirty=$1 pr=$2 merged=$3 recent=$4 got $got want $5"
}

assert_bucket clean '#1/open' no no hold-open-pr
assert_bucket clean '#1/opened' no no hold-open-pr
assert_bucket clean '#1/draft' no no hold-open-pr
assert_bucket 'wip:1' '#1/closed' no no hold-wip
assert_bucket clean '#1/merged' no no safe
assert_bucket clean '#1/merged' YES yes verify-recent-chat
assert_bucket clean '#1/closed' no no review
assert_bucket clean '-' YES no safe
assert_bucket clean '-' no no review
assert_bucket 'scratch:2' '#1/closed' no no review

got=$(printf 'worktree /repo/my feature\nworktree /other\n' | worktree_paths | head -n 1)
[ "$got" = '/repo/my feature' ] || fail "path split: [$got]"

got=$(printf 'worktree /repo/my feature\n' | worktree_paths | while IFS= read -r wt; do printf '%s' "$wt"; done)
[ "$got" = '/repo/my feature' ] || fail "read split: [$got]"

want_filter='[.[] | {number: .iid, state: (if .draft == true then "draft" elif .state == "opened" then "open" else .state end), head: .source_branch}]'
[ "$glab_mr_filter" = "$want_filter" ] || fail "glab filter drifted: $glab_mr_filter"
sample='[{"iid":7,"state":"closed","draft":false,"source_branch":"feat"},{"iid":8,"state":"opened","draft":true,"source_branch":"wip"},{"iid":9,"state":"merged","draft":false,"source_branch":"done"},{"iid":10,"state":"opened","draft":false,"source_branch":"open"}]'
want='[{"number":7,"state":"closed","head":"feat"},{"number":8,"state":"draft","head":"wip"},{"number":9,"state":"merged","head":"done"},{"number":10,"state":"open","head":"open"}]'
if command -v jq >/dev/null 2>&1; then
	mapped=$(printf '%s' "$sample" | jq -c "$glab_mr_filter")
else
	mapped=$(node -e 'const rows=JSON.parse(process.argv[1]); const mapped=rows.map((row)=>({number:row.iid,state:row.draft===true?"draft":row.state==="opened"?"open":row.state,head:row.source_branch})); process.stdout.write(JSON.stringify(mapped));' "$sample")
fi
[ "$mapped" = "$want" ] || fail "glab map: $mapped"

root=$(mktemp -d)
home=""
trap 'rm -rf "$root" "$home"' EXIT
git -C "$root" init -q -b main
git -C "$root" config user.email audit@example.com
git -C "$root" config user.name audit
printf '%s\n' one > "$root/file"
git -C "$root" add file
git -C "$root" commit -q -m init
feature="$root/my feature (copy)"
git -C "$root" worktree add -q "$feature" -b feature
printf '%s\n' two > "$feature/file"
git -C "$feature" add file
git -C "$feature" commit -q -m feature
listed=$(git -C "$root" worktree list --porcelain | worktree_paths | grep -F 'my feature (copy)')
[ -n "$listed" ] || fail "porcelain dropped the spaced worktree"
table=$("$dir/worktree-audit.sh" -b main "$root") || fail "audit exited on $root"
printf '%s\n' "$table" | grep -F -- "$listed" >/dev/null || fail "spaced path missing from table: [$table]"
printf '%s\n' "$table" | grep -F -- "$(printf '%s\treview\t%s' '-' "$listed")" >/dev/null || fail "spaced worktree was not review: [$table]"

home=$(mktemp -d)
mkdir -p "$home/.copilot/session-state/abc"
printf '%s/\n' "${listed}-r37" > "$home/.copilot/session-state/abc/events.jsonl"
table=$(HOME="$home" "$dir/worktree-audit.sh" -b main "$root") || fail "audit exited on a sibling path"
printf '%s\n' "$table" | grep -F -- "$(printf '%s\treview\t%s' '-' "$listed")" >/dev/null || fail "sibling path counted as this worktree: [$table]"
printf '%s/\n' "$listed" > "$home/.copilot/session-state/abc/events.jsonl"
table=$(HOME="$home" "$dir/worktree-audit.sh" -b main "$root") || fail "audit exited with a copilot session"
printf '%s\n' "$table" | grep -F -- "$(printf 'verify-recent-chat\t%s' "$listed")" >/dev/null || fail "copilot session did not count: [$table]"

printf '%s\n' 'worktree-audit fixtures passed'
