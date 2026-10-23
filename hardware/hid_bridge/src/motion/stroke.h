// Pointer motion at a constant speed: every HID report moves the same distance along the stroke, so iOS's
// speed-dependent pointer gain is the same for every part of a move and distance is linear in units.
// (Capping each axis on its own made diagonal reports faster than straight ones, so x and y were scaled
// differently depending on the other axis.)
#pragma once
#ifdef __cplusplus
extern "C" {
#endif

typedef void (*stroke_emit)(int dx, int dy, void *ctx);

// pts: n points (x0 y0 x1 y1 ...) in units; reports walk from pts[0] through each point to the last, `step`
// units apart along the way (the last one shorter). Their sum is exactly the last point minus the first.
void stroke_walk(const int *pts, int n, int step, stroke_emit emit, void *ctx);

#ifdef __cplusplus
}
#endif
