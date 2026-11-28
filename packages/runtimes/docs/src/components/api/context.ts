// Server-side helpers shared by the API reference pages.

import type { Catalog } from "../../lib/api/catalog.ts";
import type { Coverage } from "../../lib/api/model.ts";
import type { RenderContext } from "../../lib/api/render.ts";
import { withBase } from "../../lib/site.ts";

export function renderContext(catalog: Catalog): RenderContext {
  return { resolve: (typeName) => catalog.resolve(typeName), href: withBase };
}

/** "typed (docs)", "untyped: no type source (FrameXML)", ... for a coverage entry. */
export function coverageLabel(coverage: Coverage | undefined): string {
  if (coverage === undefined) {
    return "declared";
  }
  if (coverage.status === "typed") {
    return coverage.source === undefined ? "typed" : `typed from ${coverage.source}`;
  }
  return coverage.reason === undefined ? coverage.status : `${coverage.status}: ${coverage.reason}`;
}

export const SOURCE_NAMES: Readonly<Record<string, string>> = {
  docs: "Blizzard_APIDocumentationGenerated",
  annotations: "vscode-wow-api annotations",
  client: "the client dump",
  generator: "the generator",
  supplements: "supplements/framexml.d.luau",
};
