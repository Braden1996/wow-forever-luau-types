/// <reference types="node" />

import { spawnSync } from "node:child_process";
import { realpathSync } from "node:fs";
import { dirname } from "node:path";
import process from "node:process";

// Uncached Sergeant actions run in a scratch directory with the workspace's node_modules linked in.
// These checks need the actual checkout for Git history, the installed workspace packages, or the upstream cache.
const cwd = dirname(realpathSync("node_modules"));
const [program, ...args] = process.argv.slice(2);
if (!program) {
  throw new Error("Expected a verification command.");
}
const result = spawnSync(program, args, { cwd, stdio: "inherit" });
if (result.error) {
  throw result.error;
}
process.exitCode = result.status ?? 1;
