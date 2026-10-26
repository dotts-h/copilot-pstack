#!/usr/bin/env bash
# Read-only worktree prune audit. Classifies every git worktree by size, merge
# state, uncommitted work, remote/PR state, and the most recent chat that
# operated in it. Emits a table sorted by size with a suggested bucket. Never
# deletes anything; deletion stays a human-gated step in the playbook.
# A ? cell is an observation that failed (git status, every PR source, the
# transcript search, a chat line with no readable event time, or a Copilot
# session bound to the worktree with no readable event time). Its row is
# blocked, never safe.
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

origin_pr_fields='number status headRef headSha'
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
	local path
	path=$1
	case $path in
	[A-Za-z]:*) path=$(printf '%s' "${path:0:1}" | tr '[:upper:]' '[:lower:]')$(printf '%s' "${path:2}" | tr '\\' /) ;;
	esac
	printf '%s/.cursor/projects/%s/agent-transcripts\n' "$HOME" "$(printf '%s' "$path" | sed 's#^/##; s#/#-#g')"
}

chat_patterns() {
	local base extra spell json
	base=$(printf '%s' "$1" | tr '\\' '/')
	extra=$base
	case $base in
	[A-Za-z]:*) extra=$(printf '%s' "${base:0:1}" | tr 'A-Za-z' 'a-zA-Z')${base:1} ;;
	esac
	for spell in "$base" "$extra"; do
		json=$(printf '%s' "$spell" | sed 's#/#\\\\#g')
		printf '%s\n' \
			"$spell/" \
			"$spell\"" \
			"$spell'" \
			"$spell\\\"" \
			"$json\\\\" \
			"$json\"" \
			"$json'" \
			"$json\\\""
		[ "$spell" = "$extra" ] && break
	done
}

chat_ts_awk='
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
function shaped_ts(s) {
	return match(s, /"timestamp"[ \t]*:[ \t]*"[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9](\.[0-9]+)?Z"/)
}
function line_ts(s,   line, t, e) {
	line = -1
	while (shaped_ts(s)) {
		t = substr(s, RSTART, RLENGTH)
		sub(/^"timestamp"[ \t]*:[ \t]*"/, "", t)
		e = epoch(t)
		if (e < 0) return -1
		if (e > line) line = e
		s = substr(s, RSTART + RLENGTH)
	}
	return line
}
'

session_dirs() {
	local root child
	root=$1
	[ -d "$root" ] || return 0
	if [ -f "$root/events.jsonl" ] || [ -f "$root/workspace.yaml" ]; then
		printf '%s\n' "$root"
		return 0
	fi
	for child in "$root"/*; do
		[ -d "$child" ] || continue
		if [ -f "$child/events.jsonl" ] || [ -f "$child/workspace.yaml" ]; then
			printf '%s\n' "$child"
		fi
	done
}

mention_ts() {
	local needle ts
	needle=$1
	shift
	[ $# -gt 0 ] || { printf '%s\n' 0; return 0; }
	# Quoted cwd lines in workspace.yaml have no timestamp and would mark this scan unknown.
	if ts=$(chat_patterns "$needle" | rg --no-config --no-filename -N -F -g '!workspace.yaml' -f - -- "$@" 2>/dev/null | awk "$chat_ts_awk"'
		{
			sub(/\r$/, "")
			line = line_ts($0)
			if (line < 0) unknown = 1
			else if (line > best) best = line
		}
		END {
			if (unknown) print "?"
			else printf "%.0f\n", best
		}'
		exit $(( ${PIPESTATUS[1]} > 1 || ${PIPESTATUS[2]} != 0 ))); then
		[ -n "$ts" ] || ts='?'
		printf '%s\n' "$ts"
	else
		printf '%s\n' '?'
	fi
}

bound_session_ts() {
	local needle session_dir yaml_present events_present
	needle=$1
	session_dir=$2
	yaml_present=0
	events_present=0
	if [ -f "$session_dir/workspace.yaml" ]; then
		yaml_present=1
	fi
	if [ -f "$session_dir/events.jsonl" ]; then
		events_present=1
	fi
	needle="$needle" session_dir="$session_dir" yaml_present="$yaml_present" events_present="$events_present" awk "$chat_ts_awk"'
		function norm(p) {
			gsub(/\\/, "/", p)
			gsub(/\/+/, "/", p)
			sub(/\/$/, "", p)
			if (p ~ /^[A-Za-z]:/) p = tolower(substr(p, 1, 1)) substr(p, 2)
			return p
		}
		function binds(cand,   n) {
			n = norm(cand)
			if (n == needle) return 1
			if (index(n, needle "/") == 1) return 1
			return 0
		}
		function yaml_cwd(line,   val, n, q) {
			sub(/\r$/, "", line)
			if (!match(line, /^[ \t]*cwd:[ \t]*/)) return ""
			val = substr(line, RSTART + RLENGTH)
			sub(/^[ \t]+/, "", val)
			sub(/[ \t]+$/, "", val)
			n = length(val)
			if (n < 2) return val
			q = sprintf("%c", 39)
			if ((substr(val, 1, 1) == "\"" && substr(val, n, 1) == "\"") || (substr(val, 1, 1) == q && substr(val, n, 1) == q))
				val = substr(val, 2, n - 2)
			return val
		}
		BEGIN {
			needle = norm(ENVIRON["needle"])
			dir = ENVIRON["session_dir"]
			bound = 0
			bad = 0
			best = -1
			if (ENVIRON["yaml_present"] == "1") {
				yaml = dir "/workspace.yaml"
				while ((getline line < yaml) > 0) {
					val = yaml_cwd(line)
					if (val != "" && binds(val)) bound = 1
				}
				close(yaml)
			}
			if (ENVIRON["events_present"] == "1") {
				events = dir "/events.jsonl"
				while ((getline line < events) > 0) {
					sub(/\r$/, "", line)
					if (line ~ /"type"[ \t]*:[ \t]*"session.start"/ && match(line, /"cwd"[ \t]*:[ \t]*"/)) {
						val = substr(line, RSTART + RLENGTH)
						sub(/".*/, "", val)
						if (binds(val)) bound = 1
					}
					e = line_ts(line)
					if (e >= 0) {
						if (e > best) best = e
					} else if (shaped_ts(line)) {
						bad = 1
					}
				}
				close(events)
			}
			if (!bound) exit 0
			if (bad || best < 0) print "?"
			else printf "%.0f\n", best
			exit 0
		}'
}

newest_chat_ts() {
	local needle dir mentions sessions session contrib sess_best sess_q
	needle=$1
	shift
	for dir do
		shift
		[ -d "$dir" ] && set -- "$@" "$dir"
	done
	[ $# -gt 0 ] || { printf '%s\n' 0; return 0; }
	mentions=$(mention_ts "$needle" "$@") || mentions='?'
	sess_best=0
	sess_q=0
	for dir do
		while IFS= read -r session; do
			[ -n "$session" ] || continue
			contrib=$(bound_session_ts "$needle" "$session") || contrib='?'
			case $contrib in
			'') ;;
			'?') sess_q=1 ;;
			*)
				if [ "$contrib" -gt "$sess_best" ]; then
					sess_best=$contrib
				fi
				;;
			esac
		done < <(session_dirs "$dir")
	done
	if [ "$sess_q" -eq 1 ]; then
		sessions='?'
	else
		sessions=$sess_best
	fi
	if [ "$mentions" = '?' ] || [ "$sessions" = '?' ]; then
		printf '%s\n' '?'
		return 0
	fi
	if [ "$mentions" -gt "$sessions" ]; then
		printf '%s\n' "$mentions"
	else
		printf '%s\n' "$sessions"
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
		&& raw=$(origin pr list --author "@me" --state all --limit 1000 --json number,status,headRef,headSha 2>/dev/null) \
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
