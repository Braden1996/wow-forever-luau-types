// The Expressive Code plugin that turns every ```luau block into a checked, hoverable example (see snippets.ts).
//
// Each identifier is wrapped at build time; the page's HoverCards island shows the card:
// - an API symbol (a global function, a namespace and its members, a type the reference has a page for) becomes a
//   link with `data-sym`, so it opens the same card as the API reference's links;
// - anything else gets `data-luau-type`, the type the checker inferred (for a type function such as
//   `EventHandler<"ADDON_LOADED">`, what it resolves to);
// - a line marked `-- error` has its error underlined, with the message in `data-luau-error`.

import type { AnnotationRenderOptions } from "@astrojs/starlight/expressive-code";
import type { Diagnostic, Hover } from "luau-web-checker";
import { definePlugin, ExpressiveCodeAnnotation } from "@astrojs/starlight/expressive-code";
import { h } from "@astrojs/starlight/expressive-code/hast";

import type { Catalog } from "../api/catalog.ts";
import { loadCatalog } from "../api/load.ts";
import { apiPaths } from "../api/paths.ts";
import { buildChecker } from "./build-checker.ts";
import { checkSnippet, isDefinitionsFile } from "./snippets.ts";

const LANGUAGES: ReadonlySet<string> = new Set(["luau"]);

interface SymbolLink {
  readonly path: string;
  readonly sym: string;
}

type Nodes = ReturnType<ExpressiveCodeAnnotation["render"]>;

class LuauHoverAnnotation extends ExpressiveCodeAnnotation {
  override readonly name = "luau-hover";
  readonly #label: string;
  readonly #link: SymbolLink | undefined;
  readonly #base: string;

  constructor(hover: Hover, label: string, link: SymbolLink | undefined, base: string) {
    super({ inlineRange: { columnStart: hover.column - 1, columnEnd: hover.endColumn - 1 } });
    this.#label = label;
    this.#link = link;
    this.#base = base;
  }

  render({ nodesToTransform }: AnnotationRenderOptions): Nodes {
    const link = this.#link;
    return nodesToTransform.map((node) =>
      link === undefined
        ? h("span.luau-hover", { "data-luau-type": this.#label, tabindex: 0 }, [node])
        : h("a.luau-sym", { href: `${this.#base}${link.path}`, "data-sym": link.sym }, [node]),
    );
  }
}

class LuauErrorAnnotation extends ExpressiveCodeAnnotation {
  override readonly name = "luau-error";
  readonly #message: string;

  constructor(error: Diagnostic, lineText: string) {
    // A multi-line range is underlined on its first line only, up to the trailing `-- error` comment.
    const comment = lineText.search(/\s*--/u);
    const codeEnd = comment > error.column - 1 ? comment : lineText.length;
    const end = error.endLine === error.line ? Math.min(error.endColumn - 1, codeEnd) : codeEnd;
    const start = Math.min(error.column - 1, Math.max(lineText.length - 1, 0));
    super({ inlineRange: { columnStart: start, columnEnd: Math.max(end, start + 1) } });
    this.#message = `${error.kind}: ${error.message}`;
  }

  render({ nodesToTransform }: AnnotationRenderOptions): Nodes {
    return nodesToTransform.map((node) =>
      h("span.luau-error", { "data-luau-error": this.#message, tabindex: 0 }, [node]),
    );
  }
}

/** The API page and hover card for an identifier, when the reference has one. */
export function symbolLink(catalog: Catalog, hover: Hover, previous: Hover | undefined): SymbolLink | undefined {
  switch (hover.kind) {
    case "global": {
      if (catalog.namespaces.has(hover.name)) {
        return { path: apiPaths.namespace(hover.name), sym: `namespace:${hover.name}` };
      }
      if (catalog.parsed.functions.some((fn) => fn.name === hover.name)) {
        return { path: apiPaths.global(hover.name), sym: `global:${hover.name}` };
      }
      return undefined;
    }
    case "property": {
      // `C_Item.GetItemInfo`: a member of a namespace, right after `C_Item.`.
      const ns = previous?.kind === "global" && previous.endColumn + 1 === hover.column ? previous.name : undefined;
      if (
        ns !== undefined &&
        previous?.line === hover.line &&
        catalog.namespaces.get(ns)?.members.some((member) => member.name === hover.name) === true
      ) {
        return { path: `${apiPaths.namespace(ns)}#${hover.name}`, sym: `namespace:${ns}` };
      }
      return undefined;
    }
    case "type": {
      // A type that is its own name (`Frame`) opens its reference card; one that expands (`EventHandler<"X">`
      // resolves to a function type) shows the expansion instead, which is the more useful answer there.
      const target = hover.type === hover.name ? catalog.resolve(hover.name) : undefined;
      return target === undefined ? undefined : { path: target.path, sym: `${target.card}:${target.name}` };
    }
    case "local":
      return undefined;
  }
}

export function hoverLabel(hover: Hover): string {
  switch (hover.kind) {
    case "local":
      return `local ${hover.name}: ${hover.type}`;
    case "global":
      return `${hover.name}: ${hover.type}`;
    case "property":
      return `.${hover.name}: ${hover.type}`;
    case "type":
      return hover.type === hover.name ? `type ${hover.name}` : `type ${hover.name} = ${hover.type}`;
  }
}

/**
 * @param base The site's base path without a trailing slash (`/wow-forever-luau-types`), prefixed to API links.
 */
export function pluginLuauTypes(base: string): ReturnType<typeof definePlugin> {
  let blocks = 0;
  return definePlugin({
    name: "luau-types",
    baseStyles: `
      .luau-hover, .luau-sym { cursor: help; text-decoration: none; color: inherit; }
      .luau-hover:hover, .luau-hover:focus-visible, .luau-sym:hover, .luau-sym:focus-visible {
        text-decoration: underline dotted; text-underline-offset: 3px;
      }
      .luau-error {
        text-decoration: underline wavy #f85149; text-decoration-skip-ink: none; text-underline-offset: 3px;
        cursor: help;
      }
    `,
    hooks: {
      async preprocessCode({ codeBlock }) {
        if (
          !LANGUAGES.has(codeBlock.language) ||
          codeBlock.metaOptions.getBoolean("nocheck") === true ||
          isDefinitionsFile(codeBlock.code)
        ) {
          return;
        }
        blocks += 1;
        const checker = await buildChecker();
        const catalog = loadCatalog();
        const checked = checkSnippet(checker, `snippet${String(blocks)}.luau`, codeBlock.code);

        if (checked.hidden > 0) {
          codeBlock.deleteLines(Array.from({ length: checked.hidden }, (_, index) => index));
        }

        let previous: Hover | undefined;
        for (const hover of checked.hovers) {
          const line = codeBlock.getLine(hover.line - 1);
          const link = symbolLink(catalog, hover, previous);
          // A builtin type name (`number`) says nothing more on hover; leave it plain.
          const trivial = hover.kind === "type" && link === undefined && hover.type === hover.name;
          if (line !== undefined && hover.endLine === hover.line && !trivial) {
            line.addAnnotation(new LuauHoverAnnotation(hover, hoverLabel(hover), link, base));
          }
          previous = hover;
        }
        for (const error of checked.errors) {
          const line = codeBlock.getLine(error.line - 1);
          if (line !== undefined) {
            line.addAnnotation(new LuauErrorAnnotation(error, line.text));
          }
        }
      },
    },
  });
}
