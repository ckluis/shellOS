// xclick: synthesize mouse clicks and key events on a named X11 window.
// Promoted from /tmp prototypes that drove the 2026-09-20 mouse/PTY proofs.
// Usage:
//   xclick <display> <window-name> click <x> <y>
//   xclick <display> <window-name> key <keysym-name>     (press + release)
//   xclick <display> <window-name> type <string>        (press + release per char)
// Keysym names: a-z 0-9, "space", "Return", "Escape", "bracketleft",
// "bracketright", "BackSpace", "Up", "Down", ...
// Build: gcc -O2 -o xclick xclick.c -lX11
#include <X11/Xlib.h>
#include <X11/keysym.h>
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

static void send_key_raw(Display *d, Window w, KeyCode kc, unsigned state, int is_press) {
  XEvent e;
  memset(&e, 0, sizeof(e));
  e.xkey.display = d;
  e.xkey.window = w;
  e.xkey.root = DefaultRootWindow(d);
  e.xkey.subwindow = None;
  e.xkey.time = CurrentTime;
  e.xkey.x = 1; e.xkey.y = 1;
  e.xkey.x_root = 1; e.xkey.y_root = 1;
  e.xkey.state = state;
  e.xkey.keycode = kc;
  e.xkey.same_screen = True;
  e.xkey.type = is_press ? KeyPress : KeyRelease;
  XSendEvent(d, w, True, is_press ? KeyPressMask : KeyReleaseMask, &e);
  XFlush(d);
  usleep(40000);
}

static void send_key(Display *d, Window w, KeySym ks) {
  KeyCode kc = XKeysymToKeycode(d, ks);
  if (kc == 0) { fprintf(stderr, "no keycode for keysym 0x%lx\n", (unsigned long)ks); return; }
  // Synthetic XSendEvent key events are translated client-side by
  // XLookupString, which reads the event's state field (not the live
  // modifier state). So a keysym on the shift level (plus, greater, ...)
  // only needs state=ShiftMask on its own press/release — do NOT emit a
  // separate Shift_L event: the app would see it as a printable key
  // (65536+keycode) and inject a spurious character into the terminal.
  int need_shift = (XKeycodeToKeysym(d, kc, 0) != ks);
  unsigned st = need_shift ? ShiftMask : 0;
  send_key_raw(d, w, kc, st, 1);
  send_key_raw(d, w, kc, st, 0);
}

// Map one ASCII char to a keysym name for XStringToKeysym.
static const char *char_keysym(char c, char out[2]) {
  if (c == ' ') return "space";
  if (c == '\n') return "Return";
  if (c == '[') return "bracketleft";
  if (c == ']') return "bracketright";
  if (c == '-') return "minus";
  if (c == '_') return "underscore";
  if (c == '.') return "period";
  if (c == '/') return "slash";
  out[0] = c; out[1] = '\0';
  return out;
}

int main(int argc, char **argv) {
  if (argc < 4) {
    fprintf(stderr, "usage: xclick <dpy> <name> click <x> <y> | key <keysym> | type <string>\n");
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
  if (strcmp(argv[3], "click") == 0 && argc >= 6) {
    int x = atoi(argv[4]), y = atoi(argv[5]);
    XWarpPointer(d, None, w, 0, 0, 0, 0, x, y);
    XFlush(d);
    usleep(200000);
    XEvent e;
    memset(&e, 0, sizeof(e));
    e.xbutton.type = ButtonPress;
    e.xbutton.display = d;
    e.xbutton.window = w;
    e.xbutton.root = DefaultRootWindow(d);
    e.xbutton.subwindow = None;
    e.xbutton.time = CurrentTime;
    e.xbutton.x = x; e.xbutton.y = y;
    e.xbutton.x_root = x; e.xbutton.y_root = y;
    e.xbutton.state = 0;
    e.xbutton.button = Button1;
    e.xbutton.same_screen = True;
    XSendEvent(d, w, True, ButtonPressMask, &e);
    XFlush(d);
    usleep(150000);
    e.xbutton.type = ButtonRelease;
    XSendEvent(d, w, True, ButtonReleaseMask, &e);
    XFlush(d);
    printf("clicked %d,%d on '%s'\n", x, y, argv[2]);
  } else if (strcmp(argv[3], "key") == 0 && argc >= 5) {
    send_key(d, w, XStringToKeysym(argv[4]));
    printf("key %s on '%s'\n", argv[4], argv[2]);
  } else if (strcmp(argv[3], "type") == 0 && argc >= 5) {
    const char *s = argv[4];
    for (size_t i = 0; s[i]; i++) {
      // ASCII printable 0x20-0x7e maps 1:1 to X11 keysyms (XK_space=0x20,
      // XK_greater=0x3e, ...). Do NOT route through XStringToKeysym: it
      // only accepts keysym NAMES ("greater") or alphanumerics, and
      // returns NoSymbol(0) for literal punctuation like ">" or "+".
      KeySym ks = (s[i] == '\n') ? XK_Return : (KeySym)(unsigned char)s[i];
      send_key(d, w, ks);
    }
    printf("typed %zu chars on '%s'\n", strlen(s), argv[2]);
  } else {
    fprintf(stderr, "bad args\n");
    return 2;
  }
  XCloseDisplay(d);
  return 0;
}
