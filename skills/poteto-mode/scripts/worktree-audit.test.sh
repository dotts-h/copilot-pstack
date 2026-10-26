#!/usr/bin/env bash
set -eu
dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=worktree-audit.sh
. "$dir/worktree-audit.sh" --functions-only

failed=0
fail() {
	printf '%s\n' "$1" >&2
	failed=$((failed + 1))
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
assert_bucket '?' '#1/merged' YES no blocked
assert_bucket clean '?' YES no blocked
assert_bucket clean '#1/merged' YES '?' blocked
assert_bucket 'wip:1' '?' no no blocked

got=$(printf 'worktree /repo/my feature\nworktree /other\n' | worktree_paths | head -n 1)
[ "$got" = '/repo/my feature' ] || fail "path split: [$got]"

got=$(printf 'worktree /repo/my feature\n' | worktree_paths | while IFS= read -r wt; do printf '%s' "$wt"; done)
[ "$got" = '/repo/my feature' ] || fail "read split: [$got]"

assert_transcripts() {
	got=$(HOME=/h transcripts_dir "$1")
	[ "$got" = "/h/.cursor/projects/$2/agent-transcripts" ] || fail "transcripts for $1 got $got want slug $2"
}

assert_transcripts 'C:/Users/me/repo' c-Users-me-repo
assert_transcripts 'C:\Users\me\repo' c-Users-me-repo
assert_transcripts 'D:\Repos\Cursor\copilot-pstack' d-Repos-Cursor-copilot-pstack
assert_transcripts /c/Users c-Users
assert_transcripts /Users/foo Users-foo

want_filter='[.[] | {number: .iid, state: (if .draft == true then "draft" elif .state == "opened" then "open" else .state end), head: .source_branch, headSha: .sha}]'
[ "$glab_mr_filter" = "$want_filter" ] || fail "glab filter drifted: $glab_mr_filter"
sample='[{"iid":7,"state":"closed","draft":false,"source_branch":"feat","sha":"a1"},{"iid":8,"state":"opened","draft":true,"source_branch":"wip","sha":"b2"},{"iid":9,"state":"merged","draft":false,"source_branch":"done","sha":"c3"},{"iid":10,"state":"opened","draft":false,"source_branch":"open","sha":"d4"}]'
want='[{"number":7,"state":"closed","head":"feat","headSha":"a1"},{"number":8,"state":"draft","head":"wip","headSha":"b2"},{"number":9,"state":"merged","head":"done","headSha":"c3"},{"number":10,"state":"open","head":"open","headSha":"d4"}]'
if command -v jq >/dev/null 2>&1; then
	mapped=$(printf '%s' "$sample" | jq -c "$glab_mr_filter")
else
	mapped=$(node -e 'const rows=JSON.parse(process.argv[1]); const mapped=rows.map((row)=>({number:row.iid,state:row.draft===true?"draft":row.state==="opened"?"open":row.state,head:row.source_branch,headSha:row.sha})); process.stdout.write(JSON.stringify(mapped));' "$sample")
fi
[ "$mapped" = "$want" ] || fail "glab map: $mapped"

want_rows=$(printf 'feat\t7\tclosed\ta1\nwip\t8\tdraft\tb2\ndone\t9\tmerged\tc3\nopen\t10\topen\td4')
gh_sample='[{"number":5,"state":"MERGED","headRefName":"shipped","headRefOid":"a1"},{"number":6,"state":"OPEN","headRefName":"shipped","headRefOid":"b2"}]'
want_gh_rows=$(printf 'shipped\t5\tmerged\ta1\nshipped\t6\topen\tb2')
for parser in jq node; do
	command -v "$parser" >/dev/null 2>&1 || continue
	got=$(printf '%s' "$sample" | forge_rows "$parser" $glab_mr_fields) || fail "$parser rejected the glab list"
	[ "$got" = "$want_rows" ] || fail "$parser glab rows: $got"
	got=$(printf '%s' "$gh_sample" | forge_rows "$parser" $gh_pr_fields) || fail "$parser rejected the gh list"
	[ "$got" = "$want_gh_rows" ] || fail "$parser gh rows: $got"
	if printf '{"a":{"iid":1,"state":"merged"}}' | forge_rows "$parser" $glab_mr_fields >/dev/null; then
		fail "$parser read an object as a list"
	fi
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
root="$tmp/repo"
git init -q -b main "$root"
git -C "$root" config user.email audit@example.com
git -C "$root" config user.name audit
printf '%s\n' one > "$root/file"
git -C "$root" add file
git -C "$root" commit -q -m init

commit_in() {
	printf '%s\n' "$2" > "$root/$1/file"
	git -C "$root/$1" commit -q -am "$2"
}

git -C "$root" worktree add -q "$root/my feature (copy)" -b feature
commit_in 'my feature (copy)' two
git -C "$root" worktree add -q "$root/second workspace" -b second
commit_in 'second workspace' three
git -C "$root" worktree add -q "$root/status broken" -b broken
printf '%s\n' edit > "$root/status broken/file"
printf '%s' garbage > "$(git -C "$root/status broken" rev-parse --absolute-git-dir)/index"
status_rc=0
git -C "$root/status broken" status --porcelain >/dev/null 2>&1 || status_rc=$?
[ "$status_rc" -eq 128 ] || fail "fixture: status on a corrupt index exited $status_rc, want 128"
git -C "$root" worktree add -q "$root/shipped" -b shipped
commit_in shipped four
sha_a=$(git -C "$root/shipped" rev-parse HEAD)
git -C "$root" worktree add -q "$root/landed" -b landed

listed() {
	git -C "$root" worktree list --porcelain | worktree_paths | while IFS= read -r wt; do
		case "$wt" in */"$1") printf '%s\n' "$wt" ;; esac
	done
}
main_wt=$(git -C "$root" worktree list --porcelain | worktree_paths | head -n 1)
feature=$(listed 'my feature (copy)')
second=$(listed 'second workspace')
broken=$(listed 'status broken')
shipped=$(listed shipped)
landed=$(listed landed)
[ -n "$feature" ] || fail "porcelain dropped the spaced worktree"

stub() {
	printf '%s' "${3-}" > "$tmp/bin/$1.out"
	printf '#!/usr/bin/env bash\ncat "$0.out"\nexit %s\n' "$2" > "$tmp/bin/$1"
	chmod +x "$tmp/bin/$1"
}

baseline() {
	rm -rf "$tmp/home" "$tmp/bin"
	mkdir -p "$tmp/home" "$tmp/bin"
	stub origin 1
	stub glab 1
	stub gh 0 '[]'
}

audit() {
	table=$(HOME="$tmp/home" PATH="$tmp/bin:$PATH" TZ=UTC "$dir/worktree-audit.sh" -b main "$root" 2>"$tmp/stderr") \
		|| fail "audit exited non-zero: $(cat "$tmp/stderr")"
}

cell() {
	printf '%s\n' "$table" | wt="$1" col="$2" awk -F'\t' '
		$1 == "SIZE" { for (i = 1; i <= NF; i++) at[$i] = i; next }
		at["WORKTREE"] && $(at["WORKTREE"]) == ENVIRON["wt"] { print $(at[ENVIRON["col"]]) }'
}

expect() {
	got=$(cell "$1" "$2")
	[ "$got" = "$3" ] || fail "$4: ${1##*/} $2 got [$got] want [$3]"
}

put() {
	mkdir -p "$(dirname -- "$1")"
	printf '%s\n' "$2" >> "$1"
}

event() {
	printf '{"type":"tool.execution_start","data":{"toolName":"bash","arguments":{"command":"%s"}},"id":"e1","timestamp":"%s","parentId":null}' "$1" "$2"
}

cursor_line() {
	printf '{"role":"user","message":{"content":[{"type":"text","text":"%s"}]}}' "$1"
}

transcripts() {
	HOME="$tmp/home" transcripts_dir "$1"
}

gh_row() {
	printf '{"number":%s,"state":"%s","headRefName":"shipped","headRefOid":"%s"}' "$1" "$2" "$3"
}

glab_row() {
	printf '{"iid":%s,"state":"%s","draft":false,"source_branch":"shipped","sha":"%s"}' "$1" "$2" "$3"
}

origin_row() {
	printf '{"number":%s,"status":"%s","headRef":"shipped","headSha":"%s"}' "$1" "$2" "$3"
}

session="$tmp/home/.copilot/session-state/abc/events.jsonl"
fresh_ts=$(date -u '+%Y-%m-%dT%H:%M:%S.000Z')
stale_ts='2020-01-01T12:00:00.000Z'

baseline
audit
expect "$feature" WORKTREE "$feature" "spaced path missing from table"
expect "$feature" LAST_CHAT - "spaced worktree has no chat"
expect "$feature" BUCKET review "spaced worktree was not review"
expect "$landed" BUCKET safe "clean worktree at the base was not safe"
expect "$broken" DIRTY '?' "failed git status read as known"
expect "$broken" BUCKET blocked "failed git status was a cleanup candidate"

baseline
put "$session" "$(event "cat ${feature}-r37/file" "$fresh_ts")"
audit
expect "$feature" BUCKET review "sibling path counted as this worktree"

baseline
put "$session" "$(event "cat $feature/file" "$fresh_ts")"
audit
expect "$feature" BUCKET verify-recent-chat "copilot session did not count"

baseline
put "$session" "$(event "cat $feature/file" "$stale_ts")"
put "$session" "$(event "git -C '$second' status --short" "$fresh_ts")"
put "$session" "$(event "git -C \\\"$shipped\\\" status --short" "$fresh_ts")"
put "$(transcripts "$main_wt")/t.jsonl" "$(cursor_line "edit $landed/file")"
touch -t 202001011200 "$(transcripts "$main_wt")/t.jsonl"
audit
expect "$second" BUCKET verify-recent-chat "single-quoted path did not count"
expect "$shipped" BUCKET verify-recent-chat "backslash-quoted path did not count"
expect "$feature" LAST_CHAT 2020-01-01 "file mtime stood in for the event time"
expect "$feature" BUCKET review "a later unrelated event made an old chat recent"
expect "$landed" LAST_CHAT '?' "a chat with no event time read as known"
expect "$landed" BUCKET blocked "a chat with no event time was a cleanup candidate"

baseline
put "$(transcripts "$second")/t.jsonl" "$(cursor_line "edit $second/file")"
audit
expect "$second" LAST_CHAT '?' "the worktree's own transcript dir was not read"
expect "$second" BUCKET blocked "a chat under the worktree's own slug was not blocked"

baseline
mkdir -p "${session%/*}"
stub rg 2
audit
expect "$landed" LAST_CHAT '?' "an rg failure read as no chat"
expect "$landed" BUCKET blocked "an rg failure was a cleanup candidate"

baseline
stub gh 0 "[$(gh_row 5 MERGED "$sha_a")]"
audit
expect "$shipped" PR '#5/merged' "merged request at HEAD"
expect "$shipped" BUCKET safe "merged request at HEAD was not safe"
commit_in shipped five
sha_b=$(git -C "$root/shipped" rev-parse HEAD)
audit
expect "$shipped" PR '#5/merged-stale' "a commit after the merged head still read as merged"
expect "$shipped" BUCKET review "a commit after the merged head was a cleanup candidate"
stub gh 0 "[$(gh_row 5 MERGED "$sha_a"),$(gh_row 6 OPEN "$sha_b")]"
audit
expect "$shipped" PR '#6/open' "a merged request hid the open one"
expect "$shipped" BUCKET hold-open-pr "an open request did not hold"

baseline
stub origin 0 '{"message":"not a list"}'
stub gh 0 "[$(gh_row 6 OPEN "$sha_b")]"
audit
expect "$shipped" PR '#6/open' "a non-array source stopped the fallback"

baseline
stub origin 0 'not json'
stub gh 1
audit
expect "$landed" PR '?' "unreadable PR lists read as no PR"
expect "$landed" BUCKET blocked "unreadable PR lists left a cleanup candidate"

baseline
stub origin 0 "[$(origin_row 9 merged "$sha_b")]"
audit
expect "$shipped" PR '#9/merged' "origin merged change at HEAD"
expect "$shipped" BUCKET safe "origin merged change at HEAD was not safe"

baseline
stub glab 0 "[$(glab_row 7 merged "$sha_b")]"
stub gh 0 "[$(gh_row 8 OPEN "$sha_b")]"
git -C "$root" remote add origin https://github.com/org/gitlab-tools.git
audit
expect "$shipped" PR '#8/open' "a gitlab path on github.com used glab"
git -C "$root" remote set-url origin git@gitlab.com:org/repo.git
audit
expect "$shipped" PR '#7/merged' "an scp gitlab remote did not use glab"
expect "$shipped" BUCKET safe "a GitLab merged request at HEAD was not safe"
stub glab 0 "[$(glab_row 7 merged "$sha_a")]"
git -C "$root" remote set-url origin https://ci:token@gitlab.example.com:8443/org/repo.git
audit
expect "$shipped" PR '#7/merged-stale' "a stale GitLab merged request still read as merged"
expect "$shipped" BUCKET review "a stale GitLab merged request was a cleanup candidate"

json_cwd() {
	printf '{"timestamp":"%s","data":{"context":{"cwd":"%s"}}}' "$1" "$2"
}

chat_at() {
	dir=$tmp/chat-$3
	rm -rf "$dir"
	mkdir -p "$dir"
	printf '%s\n' "$2" > "$dir/events.jsonl"
	newest_chat_ts "$1" "$dir"
}

base=$(chat_at 'C:/Users/ada/repo' "$(json_cwd "$fresh_ts" 'C:/Users/ada/repo')" fwd)
[ "$base" != 0 ] && [ "$base" != '?' ] || fail "forward-slash cwd was not a chat: [$base]"
got=$(chat_at 'C:/Users/ada/repo' "$(json_cwd "$fresh_ts" 'C:\\Users\\ada\\repo')" win)
[ "$got" = "$base" ] || fail "windows json cwd got [$got] want [$base]"
got=$(chat_at 'C:/Users/ada/repo' "$(json_cwd "$fresh_ts" 'c:\\Users\\ada\\repo')" case)
[ "$got" = "$base" ] || fail "drive-letter case got [$got] want [$base]"
got=$(chat_at '/Users/ada/repo' "$(json_cwd "$fresh_ts" '/Users/ada/repo')" mac)
[ "$got" = "$base" ] || fail "mac cwd got [$got] want [$base]"
got=$(chat_at '/Users/ada/repo' "$(json_cwd "$fresh_ts" '\\Users\\ada\\repo')" macbs)
[ "$got" = "$base" ] || fail "mac backslash cwd got [$got] want [$base]"
got=$(chat_at 'C:\Users\ada\repo' "$(json_cwd "$fresh_ts" 'C:\\Users\\ada\\repo')" needle)
[ "$got" = "$base" ] || fail "backslash needle got [$got] want [$base]"
got=$(chat_at '/Users/ada/repo' "$(json_cwd "$fresh_ts" '/Users/ada/repo-extra')" sib)
[ "$got" = 0 ] || fail "sibling cwd counted: [$got]"
yamldir=$tmp/chat-yaml
rm -rf "$yamldir"
mkdir -p "$yamldir"
printf '%s\n' 'cwd: C:\Users\ada\repo' > "$yamldir/workspace.yaml"
got=$(newest_chat_ts 'C:/Users/ada/repo' "$yamldir")
[ "$got" = 0 ] || fail "yaml-only cwd counted: [$got]"
printf '%s\n' "$(json_cwd "$fresh_ts" 'C:\\Users\\ada\\repo')" > "$yamldir/events.jsonl"
got=$(newest_chat_ts 'C:/Users/ada/repo' "$yamldir")
[ "$got" = "$base" ] || fail "yaml beside a json cwd got [$got] want [$base]"

baseline
json_path=$(printf '%s' "$feature" | sed 's#/#\\\\#g')
put "$session" "$(json_cwd "$fresh_ts" "$json_path")"
audit
expect "$feature" BUCKET verify-recent-chat "json-escaped cwd did not count"

[ "$failed" -eq 0 ] || { printf '%s\n' "$failed worktree-audit checks failed" >&2; exit 1; }
printf '%s\n' 'worktree-audit fixtures passed'
