// Forked from warcraftcn/ui (https://github.com/TheOrcDev/warcraftcn-ui, MIT, see ./LICENSE.md) at 67dfa8e.
// Changes: only the default (gold rune) look, no faction variants; strict-TypeScript props, relative imports.

import type { ComponentProps, ReactElement } from "react";

import { cn } from "../../lib/cn.ts";

export const Skeleton = ({ className, ...props }: ComponentProps<"div">): ReactElement => (
  <div
    className={cn("fantasy relative overflow-hidden rounded-md wc-skeleton", className)}
    data-slot="skeleton"
    {...props}
  >
    <div className="wc-skeleton-icons" aria-hidden="true" />
    <div className="wc-skeleton-shimmer" aria-hidden="true" />
  </div>
);
