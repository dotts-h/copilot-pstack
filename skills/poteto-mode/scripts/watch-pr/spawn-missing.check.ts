import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { GhGitHubReader, WatcherQueryError } from "./github.ts";
import { parsePrNumber } from "./types.ts";

const empty = mkdtempSync(join(tmpdir(), "no-gh-"));
process.env.PATH = empty;
process.env.Path = empty;

const reader = new GhGitHubReader();
try {
  await reader.checksFastPath({
    owner: "owner",
    repo: "repo",
    number: parsePrNumber(1),
  });
  console.error("missing gh resolved instead of failing");
  process.exit(1);
} catch (error) {
  if (!(error instanceof WatcherQueryError)) {
    console.error("raw spawn error", error);
    process.exit(1);
  }
  if (error.failure.kind !== "spawn-failed" || error.failure.retryable !== false) {
    console.error("unexpected failure", error.failure);
    process.exit(1);
  }
  if (!error.failure.detail.includes("gh: not found")) {
    console.error("detail", error.failure.detail);
    process.exit(1);
  }
  console.log("missing gh returns spawn-failed");
}
