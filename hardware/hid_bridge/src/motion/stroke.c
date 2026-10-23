// See stroke.h.
#include "stroke.h"
#include <math.h>

static double seglen(const int *pts, int i) {  // segment from point i-1 to point i
  return hypot(pts[2 * i] - pts[2 * i - 2], pts[2 * i + 1] - pts[2 * i - 1]);
}

void stroke_walk(const int *pts, int n, int step, stroke_emit emit, void *ctx) {
  if (n < 2 || step <= 0) return;
  double total = 0;
  for (int i = 1; i < n; i++) total += seglen(pts, i);
  int sx = pts[0], sy = pts[1];  // the position reported so far
  int seg = 1;
  double start = 0;  // distance along the stroke where segment `seg` begins
  for (double d = step; d < total; d += step) {
    while (seg < n - 1 && d > start + seglen(pts, seg)) start += seglen(pts, seg++);
    double len = seglen(pts, seg), t = len > 0 ? (d - start) / len : 1;
    int x = (int)lround(pts[2 * seg - 2] + (pts[2 * seg] - pts[2 * seg - 2]) * t);
    int y = (int)lround(pts[2 * seg - 1] + (pts[2 * seg + 1] - pts[2 * seg - 1]) * t);
    if (x != sx || y != sy) emit(x - sx, y - sy, ctx);
    sx = x;
    sy = y;
  }
  int ex = pts[2 * n - 2], ey = pts[2 * n - 1];
  if (ex != sx || ey != sy) emit(ex - sx, ey - sy, ctx);
}
