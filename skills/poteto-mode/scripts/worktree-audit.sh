#!/usr/bin/env bash
# Read-only worktree prune audit. Classifies every git worktree by size, merge
# state, uncommitted work, remote/PR state, and the most recent chat that
# operated in it. Emits a table sorted by size with a suggested bucket. Never
# deletes anything; deletion stays a human-gated step in the playbook.
# A ? cell is an observation that failed (git status, every PR source, or a
# chat line with no readable event time). Its row is blocked, never safe.
#
# Usage: worktree-audit.sh [-b|--base <ref>] [repo-path]
#   repo-path defaults to the current repo.
#   -b sets the ref the MERGED column checks against (e.g. origin/integration).
#   Without it the base is origin/HEAD, then origin/main, then origin/master.
#   origin/HEAD is the remote's default branch, not necessarily the branch PRs
#   merge into; pass -b when they differ.
set -u

worktree_paths() {
	sed -n 's/^worktree //p'
}

pr_filter() {
	printf '[.[] | {number: .%s, state: (if .draft == true then "draft" elif .%s == "opened" then "open" else .%s end), head: .%s, headSha: .%s}]' "$1" "$2" "$2" "$3" "$4"
}

# origin pr list has no head SHA field, so its merged rows are safe only by ancestry.
origin_pr_fields='number status headRef none'
glab_mr_fields='iid state source_branch sha'
gh_pr_fields='number state headRefName headRefOid'
glab_mr_filter=$(pr_filter $glab_mr_fields)

forge_rows() {
	local parser rows
	parser=$1
	shift
	case $parser in
	jq) rows=$(jq -rn "input | if type == \"array\" then . else error(\"not a list\") end | $(pr_filter "$@") | .[] | [.head, .number, (.state | ascii_downcase), .headSha] | @tsv" 2>/dev/null) || return 1 ;;
	node) rows=$(node -e '
		const [num, state, head, sha] = process.argv.slice(1);
		let text = "";
		process.stdin.setEncoding("utf8");
		process.stdin.on("data", (chunk) => { text += chunk; });
		process.stdin.on("end", () => {
			const rows = JSON.parse(text);
			if (!Array.isArray(rows)) throw new Error("not a list");
			process.stdout.write(rows.map((row) => {
				const s = row.draft === true ? "draft" : row[state] === "opened" ? "open" : row[state];
				return [row[head], row[num], s.toLowerCase(), row[sha]].join("\t") + "\n";
			}).join(""));
		});' "$@" 2>/dev/null) || return 1 ;;
	*) return 1 ;;
	esac
	printf '%s' "$rows" | tr -d '\r'
}

# awk compares number-shaped strings as numbers, so the trailing "" forces a
# string compare of the branch and the SHA.
pr_cell() {
	pr_branch="$1" pr_head="$2" awk -F'\t' '
		ENVIRON["pr_branch"] != "" && $1 == ENVIRON["pr_branch"] "" {
			if ($3 == "open" || $3 == "draft") rank = 3
			else if ($3 == "merged" && $4 != "" && $4 == ENVIRON["pr_head"] "") rank = 2
			else rank = 1
			if (rank > best) {
				best = rank
				cell = "#" $2 "/" $3
				if (rank == 1 && $3 == "merged") cell = cell "-stale"
			}
		}
		END { print (best ? cell : "-") }'
}

remote_host() {
	local authority
	case $1 in
	*://*) authority=${1#*://}; authority=${authority%%/*} ;;
	*:*) authority=${1%%:*}; case $authority in */*) return 0 ;; esac ;;
	*) return 0 ;;
	esac
	authority=${authority##*@}
	printf '%s\n' "${authority%%:*}" | tr '[:upper:]' '[:lower:]'
}

audit_bucket() {
	dirty="$1"
	pr="$2"
	merged="$3"
	recent="$4"
	if [ "$dirty" = '?' ] || [ "$pr" = '?' ] || [ "$recent" = '?' ]; then
		printf '%s\n' blocked
		return
	fi
	case "$dirty" in
	wip:*) printf '%s\n' hold-wip; return ;;
	esac
	case "$pr" in
	*/open|*/opened|*/draft) printf '%s\n' hold-open-pr; return ;;
	esac
	if [ "$recent" = yes ]; then
		printf '%s\n' verify-recent-chat
		return
	fi
	if [ "$merged" = YES ]; then
		printf '%s\n' safe
		return
	fi
	case "$pr" in
	*/merged) printf '%s\n' safe ;;
	*) printf '%s\n' review ;;
	esac
}

transcripts_dir() {
	printf '%s/.cursor/projects/%s/agent-transcripts\n' "$HOME" "$(printf '%s' "$1" | sed 's#^/##; s#/#-#g')"
}

newest_chat_ts() {
	local needle dir ts
	needle=$1
	shift
	for dir do
		shift
		[ -d "$dir" ] && set -- "$@" "$dir"
	done
	[ $# -gt 0 ] || { printf '%s\n' 0; return; }
	# A user ripgrep config (max-columns, globs, max-count) could hide or truncate matches.
	if ts=$(rg --no-config --no-filename -N -F \
		-e "$needle/" -e "$needle\"" -e "$needle'" -e "$needle\\\"" -- "$@" 2>/dev/null | awk '
		function epoch(t,   y, m, d, hh, mm, ss, era, yoe, doy, doe) {
			y = substr(t, 1, 4) + 0
			m = substr(t, 6, 2) + 0
			d = substr(t, 9, 2) + 0
			hh = substr(t, 12, 2) + 0
			mm = substr(t, 15, 2) + 0
			ss = substr(t, 18, 2) + 0
			if (m < 1 || m > 12 || d < 1 || d > 31 || hh > 23 || mm > 59 || ss > 60) return -1
			if (m <= 2) y--
			era = int(y / 400)
			yoe = y - era * 400
			doy = int((153 * (m > 2 ? m - 3 : m + 9) + 2) / 5) + d - 1
			doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
			return (era * 146097 + doe - 719468) * 86400 + hh * 3600 + mm * 60 + ss
		}
		{
			sub(/\r$/, "")
			line = -1
			s = $0
			while (match(s, /"timestamp"[ \t]*:[ \t]*"[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9](\.[0-9]+)?Z"/)) {
				t = substr(s, RSTART, RLENGTH)
				sub(/^"timestamp"[ \t]*:[ \t]*"/, "", t)
				e = epoch(t)
				if (e < 0) { line = -1; break }
				if (e > line) line = e
				s = substr(s, RSTART + RLENGTH)
			}
			if (line < 0) unknown = 1
			else if (line > best) best = line
		}
		END {
			if (unknown) print "?"
			else printf "%.0f\n", best
		}'
		exit $(( ${PIPESTATUS[0]} > 1 || ${PIPESTATUS[1]} != 0 ))) && [ -n "$ts" ]; then
		printf '%s\n' "$ts"
	else
		printf '%s\n' '?'
	fi
}

if [ "${1:-}" = "--functions-only" ]; then
	return 0 2>/dev/null || exit 0
fi

base=""
while [ $# -gt 0 ]; do
	case "$1" in
	-b|--base) [ $# -ge 2 ] || { echo "error: $1 needs a ref" >&2; exit 2; }; base="$2"; shift 2 ;;
	-h|--help) sed -n '2,/^set -u/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
	-*) echo "error: unknown option: $1" >&2; exit 2 ;;
	*) break ;;
	esac
done

repo="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -z "$repo" ] && { echo "not in a git repo; pass a repo path" >&2; exit 1; }
cd "$repo" || exit 1
git rev-parse --git-dir >/dev/null 2>&1 || { echo "error: not a git repo: $repo" >&2; exit 1; }

# Main worktree is the first entry; everything else is a candidate.
main_wt=$(git worktree list --porcelain | worktree_paths | head -n 1)

if [ -z "$base" ]; then
	for cand in "$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)" origin/main origin/master; do
		[ -n "$cand" ] && git rev-parse --verify --quiet "$cand^{commit}" >/dev/null && { base="$cand"; break; }
	done
	[ -z "$base" ] && { echo "error: no base ref (origin/HEAD, origin/main, origin/master all missing); pass -b <ref>" >&2; exit 1; }
	echo "warn: no -b given; MERGED checks against $base" >&2
fi

# The base drives the merge check. The fetch is best-effort (stale is fine for
# a first pass) and runs before the check, since -b may name a branch not
# fetched yet. The explicit refspec creates it even in a single-branch clone.
case "$base" in
origin/*) git fetch origin "+refs/heads/${base#origin/}:refs/remotes/$base" --quiet 2>/dev/null \
	|| echo "warn: could not fetch $base; merged column may be stale" >&2 ;;
esac
git rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1 || { echo "error: base ref not found: $base" >&2; exit 1; }

# GNU coreutils (Linux, Homebrew gnubin) reads `date -r` as a file, so pick
# the date flag once.
if stat -c %Y / >/dev/null 2>&1; then
	fmt_day() { date -d "@$1" '+%Y-%m-%d'; }
else
	fmt_day() { date -r "$1" '+%Y-%m-%d'; }
fi

if command -v jq >/dev/null 2>&1; then json=jq
elif command -v node >/dev/null 2>&1; then json=node
else json=none; fi
case $(remote_host "$(git remote get-url origin 2>/dev/null)") in
*gitlab*) gitlab=yes ;;
*) gitlab=no ;;
esac
prs=$( { command -v origin >/dev/null 2>&1 \
		&& raw=$(origin pr list --author "@me" --state all --limit 1000 --json number,status,headRef 2>/dev/null) \
		&& printf '%s' "$raw" | forge_rows "$json" $origin_pr_fields; } \
	|| { [ "$gitlab" = yes ] \
		&& raw=$(glab mr list --all --per-page 100 --output json 2>/dev/null) \
		&& printf '%s' "$raw" | forge_rows "$json" $glab_mr_fields; } \
	|| { raw=$(gh pr list --author "@me" --state all --limit 1000 --json number,state,headRefName,headRefOid 2>/dev/null) \
		&& printf '%s' "$raw" | forge_rows "$json" $gh_pr_fields; } ) \
	|| { prs='?'; echo "warn: no PR source returned a list (JSON via $json); PR column is ?" >&2; }

transcripts=$(transcripts_dir "$main_wt")
now=$(date +%s)

echo "# base: $base"
printf "SIZE\tAGE\tMERGED\tDIRTY\tREMOTE\tPR\tLAST_CHAT\tBUCKET\tWORKTREE\n"

git worktree list --porcelain | worktree_paths | while IFS= read -r wt; do
	[ "$wt" = "$main_wt" ] && continue

	size=$(du -sh "$wt" 2>/dev/null | awk '{print $1}')
	head=$(git -C "$wt" rev-parse HEAD 2>/dev/null)
	head_ts=$(git -C "$wt" log -1 --format='%ct' HEAD 2>/dev/null || echo 0)
	age=$([ "$head_ts" -gt 0 ] 2>/dev/null && echo "$(( (now - head_ts) / 86400 ))d" || echo "?")

	# Squash-merged branches are not ancestors of the base, so PR state is the
	# real signal; merge-base only catches fast-forward/rebase merges.
	git merge-base --is-ancestor "$head" "$base" 2>/dev/null && merged=YES || merged=no

	# Distinguish real WIP (tracked edits) from disposable untracked scratch.
	if ! porcelain=$(git -C "$wt" status --porcelain 2>/dev/null); then dirty='?'
	elif [ -z "$porcelain" ]; then dirty=clean
	elif printf '%s\n' "$porcelain" | grep -qv '^??'; then
		dirty="wip:$(printf '%s\n' "$porcelain" | grep -cv '^??')"
	else dirty="scratch:$(printf '%s\n' "$porcelain" | grep -c '^??')"; fi

	branch=$(git -C "$wt" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "")
	if [ -z "$branch" ]; then remote=detached
	elif git -C "$wt" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
		[ "$(git -C "$wt" rev-parse "origin/$branch" 2>/dev/null)" = "$head" ] \
			&& remote=pushed \
			|| remote="ahead$(git -C "$wt" rev-list --count "origin/$branch..HEAD" 2>/dev/null)"
	else remote=no-remote; fi

	if [ "$prs" = '?' ]; then pr='?'
	else pr=$(printf '%s\n' "$prs" | pr_cell "$branch" "$head"); fi

	last_ts=$(newest_chat_ts "$wt" "$transcripts" "$(transcripts_dir "$wt")" "$HOME/.copilot/session-state")
	case $last_ts in
	'?') last='?'; recent='?' ;;
	0) last=-; recent=no ;;
	*) last=$(fmt_day "$last_ts" 2>/dev/null)
		[ $(( (now - last_ts) / 86400 )) -le 4 ] && recent=yes || recent=no ;;
	esac

	bucket=$(audit_bucket "$dirty" "$pr" "$merged" "$recent")

	printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
		"$size" "$age" "$merged" "$dirty" "$remote" "$pr" "$last" "$bucket" "$wt"
done | sort -t$'\t' -k1,1 -rh
