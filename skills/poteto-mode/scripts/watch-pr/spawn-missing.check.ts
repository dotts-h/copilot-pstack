import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { GhGitHubReader, WatcherQueryError } from "./github.ts";
import { GlabGitLabReader } from "./gitlab.ts";
import { parsePrNumber } from "./types.ts";

const empty = mkdtempSync(join(tmpdir(), "no-gh-"));
process.env.PATH = empty;
process.env.Path = empty;

async function expectSpawnFailed(
  binary: string,
  read: () => Promise<unknown>
): Promise<void> {
  try {
    await read();
    console.error(`missing ${binary} resolved instead of failing`);
    process.exit(1);
  } catch (error) {
    if (!(error instanceof WatcherQueryError)) {
      console.error("raw spawn error", error);
      process.exit(1);
    }
    if (
      error.failure.kind !== "spawn-failed" ||
      error.failure.retryable !== false
    ) {
      console.error("unexpected failure", error.failure);
      process.exit(1);
    }
    if (!error.failure.detail.includes(`${binary}: not found`)) {
      console.error("detail", error.failure.detail);
      process.exit(1);
    }
    console.log(`missing ${binary} returns spawn-failed`);
  }
}

await expectSpawnFailed("gh", () =>
  new GhGitHubReader().checksFastPath({
    owner: "owner",
    repo: "repo",
    number: parsePrNumber(1),
  })
);
await expectSpawnFailed("glab", () =>
  new GlabGitLabReader({
    origin: { owner: "group", repo: "project" },
  }).mergeRequest({
    owner: "group",
    repo: "project",
    number: parsePrNumber(1),
  })
);
