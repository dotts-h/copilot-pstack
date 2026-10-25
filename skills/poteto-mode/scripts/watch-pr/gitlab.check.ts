import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import {
  GITLAB_CONTEXT,
  GITLAB_MR_URL,
  GITLAB_ORIGIN,
  GITLAB_PIPELINE_URL,
  GLAB_DISCUSSIONS,
  GLAB_MR,
  commandFixture,
  mergeRequestBody,
  ok,
  pipelineBody,
  watchSingle,
} from "./fakes.test-helper.ts";
import {
  WatcherQueryError,
  resolveContext,
  type CommandRunner,
} from "./github.ts";
import { GlabGitLabReader, readerForRemote } from "./gitlab.ts";
import { readSnapshot, resolveWatchContexts } from "./policy.ts";
import { parsePrNumber } from "./types.ts";
import type { PollingOptions, PrNumber, TerminalVerdict } from "./types.ts";

const empty = mkdtempSync(join(tmpdir(), "no-glab-"));
process.env.PATH = empty;
process.env.Path = empty;

const CURRENT = ["glab", "mr", "view", "--output", "json"] as const;
const NO_DISCUSSIONS = [GLAB_DISCUSSIONS, [ok([])]] as const;
const CREATED_AT = "2026-07-26T00:00:00.000Z";

function note(
  overrides: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    id: 1,
    type: "DiffNote",
    body: "acknowledged",
    author: { username: "alice" },
    created_at: CREATED_AT,
    system: false,
    resolvable: true,
    resolved: true,
    position: {
      new_path: "src/a.ts",
      old_path: "src/a.ts",
      new_line: 12,
      old_line: 11,
    },
    ...overrides,
  };
}

function discussion(
  id: string,
  notes: readonly Record<string, unknown>[],
  individualNote = false
): Record<string, unknown> {
  return { id, individual_note: individualNote, notes };
}

const watchMr = (
  run: CommandRunner,
  polling: Partial<PollingOptions> = {},
  statusOnly = false
) =>
  watchSingle(
    new GlabGitLabReader({ origin: GITLAB_ORIGIN, run }),
    GITLAB_CONTEXT,
    polling,
    statusOnly
  );

function exitBlocker(verdict: TerminalVerdict, exitCode: number) {
  assert.equal(verdict.exitCode, exitCode);
  assert.equal(verdict.kind, "BLOCKER");
  return verdict.blocker;
}

function singlePr(verdict: TerminalVerdict) {
  assert.equal(verdict.kind, "READY");
  assert.equal(verdict.exitCode, 0);
  assert.equal(verdict.scope.kind, "single");
  return verdict.scope.pr;
}

async function expectRefused(
  mode: "stack" | "queued-stack",
  pr: PrNumber | null,
  stackPrs: readonly PrNumber[]
) {
  const fixture = commandFixture([]);
  await assert.rejects(
    () =>
      resolveWatchContexts({
        reader: new GlabGitLabReader({
          origin: GITLAB_ORIGIN,
          run: fixture.run,
        }),
        mode,
        owner: null,
        repo: null,
        pr,
        stackPrs,
      }),
    (error: unknown) => {
      assert.ok(error instanceof WatcherQueryError);
      assert.equal(error.failure.kind, "unsupported");
      assert.equal(error.failure.retryable, false);
      return true;
    }
  );
  assert.deepEqual(fixture.calls, []);
}

test("a remote is GitLab only when its host contains gitlab", async () => {
  const githubRemotes = [
    "https://github.com/org/gitlab-tools.git",
    "git@github.com:org/gitlab-tools.git",
    "ssh://git@github.com/org/gitlab-tools.git",
    "https://gitlab-bot@github.com/org/repo.git",
    "https://code.example.com/gitlab/group/project.git",
    "https://example.com/org/repo",
    null,
  ] as const;
  for (const remote of githubRemotes)
    assert.equal(
      readerForRemote(remote).forge,
      "github",
      remote ?? "(null remote)"
    );
  for (const [remote, origin] of [
    ["https://gitlab.com/group/sub/project.git", GITLAB_ORIGIN],
    ["git@gitlab.com:group/sub/project.git", GITLAB_ORIGIN],
    [
      "ssh://git@gitlab.corp.internal:2222/team/project.git",
      { owner: "team", repo: "project" },
    ],
    [
      "https://GitLab.Example.com/team/project",
      { owner: "team", repo: "project" },
    ],
  ] as const) {
    const reader = readerForRemote(remote);
    assert.equal(reader.forge, "gitlab", remote);
    assert.deepEqual(await reader.originRepo(), origin);
  }
});

test("github.com/org/gitlab-tools runs gh, not glab", async () => {
  for (const [remote, context, binary] of [
    [
      "https://github.com/org/gitlab-tools.git",
      { owner: "org", repo: "gitlab-tools", number: parsePrNumber(1) },
      "gh",
    ],
    ["git@gitlab.corp.internal:group/sub/project.git", GITLAB_CONTEXT, "glab"],
  ] as const)
    await assert.rejects(
      () =>
        readSnapshot({
          reader: readerForRemote(remote),
          context,
          pendingHistory: "include",
          allowDraft: false,
        }),
      (error: unknown) => {
        assert.ok(error instanceof WatcherQueryError);
        assert.equal(error.failure.kind, "spawn-failed");
        assert.equal(error.failure.detail, `${binary}: not found`);
        return true;
      }
    );
});

test("a clean merge request is READY", async () => {
  const fixture = commandFixture([
    [GLAB_MR, [ok(mergeRequestBody())]],
    [
      GLAB_DISCUSSIONS,
      [
        ok([
          discussion("disc-resolved", [note()]),
          discussion(
            "disc-system",
            [
              {
                id: 2,
                type: null,
                body: "changed the description",
                author: { username: "alice" },
                created_at: CREATED_AT,
                system: true,
                resolvable: false,
              },
            ],
            true
          ),
        ]),
      ],
    ],
  ]);
  const { verdict } = await watchMr(fixture.run);
  const pr = singlePr(verdict);
  assert.equal(pr.kind, "ready-pr");
  assert.equal(pr.proof.ci.source, "gitlab-head-pipeline");
  assert.deepEqual(
    pr.proof.ci.all.map((check) => ({
      kind: check.kind,
      name: check.name,
      reportedState: check.reportedState,
    })),
    [{ kind: "passed", name: "pipeline", reportedState: "SUCCESS" }]
  );
  assert.deepEqual(fixture.calls, [GLAB_MR, GLAB_DISCUSSIONS]);
});

test("unresolved discussions are the review-threads blocker", async () => {
  const fixture = commandFixture([
    [GLAB_MR, [ok(mergeRequestBody())]],
    [
      GLAB_DISCUSSIONS,
      [
        ok([
          discussion("disc-bugbot", [
            note({
              id: 11,
              body: "Null pointer on the empty input\nRUN_ID: run-1\n",
              author: { username: "bugbot" },
              resolved: false,
              position: {
                new_path: "src/a.ts",
                old_path: "src/a.ts.old",
                new_line: 12,
                old_line: 4,
              },
            }),
          ]),
          discussion("disc-removed-line", [
            note({
              id: 12,
              resolved: false,
              position: {
                new_path: "src/b.ts",
                old_path: "src/b.ts",
                new_line: null,
                old_line: 9,
              },
            }),
          ]),
          discussion("disc-general", [
            {
              id: 13,
              type: "DiscussionNote",
              body: "Please add a changelog entry",
              author: { username: "carol" },
              created_at: CREATED_AT,
              system: false,
              resolvable: true,
              resolved: false,
            },
          ]),
        ]),
      ],
    ],
  ]);
  const { verdict } = await watchMr(fixture.run);
  const blocker = exitBlocker(verdict, 3);
  assert.equal(blocker.kind, "review-threads");
  assert.deepEqual(blocker.threads, [
    {
      id: "disc-bugbot",
      firstComment: {
        authorLogin: "bugbot",
        body: "Null pointer on the empty input\nRUN_ID: run-1\n",
        path: "src/a.ts",
        line: 12,
        createdAt: CREATED_AT,
      },
      isBugbot: false,
      bugbotReviewPasses: 0,
    },
    {
      id: "disc-removed-line",
      firstComment: {
        authorLogin: "alice",
        body: "acknowledged",
        path: "src/b.ts",
        line: 9,
        createdAt: CREATED_AT,
      },
      isBugbot: false,
      bugbotReviewPasses: 0,
    },
    {
      id: "disc-general",
      firstComment: {
        authorLogin: "carol",
        body: "Please add a changelog entry",
        path: null,
        line: null,
        createdAt: CREATED_AT,
      },
      isBugbot: false,
      bugbotReviewPasses: 0,
    },
  ]);
});

test("a failed head pipeline is the failing-checks blocker", async () => {
  const fixture = commandFixture([
    [
      GLAB_MR,
      [
        ok(
          mergeRequestBody({
            head_pipeline: pipelineBody({ status: "failed" }),
          })
        ),
      ],
    ],
    NO_DISCUSSIONS,
  ]);
  const { verdict } = await watchMr(fixture.run);
  const blocker = exitBlocker(verdict, 4);
  assert.equal(blocker.kind, "failing-checks");
  assert.equal(blocker.ci.kind, "ci-failing");
  const [failed] = blocker.ci.failed;
  assert.equal(failed.name, "pipeline");
  assert.equal(failed.reportedState, "FAILED");
  assert.equal(failed.link, GITLAB_PIPELINE_URL);
});

test("canceled and manual pipelines are failing checks", async () => {
  for (const [status, reportedState] of [
    ["canceled", "CANCELED"],
    ["manual", "MANUAL"],
  ] as const) {
    const fixture = commandFixture([
      [
        GLAB_MR,
        [ok(mergeRequestBody({ head_pipeline: pipelineBody({ status }) }))],
      ],
      NO_DISCUSSIONS,
    ]);
    const { verdict } = await watchMr(fixture.run);
    const blocker = exitBlocker(verdict, 4);
    assert.equal(blocker.kind, "failing-checks", status);
    assert.equal(blocker.ci.kind, "ci-failing", status);
    assert.equal(blocker.ci.failed[0].reportedState, reportedState, status);
  }
});

test("a running pipeline waits, then becomes READY", async () => {
  const fixture = commandFixture([
    [
      GLAB_MR,
      [
        ok(
          mergeRequestBody({
            head_pipeline: pipelineBody({ status: "running" }),
          })
        ),
        ok(mergeRequestBody()),
      ],
    ],
    NO_DISCUSSIONS,
  ]);
  const { verdict, emitted, sleeps } = await watchMr(fixture.run);
  assert.equal(emitted.length, 1);
  const [waiting] = emitted;
  assert.equal(waiting.kind, "WAITING");
  assert.equal(waiting.reason.kind, "pending-checks");
  assert.equal(waiting.reason.pending[0].name, "pipeline");
  assert.deepEqual(sleeps, [60]);
  assert.equal(singlePr(verdict).kind, "ready-pr");
});

test("a head pipeline for an older commit retries, then becomes READY", async () => {
  const fixture = commandFixture([
    [
      GLAB_MR,
      [
        ok(
          mergeRequestBody({
            head_pipeline: pipelineBody({
              sha: "fedcba9876543210fedcba9876543210fedcba98",
            }),
          })
        ),
        ok(mergeRequestBody()),
      ],
    ],
    NO_DISCUSSIONS,
  ]);
  const { verdict, emitted, sleeps } = await watchMr(fixture.run);
  assert.equal(emitted.length, 1);
  const [retry] = emitted;
  assert.equal(retry.kind, "RETRY");
  assert.equal(retry.failure.kind, "checks-unavailable");
  assert.deepEqual(sleeps, [60]);
  assert.deepEqual(fixture.calls, [GLAB_MR, GLAB_MR, GLAB_DISCUSSIONS]);
  assert.equal(singlePr(verdict).kind, "ready-pr");
});

test("a merge request with no head pipeline fails closed at exit 7", async () => {
  const omitted = mergeRequestBody();
  delete omitted.head_pipeline;
  for (const body of [mergeRequestBody({ head_pipeline: null }), omitted]) {
    const fixture = commandFixture([[GLAB_MR, [ok(body)]]]);
    const { verdict, emitted, sleeps } = await watchMr(fixture.run, {
      maxQueryErrors: 2,
    });
    assert.equal(emitted.length, 1, "one retry then the budget ends");
    const [retry] = emitted;
    assert.equal(retry.kind, "RETRY");
    assert.equal(retry.failure.kind, "checks-unavailable");
    const blocker = exitBlocker(verdict, 7);
    assert.equal(blocker.kind, "status-query");
    assert.equal(blocker.failures, 2);
    assert.equal(blocker.failure.kind, "checks-unavailable");
    assert.deepEqual(sleeps, [60]);
    assert.deepEqual(fixture.calls, [GLAB_MR, GLAB_MR]);
  }
});

test("a merged merge request is READY", async () => {
  const fixture = commandFixture([
    [
      GLAB_MR,
      [ok(mergeRequestBody({ state: "merged", merged_at: CREATED_AT }))],
    ],
  ]);
  const { verdict } = await watchMr(fixture.run);
  assert.equal(singlePr(verdict).kind, "merged-pr");
  assert.deepEqual(fixture.calls, [GLAB_MR]);
});

test("a closed merge request is the merge-gate blocker", async () => {
  const fixture = commandFixture([
    [GLAB_MR, [ok(mergeRequestBody({ state: "closed" }))]],
  ]);
  const { verdict } = await watchMr(fixture.run);
  const blocker = exitBlocker(verdict, 6);
  assert.equal(blocker.kind, "merge-gate");
  assert.equal(blocker.reason, "closed-without-merge");
});

test("a draft merge request is the merge-gate blocker", async () => {
  const fixture = commandFixture([
    [
      GLAB_MR,
      [
        ok(
          mergeRequestBody({
            draft: true,
            detailed_merge_status: "draft_status",
          })
        ),
      ],
    ],
    NO_DISCUSSIONS,
  ]);
  const { verdict } = await watchMr(fixture.run);
  const blocker = exitBlocker(verdict, 6);
  assert.equal(blocker.kind, "merge-gate");
  assert.equal(blocker.reason, "draft-pr");
});

test("conflicts are the merge-conflicts blocker", async () => {
  const fixture = commandFixture([
    [
      GLAB_MR,
      [
        ok(
          mergeRequestBody({
            has_conflicts: true,
            detailed_merge_status: "conflict",
          })
        ),
      ],
    ],
    NO_DISCUSSIONS,
  ]);
  const { verdict } = await watchMr(fixture.run);
  assert.equal(exitBlocker(verdict, 2).kind, "merge-conflicts");
});

test("requested changes are the merge-gate blocker", async () => {
  const fixture = commandFixture([
    [
      GLAB_MR,
      [ok(mergeRequestBody({ detailed_merge_status: "requested_changes" }))],
    ],
    NO_DISCUSSIONS,
  ]);
  const { verdict } = await watchMr(fixture.run);
  const blocker = exitBlocker(verdict, 6);
  assert.equal(blocker.kind, "merge-gate");
  assert.equal(blocker.reason, "changes-requested");
});

test("an undocumented detailed_merge_status fails closed", async () => {
  const fixture = commandFixture([
    [
      GLAB_MR,
      [ok(mergeRequestBody({ detailed_merge_status: "future_status" }))],
    ],
  ]);
  const { verdict, emitted, sleeps } = await watchMr(fixture.run, {
    maxQueryErrors: 1,
  });
  assert.deepEqual(emitted, []);
  assert.deepEqual(sleeps, []);
  const blocker = exitBlocker(verdict, 7);
  assert.equal(blocker.kind, "status-query");
  assert.equal(blocker.failure.kind, "missing-key");
  assert.equal(blocker.failure.rawValue, '"future_status"');
});

test("status-only single mode returns STATUS", async () => {
  const fixture = commandFixture([
    [GLAB_MR, [ok(mergeRequestBody())]],
    NO_DISCUSSIONS,
  ]);
  const { verdict } = await watchMr(fixture.run, {}, true);
  assert.equal(verdict.kind, "STATUS");
  assert.equal(verdict.exitCode, 0);
  const [row] = verdict.rows;
  assert.equal(row.kind, "open");
  assert.equal(row.ci.source, "gitlab-head-pipeline");
});

test("the current-branch merge request resolves through glab mr view", async () => {
  const fixture = commandFixture([
    [CURRENT, [ok({ iid: 7, web_url: GITLAB_MR_URL })]],
  ]);
  assert.deepEqual(
    await resolveContext({
      reader: new GlabGitLabReader({ origin: GITLAB_ORIGIN, run: fixture.run }),
      owner: null,
      repo: null,
      pr: null,
    }),
    GITLAB_CONTEXT
  );
  assert.deepEqual(fixture.calls, [CURRENT]);

  const idle = commandFixture([]);
  assert.deepEqual(
    await resolveContext({
      reader: new GlabGitLabReader({ origin: GITLAB_ORIGIN, run: idle.run }),
      owner: null,
      repo: null,
      pr: parsePrNumber(7),
    }),
    GITLAB_CONTEXT
  );
  assert.deepEqual(idle.calls, []);
});

test("stack mode is refused before any read", () =>
  expectRefused("stack", null, []));

test("queued mode is refused before any read", async () => {
  await expectRefused("queued-stack", null, [
    parsePrNumber(7),
    parsePrNumber(8),
  ]);
  await expectRefused("queued-stack", parsePrNumber(7), []);
});
