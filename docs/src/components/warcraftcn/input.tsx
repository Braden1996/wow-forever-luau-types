// Forked from warcraftcn/ui (https://github.com/TheOrcDev/warcraftcn-ui, MIT, see ./LICENSE.md) at 67dfa8e.
// Changes: strict-TypeScript props, relative imports; styles come from ./warcraft.css via the global stylesheet.

import type { ComponentProps, ReactElement } from "react";

import { cn } from "../../lib/cn.ts";

export const Input = ({ className, type, ...props }: ComponentProps<"input">): ReactElement => (
  <input
    className={cn(
      "fantasy min-w-0 bg-center bg-cover bg-no-repeat p-3 text-base shadow-xs outline-none transition-[color,box-shadow] placeholder:text-muted-foreground disabled:pointer-events-none disabled:cursor-not-allowed disabled:opacity-50 md:text-sm",
      "border-solid wc-input-border [border-image-repeat:stretch]",
      "border-6 [border-image-slice:16_fill]",
      className,
    )}
    data-slot="input"
    type={type}
    {...props}
  />
);
