import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import {
  GITLAB_CONTEXT,
  GITLAB_ORIGIN,
  GLAB_MR,
  commandFixture,
  watchSingle,
} from "./fakes.test-helper.ts";
import { GhGitHubReader } from "./github.ts";
import { GlabGitLabReader } from "./gitlab.ts";
import { parsePrNumber } from "./types.ts";
import type { TerminalVerdict } from "./types.ts";

const empty = mkdtempSync(join(tmpdir(), "no-gh-"));
process.env.PATH = empty;
process.env.Path = empty;

function statusQuery(verdict: TerminalVerdict) {
  assert.equal(verdict.kind, "BLOCKER");
  assert.equal(verdict.exitCode, 7);
  assert.equal(verdict.blocker.kind, "status-query");
  return verdict.blocker;
}

for (const [binary, reader, context] of [
  ["glab", new GlabGitLabReader({ origin: GITLAB_ORIGIN }), GITLAB_CONTEXT],
  [
    "gh",
    new GhGitHubReader(),
    { owner: "owner", repo: "repo", number: parsePrNumber(1) },
  ],
] as const)
  test(`missing ${binary} ends a single watch at exit 7 without spending the retry budget`, async () => {
    const { verdict, emitted, sleeps } = await watchSingle(reader, context);
    const blocker = statusQuery(verdict);
    assert.equal(blocker.failures, 1, "retry budget stays unspent");
    assert.equal(blocker.failure.kind, "spawn-failed");
    assert.equal(blocker.failure.retryable, false);
    assert.equal(blocker.failure.detail, `${binary}: not found`);
    assert.deepEqual(emitted, [], "no RETRY verdict");
    assert.deepEqual(sleeps, [], "no retry sleep");
  });

test("a retryable glab failure spends the budget", async () => {
  const fixture = commandFixture([
    [GLAB_MR, [{ code: 1, stdout: "", stderr: "glab: 401 Unauthorized" }]],
  ]);
  const { verdict, emitted, sleeps } = await watchSingle(
    new GlabGitLabReader({ origin: GITLAB_ORIGIN, run: fixture.run }),
    GITLAB_CONTEXT,
    { maxQueryErrors: 3 }
  );
  assert.equal(emitted.length, 2, "two retries before the budget ends");
  for (const retry of emitted) {
    assert.equal(retry.kind, "RETRY");
    assert.equal(retry.failure.kind, "command-exit");
    assert.equal(retry.failure.retryable, true);
  }
  assert.deepEqual(sleeps, [60, 120]);
  const blocker = statusQuery(verdict);
  assert.equal(blocker.failures, 3);
  assert.equal(blocker.failure.kind, "command-exit");
  assert.deepEqual(fixture.calls, [GLAB_MR, GLAB_MR, GLAB_MR]);
});
