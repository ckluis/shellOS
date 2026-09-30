// xmove: move the mouse pointer over a named X11 window (no click, no keys).
//   xmove <display> <window-name> <x> <y>
// Used by the Xvfb regression gate for hover-state tests: hovering a theme
// button must change the frame (highlight) without any click, and moving
// away must restore the resting frame.
// Build: gcc -O2 -o xmove xmove.c -lX11
#include <X11/Xlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static Window find_named(Display *d, Window root, const char *name) {
  Window r, p, *kids = NULL;
  unsigned nk = 0;
  char *wn = NULL;
  Window found = 0;
  if (XQueryTree(d, root, &r, &p, &kids, &nk)) {
    for (unsigned i = 0; i < nk && !found; i++) {
      if (XFetchName(d, kids[i], &wn) && wn) {
        if (strcmp(wn, name) == 0) found = kids[i];
        XFree(wn);
      }
      if (!found) found = find_named(d, kids[i], name);
    }
    if (kids) XFree(kids);
  }
  return found;
}

int main(int argc, char **argv) {
  if (argc < 5) {
    fprintf(stderr, "usage: xmove <dpy> <name> <x> <y>\n");
    return 2;
  }
  Display *d = XOpenDisplay(argv[1]);
  if (!d) { fprintf(stderr, "no display %s\n", argv[1]); return 1; }
  Window w = find_named(d, DefaultRootWindow(d), argv[2]);
  if (!w) { fprintf(stderr, "window '%s' not found\n", argv[2]); return 1; }
  XRaiseWindow(d, w);
  XSetInputFocus(d, w, RevertToParent, CurrentTime);
  XFlush(d);
  usleep(200000);
  int x = atoi(argv[3]), y = atoi(argv[4]);
  XWarpPointer(d, None, w, 0, 0, 0, 0, x, y);
  XFlush(d);
  usleep(300000);
  printf("moved to %d,%d on '%s'\n", x, y, argv[2]);
  return 0;
}
