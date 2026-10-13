export const COLUMNS = 6;
export const BREAKPOINT_PX = 768;

export function columnsFor(viewportWidth) {
  return viewportWidth < BREAKPOINT_PX ? 1 : COLUMNS;
}
