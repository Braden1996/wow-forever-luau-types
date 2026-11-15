// The in-browser type checker: Luau's analysis library compiled to WebAssembly (@luau-rs/luau), run in a Web
// Worker with the generated definitions loaded. No server: the WASM and the definitions are static files.

import type { AnalysisDiagnostic, AnalysisPosition, AutocompleteEntry } from "@luau-rs/luau/analysis/worker";

import { AnalysisWorker } from "@luau-rs/luau/analysis/worker";

import { withBase } from "../../lib/site.ts";

export const MODULE = "main.luau";

export interface Checker {
  check(source: string): Promise<readonly AnalysisDiagnostic[]>;
  typeAt(source: string, position: AnalysisPosition): Promise<string | undefined>;
  complete(source: string, position: AnalysisPosition): Promise<readonly AutocompleteEntry[]>;
  dispose(): void;
}

/** Downloads the definitions (about 2 MB, cached by the browser) and starts the worker. */
export async function createChecker(): Promise<Checker> {
  const response = await fetch(withBase("/playground/wow-forever.d.luau"));
  if (!response.ok) {
    throw new Error(`definitions: HTTP ${response.status}`);
  }
  const definitions = await response.text();
  const worker = new AnalysisWorker({ mode: "strict", lint: false });
  worker.addDefinition("@wow", definitions);
  let current: string | undefined;
  // The worker answers one query at a time: queue them so a hover never overlaps a check.
  let queue: Promise<unknown> = Promise.resolve();
  const run = <T,>(source: string, query: () => Promise<T>): Promise<T> => {
    const next = queue.then(async () => {
      if (source !== current) {
        worker.setModule(MODULE, source);
        current = source;
      }
      return query();
    });
    queue = next.catch(() => undefined);
    return next;
  };
  return {
    check: async (source) => (await run(source, async () => worker.check(MODULE))).diagnostics,
    typeAt: async (source, position) => run(source, async () => worker.typeAt(MODULE, position)),
    complete: async (source, position) =>
      (await run(source, async () => worker.autocomplete(MODULE, position))).entries,
    dispose() {
      worker.terminate();
    },
  };
}
