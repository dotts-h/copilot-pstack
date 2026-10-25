import type { CommandResult, CommandRunner } from "./github.ts";
import { runSimple } from "./policy.ts";
import type {
  Check,
  ChecksFastPath,
  CommitRollup,
  ForgeReader,
  GitHubReader,
  OpenPullRequest,
  PollingOptions,
  PrContext,
  ProgressVerdict,
  PullRequestFacts,
  Repository,
  RawReviewThread,
  ReviewThread,
  ReviewThreadPage,
  RollupPage,
} from "./types.ts";
import { parsePrNumber } from "./types.ts";

export interface FakeReaderOptions {
  readonly facts?: Partial<Omit<PullRequestFacts, "context">>;
  readonly fastPath?: ChecksFastPath;
  readonly rollupPages?: readonly RollupPage[];
  readonly threads?: readonly ReviewThread[];
  readonly threadPages?: readonly ReviewThreadPage[];
  readonly commitRollups?: readonly CommitRollup[];
  readonly openPullRequests?: readonly OpenPullRequest[];
  readonly origin?: Repository | null;
  readonly current?: PrContext;
}

function toRawThread(thread: ReviewThread): RawReviewThread {
  return { id: thread.id, firstComment: thread.firstComment, resolved: false };
}

export function passingCheck(name = "ci"): Check {
  return {
    kind: "passed",
    name,
    reportedState: "SUCCESS",
    description: "",
    link: "",
    workflow: "",
  };
}

export function pendingCheck(name = "ci"): Check {
  return {
    kind: "pending",
    name,
    reportedState: "PENDING",
    description: "",
    link: "",
    workflow: "",
  };
}

export function failedCheck(name = "ci"): Check {
  return {
    kind: "failed",
    name,
    reportedState: "FAILURE",
    description: "",
    link: "",
    workflow: "",
  };
}

export function fakeReader(
  options: FakeReaderOptions = {}
): GitHubReader & { readonly calls: readonly string[] } {
  const calls: string[] = [];
  const context = options.current ?? {
    owner: "owner",
    repo: "repo",
    number: parsePrNumber(1),
  };
  const defaults: PullRequestFacts = {
    context,
    mergeable: "MERGEABLE",
    mergeStateStatus: "CLEAN",
    reviewDecision: "APPROVED",
    headRefOid: "head",
    headRefName: "feature",
    baseRefName: "main",
    state: "OPEN",
    mergedAt: null,
    isDraft: false,
  };
  let page = 0;
  let threadPage = 0;
  return {
    forge: "github",
    calls,
    async originRepo() {
      calls.push("originRepo");
      return options.origin === undefined
        ? { owner: "owner", repo: "repo" }
        : options.origin;
    },
    async currentPr(pr) {
      calls.push("currentPr");
      return { ...context, number: pr ?? context.number };
    },
    async pullRequest(requested) {
      calls.push("pullRequest");
      return { ...defaults, ...options.facts, context: requested };
    },
    async openPullRequests() {
      calls.push("openPullRequests");
      return options.openPullRequests ?? [];
    },
    async checksFastPath() {
      calls.push("checksFastPath");
      return options.fastPath ?? { kind: "checks", checks: [passingCheck()] };
    },
    async checkRollupPage(_requested, after) {
      calls.push(`checkRollupPage:${after ?? "null"}`);
      return options.rollupPages?.[page++] ?? { checks: [], endCursor: null };
    },
    async reviewThreadPage(_requested, after) {
      calls.push(`reviewThreadPage:${after ?? "null"}`);
      return options.threadPages?.[threadPage++] ?? {
        threads: (options.threads ?? []).map(toRawThread),
        endCursor: null,
      };
    },
    async commitRollups() {
      calls.push("commitRollups");
      return options.commitRollups ?? [{ oid: "head", state: "SUCCESS" }];
    },
  };
}

export type CommandEntry = readonly [
  readonly [string, ...string[]],
  readonly CommandResult[],
];

export function commandFixture(entries: readonly CommandEntry[]): {
  readonly run: CommandRunner;
  readonly calls: readonly (readonly string[])[];
} {
  const queues = new Map(
    entries.map(([argv, results]) => [argv.join("\0"), [...results]])
  );
  const calls: (readonly string[])[] = [];
  const run: CommandRunner = async (argv) => {
    calls.push(argv);
    const queue = queues.get(argv.join("\0")) ?? [];
    const next = queue.length > 1 ? queue.shift() : queue[0];
    if (next === undefined)
      throw new Error(`unexpected command: ${argv.join(" ")}`);
    return next;
  };
  return { run, calls };
}

export const ok = (body: unknown): CommandResult => ({
  code: 0,
  stdout: JSON.stringify(body),
  stderr: "",
});

export const GITLAB_ORIGIN: Repository = {
  owner: "group/sub",
  repo: "project",
};
export const GITLAB_CONTEXT: PrContext = {
  ...GITLAB_ORIGIN,
  number: parsePrNumber(7),
};
export const GITLAB_MR_URL =
  "https://gitlab.corp.internal/group/sub/project/-/merge_requests/7";
export const GITLAB_PIPELINE_URL =
  "https://gitlab.corp.internal/group/sub/project/-/pipelines/99";
export const GLAB_MR = [
  "glab",
  "api",
  "projects/group%2Fsub%2Fproject/merge_requests/7",
] as const;
export const GLAB_DISCUSSIONS = [
  "glab",
  "api",
  "projects/group%2Fsub%2Fproject/merge_requests/7/discussions",
  "--paginate",
] as const;
const GITLAB_HEAD = "0123456789abcdef0123456789abcdef01234567";

export function pipelineBody(
  overrides: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    id: 99,
    iid: 12,
    project_id: 3,
    sha: GITLAB_HEAD,
    ref: "feature",
    status: "success",
    source: "merge_request_event",
    web_url: GITLAB_PIPELINE_URL,
    ...overrides,
  };
}

export function mergeRequestBody(
  overrides: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    iid: 7,
    state: "opened",
    draft: false,
    has_conflicts: false,
    detailed_merge_status: "mergeable",
    sha: GITLAB_HEAD,
    source_branch: "feature",
    target_branch: "main",
    merged_at: null,
    web_url: GITLAB_MR_URL,
    head_pipeline: pipelineBody(),
    ...overrides,
  };
}

export async function watchSingle(
  reader: ForgeReader,
  context: PrContext,
  polling: Partial<PollingOptions> = {},
  statusOnly = false
) {
  let now = 0;
  const sleeps: number[] = [];
  const emitted: ProgressVerdict[] = [];
  const verdict = await runSimple({
    dependencies: {
      reader,
      clock: {
        now: () => now,
        observedAt: () => "2026-07-26T00:00:00.000Z",
        async sleep(seconds) {
          sleeps.push(seconds);
          now += seconds;
        },
      },
      emit: (progress) => emitted.push(progress),
    },
    contexts: [context],
    mode: "single",
    statusOnly,
    options: {
      interval: 60,
      sweepInterval: 300,
      timeout: 0,
      maxQueryErrors: 5,
      allowDraft: false,
      ...polling,
    },
  });
  return { verdict, sleeps, emitted };
}
