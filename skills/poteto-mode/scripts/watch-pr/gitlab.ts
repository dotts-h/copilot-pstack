import {
  GhGitHubReader,
  WatcherQueryError,
  list,
  missing,
  optionalString,
  record,
  run,
  runJson,
  string,
  type CommandRunner,
} from "./github.ts";
import type * as T from "./types.ts";
import { parsePrNumber } from "./types.ts";

const MR_STATES = {
  opened: "OPEN",
  locked: "OPEN",
  closed: "CLOSED",
  merged: "MERGED",
} as const satisfies Record<string, T.PullRequestFacts["state"]>;
const MERGE_STATUS = {
  mergeable: { state: "CLEAN", review: null },
  conflict: { state: "DIRTY", review: null },
  need_rebase: { state: "BEHIND", review: null },
  draft_status: { state: "DRAFT", review: null },
  not_approved: { state: "BLOCKED", review: "REVIEW_REQUIRED" },
  requested_changes: { state: "BLOCKED", review: "CHANGES_REQUESTED" },
  discussions_not_resolved: { state: "BLOCKED", review: null },
  ci_must_pass: { state: "BLOCKED", review: null },
  ci_still_running: { state: "BLOCKED", review: null },
  status_checks_must_pass: { state: "BLOCKED", review: null },
  commits_status: { state: "BLOCKED", review: null },
  security_policy_pipeline_check: { state: "BLOCKED", review: null },
  security_policy_violations: { state: "BLOCKED", review: null },
  merge_request_blocked: { state: "BLOCKED", review: null },
  jira_association_missing: { state: "BLOCKED", review: null },
  title_regex: { state: "BLOCKED", review: null },
  locked_paths: { state: "BLOCKED", review: null },
  locked_lfs_files: { state: "BLOCKED", review: null },
  merge_time: { state: "BLOCKED", review: null },
  not_open: { state: "UNKNOWN", review: null },
  unchecked: { state: "UNKNOWN", review: null },
  checking: { state: "UNKNOWN", review: null },
  preparing: { state: "UNKNOWN", review: null },
  approvals_syncing: { state: "UNKNOWN", review: null },
} as const satisfies Record<
  string,
  { readonly state: T.MergeStateStatus; readonly review: T.ReviewDecision }
>;
const PIPELINE_STATUS = {
  created: "pending",
  waiting_for_resource: "pending",
  preparing: "pending",
  waiting_for_callback: "pending",
  pending: "pending",
  running: "pending",
  canceling: "pending",
  scheduled: "pending",
  success: "passed",
  skipped: "skipped",
  failed: "failed",
  canceled: "failed",
  manual: "failed",
} as const satisfies Record<string, T.PipelineCheck["kind"]>;
const lookup = <V>(
  table: Readonly<Record<string, V>>,
  key: unknown
): V | undefined =>
  typeof key === "string" && Object.hasOwn(table, key) ? table[key] : undefined;
function remoteLocation(
  remote: string
): { readonly host: string; readonly path: readonly string[] } | null {
  const scp = /^(?:[^@\s/]+@)?([^:\s/]+):(?!\/\/)(.+)$/.exec(remote);
  let location: { readonly hostname: string; readonly pathname: string };
  try {
    location =
      scp === null ? new URL(remote) : { hostname: scp[1], pathname: scp[2] };
  } catch {
    return null;
  }
  return {
    host: location.hostname.toLowerCase(),
    path: location.pathname
      .replace(/\.git$/, "")
      .split("/")
      .filter(Boolean),
  };
}
export function readerForRemote(remote: string | null): T.ForgeReader {
  const location = remote === null ? null : remoteLocation(remote);
  if (location === null || !location.host.includes("gitlab"))
    return new GhGitHubReader();
  const { path } = location;
  return new GlabGitLabReader({
    origin:
      path.length >= 2
        ? { owner: path.slice(0, -1).join("/"), repo: path[path.length - 1] }
        : null,
  });
}
function parseMergeRequestUrl(value: string): T.PrContext {
  try {
    const url = new URL(value);
    const parts = url.pathname.split("/").filter(Boolean);
    const dash = parts.indexOf("-");
    if (
      (url.protocol !== "https:" && url.protocol !== "http:") ||
      url.username ||
      url.password ||
      url.search ||
      url.hash ||
      dash < 2 ||
      parts.length !== dash + 3 ||
      parts[dash + 1] !== "merge_requests"
    )
      throw new Error("not a canonical GitLab merge request URL");
    return {
      owner: parts.slice(0, dash - 1).join("/"),
      repo: parts[dash - 1],
      number: parsePrNumber(Number(parts[dash + 2])),
    };
  } catch (error) {
    throw new WatcherQueryError({
      kind: "invalid-context-url",
      retryable: false,
      rawValue: value,
      detail: `could not infer project from MR URL: ${value} (${error instanceof Error ? error.message : String(error)})`,
    });
  }
}
function parseHeadPipeline(
  value: unknown,
  context: T.PrContext,
  headSha: string | null
): T.HeadPipeline {
  if (value === undefined || value === null)
    return {
      kind: "missing",
      detail: "merge request has no visible head pipeline",
    };
  const pipeline = record(value, "merge request.head_pipeline");
  const ref = string(pipeline.ref, "merge request.head_pipeline.ref");
  if (ref === `refs/merge-requests/${context.number}/merge`)
    return { kind: "merged-results", ref };
  const status = string(pipeline.status, "merge request.head_pipeline.status");
  const pipelineSha = string(pipeline.sha, "merge request.head_pipeline.sha");
  if (pipelineSha !== headSha)
    return {
      kind: "missing",
      detail: `head pipeline ran on ${pipelineSha}, not the merge request head ${headSha ?? "(none)"}`,
    };
  return {
    kind: "visible",
    check: {
      kind: lookup(PIPELINE_STATUS, status) ?? "failed",
      name: "pipeline",
      reportedState: status.toUpperCase(),
      description: "",
      link: string(pipeline.web_url, "merge request.head_pipeline.web_url"),
      workflow: "",
    },
  };
}
function parseMergeRequest(
  value: unknown,
  context: T.PrContext
): T.MergeRequestRead {
  const object = record(value, "merge request");
  if (typeof object.draft !== "boolean")
    missing("merge request.draft", object.draft);
  if (typeof object.has_conflicts !== "boolean")
    missing("merge request.has_conflicts", object.has_conflicts);
  const row =
    lookup(MERGE_STATUS, object.detailed_merge_status) ??
    missing(
      "merge request.detailed_merge_status",
      object.detailed_merge_status
    );
  const sha = optionalString(object.sha, "merge request.sha");
  return {
    facts: {
      context,
      mergeable:
        object.has_conflicts || row.state === "DIRTY"
          ? "CONFLICTING"
          : row.state === "UNKNOWN"
            ? "UNKNOWN"
            : "MERGEABLE",
      mergeStateStatus: row.state,
      reviewDecision: row.review,
      headRefOid: sha,
      headRefName: string(object.source_branch, "merge request.source_branch"),
      baseRefName: string(object.target_branch, "merge request.target_branch"),
      state:
        lookup(MR_STATES, object.state) ??
        missing("merge request.state", object.state),
      mergedAt: optionalString(object.merged_at, "merge request.merged_at"),
      isDraft: object.draft,
    },
    pipeline: parseHeadPipeline(object.head_pipeline, context, sha),
  };
}
function parseNote(note: Record<string, unknown>): T.ReviewComment {
  const author = record(note.author, "discussion note.author");
  const position =
    note.position === undefined
      ? null
      : record(note.position, "discussion note.position");
  const line =
    position === null ? null : (position.new_line ?? position.old_line ?? null);
  return {
    authorLogin: string(author.username, "discussion note.author.username"),
    body: string(note.body, "discussion note.body"),
    path:
      position === null
        ? null
        : string(position.new_path, "discussion note.position.new_path"),
    line:
      line === null
        ? null
        : Number.isInteger(line)
          ? Number(line)
          : missing("discussion note.position.line", line),
    createdAt: string(note.created_at, "discussion note.created_at"),
  };
}
function isUnresolved(note: Record<string, unknown>): boolean {
  if (typeof note.resolvable !== "boolean")
    missing("discussion note.resolvable", note.resolvable);
  if (!note.resolvable) return false;
  if (typeof note.resolved !== "boolean")
    missing("discussion note.resolved", note.resolved);
  return !note.resolved;
}
function parseDiscussions(
  discussions: readonly unknown[]
): readonly T.GitLabThread[] {
  const threads: T.GitLabThread[] = [];
  for (const item of discussions) {
    const discussion = record(item, "discussion");
    const notes = list(discussion.notes, "discussion.notes").map((note) =>
      record(note, "discussion note")
    );
    if (!notes.some(isUnresolved)) continue;
    threads.push({
      id: string(discussion.id, "discussion.id"),
      firstComment: parseNote(notes[0]),
      isBugbot: false,
      bugbotReviewPasses: 0,
    });
  }
  return threads;
}
const mergeRequestPath = (context: T.PrContext): string =>
  `projects/${encodeURIComponent(`${context.owner}/${context.repo}`)}/merge_requests/${context.number}`;

export class GlabGitLabReader implements T.GitLabReader {
  readonly forge = "gitlab";
  private readonly origin: T.Repository | null;
  private readonly run: CommandRunner;
  constructor(args: {
    readonly origin: T.Repository | null;
    readonly run?: CommandRunner;
  }) {
    this.origin = args.origin;
    this.run = args.run ?? run;
  }
  async originRepo(): Promise<T.Repository | null> {
    return this.origin;
  }
  async currentPr(pr: T.PrNumber | null): Promise<T.PrContext> {
    const argv: [string, ...string[]] = ["glab", "mr", "view"];
    if (pr !== null) argv.push(String(pr));
    argv.push("--output", "json");
    const object = record(await runJson(argv, this.run), "current MR");
    const parsed = parseMergeRequestUrl(
      string(object.web_url, "current MR.web_url")
    );
    return {
      ...parsed,
      number: pr ?? parsePrNumber(object.iid, "current MR.iid"),
    };
  }
  async mergeRequest(context: T.PrContext): Promise<T.MergeRequestRead> {
    return parseMergeRequest(
      await runJson(["glab", "api", mergeRequestPath(context)], this.run),
      context
    );
  }
  async unresolvedThreads(
    context: T.PrContext
  ): Promise<readonly T.GitLabThread[]> {
    const discussions: unknown[] = [];
    for (let page = 1; ; page += 1) {
      const pageItems = list(
        await runJson(
          [
            "glab",
            "api",
            `${mergeRequestPath(context)}/discussions`,
            "--method",
            "GET",
            "--raw-field",
            "per_page=100",
            "--raw-field",
            `page=${page}`,
          ],
          this.run
        ),
        "discussions"
      );
      // GitLab drops notes the token cannot read after paging, so only an empty page ends the list.
      if (pageItems.length === 0) break;
      discussions.push(...pageItems);
    }
    return parseDiscussions(discussions);
  }
}
