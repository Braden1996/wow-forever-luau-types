// Renders Luau type expressions and signatures to HTML strings with cross-links. Strings, not Astro components:
// the reference renders tens of thousands of tokens, and one string per signature keeps the build fast.

import type { TypeTarget } from "./catalog.ts";
import type { FunctionShape, Parameter } from "./type-expr.ts";
import { tokenize } from "./type-expr.ts";

export interface RenderContext {
  readonly resolve: (typeName: string) => TypeTarget | undefined;
  /** Adds the deploy base to a site path. */
  readonly href: (path: string) => string;
}

const ESCAPES: Readonly<Record<string, string>> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39;",
};

export function escapeHtml(text: string): string {
  return text.replaceAll(/[&<>"']/g, (char) => ESCAPES[char] ?? char);
}

export function symbolId(target: TypeTarget): string {
  return `${target.card}:${target.name}`;
}

export function typeHtml(expr: string, ctx: RenderContext): string {
  return tokenize(expr)
    .map((token) => {
      const text = escapeHtml(token.text);
      switch (token.kind) {
        case "type": {
          const target = ctx.resolve(token.text);
          if (target === undefined) {
            return `<span class="lt-type">${text}</span>`;
          }
          return `<a class="lt-ref" href="${escapeHtml(ctx.href(target.path))}" data-sym="${escapeHtml(symbolId(target))}">${text}</a>`;
        }
        case "builtin":
          return `<span class="lt-builtin">${text}</span>`;
        case "name":
          return `<span class="lt-name">${text}</span>`;
        case "string":
          return `<span class="lt-string">${text}</span>`;
        case "punct":
        case "space":
          return text;
      }
    })
    .join("");
}

function paramHtml(param: Parameter, ctx: RenderContext): string {
  if (param.variadic) {
    return `...${typeHtml(param.type, ctx)}`;
  }
  if (param.name === undefined) {
    return typeHtml(param.type, ctx);
  }
  return `<span class="lt-name">${escapeHtml(param.name)}</span>: ${typeHtml(param.type, ctx)}`;
}

const WRAP_AT = 88;

/** `function Name(a: T, b: U?): R`, wrapped one parameter per line when long. */
export function signatureHtml(name: string, shape: FunctionShape, ctx: RenderContext): string {
  const params = shape.params.map((param) => paramHtml(param, ctx));
  const plainLength =
    name.length +
    shape.returns.length +
    shape.params.reduce((total, param) => total + (param.name?.length ?? 0) + param.type.length + 4, 0);
  const generics = shape.generics === undefined ? "" : `&lt;${escapeHtml(shape.generics)}&gt;`;
  const list = plainLength > WRAP_AT && params.length > 1 ? `\n  ${params.join(",\n  ")},\n` : params.join(", ");
  return (
    `<span class="lt-kw">function</span> <span class="lt-fn">${escapeHtml(name)}</span>${generics}` +
    `(${list}): ${typeHtml(shape.returns, ctx)}`
  );
}

/** A field or value declaration: `name: T`. */
export function fieldHtml(name: string, type: string, ctx: RenderContext): string {
  return `<span class="lt-name">${escapeHtml(name)}</span>: ${typeHtml(type, ctx)}`;
}
