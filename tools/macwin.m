// macwin — the macOS stand-in for the Xvfb tools (xshot/xclick/xmove).
// Drives one app window by pid, so proofs never touch other windows.
//
//   macwin wid   <pid>              print the pid's on-screen window id (0 if none)
//   macwin front <pid>              activate the app (key events go to its key window)
//   macwin keys  <pid> <text>       type text; \r Return, \e Escape, \b Backspace,
//                                   \U \D \L \R arrows
//   macwin click <pid> <x> <y>      left click at window-content point (x, y)
//   macwin move  <pid> <x> <y>      move the pointer to window-content point (x, y)
//
// Screenshots use the system tool: screencapture -x -o -l "$(macwin wid PID)" out.png
// Posting events needs Accessibility for the calling terminal; screencapture
// needs Screen Recording. macOS prompts for both on first use.
//
// Build: clang -fobjc-arc -framework AppKit -framework ApplicationServices \
//          tools/macwin.m -o build/macwin

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// US-layout virtual key codes, with the Shift flag where the char needs it.
typedef struct { char c; CGKeyCode k; int shift; } KeyMap;
static const KeyMap keymap[] = {
  {'a',0,0},{'s',1,0},{'d',2,0},{'f',3,0},{'h',4,0},{'g',5,0},{'z',6,0},{'x',7,0},
  {'c',8,0},{'v',9,0},{'b',11,0},{'q',12,0},{'w',13,0},{'e',14,0},{'r',15,0},
  {'y',16,0},{'t',17,0},{'1',18,0},{'2',19,0},{'3',20,0},{'4',21,0},{'6',22,0},
  {'5',23,0},{'=',24,0},{'9',25,0},{'7',26,0},{'-',27,0},{'8',28,0},{'0',29,0},
  {']',30,0},{'o',31,0},{'u',32,0},{'[',33,0},{'i',34,0},{'p',35,0},{'l',37,0},
  {'j',38,0},{'\'',39,0},{'k',40,0},{';',41,0},{'\\',42,0},{',',43,0},{'/',44,0},
  {'n',45,0},{'m',46,0},{'.',47,0},{'`',50,0},{' ',49,0},
  {'\r',36,0},{'\033',53,0},{'\b',51,0},{'\t',48,0},
  // Arrows ride on otherwise-unused control bytes (see the \U \D \L \R escapes).
  {'\x01',126,0},{'\x02',125,0},{'\x03',123,0},{'\x04',124,0},
  {'!',18,1},{'@',19,1},{'#',20,1},{'$',21,1},{'^',22,1},{'%',23,1},{'+',24,1},
  {'(',25,1},{'&',26,1},{'_',27,1},{'*',28,1},{')',29,1},{'}',30,1},{'{',33,1},
  {'"',39,1},{':',41,1},{'|',42,1},{'<',43,1},{'?',44,1},{'>',47,1},{'~',50,1},
};

static int lookup(char c, CGKeyCode* k, int* shift) {
  char lc = (c >= 'A' && c <= 'Z') ? c + 32 : c;
  for (size_t i = 0; i < sizeof keymap / sizeof *keymap; i++) {
    if (keymap[i].c == lc) {
      *k = keymap[i].k;
      *shift = keymap[i].shift || (c >= 'A' && c <= 'Z');
      return 1;
    }
  }
  return 0;
}

static NSDictionary* window_of(pid_t pid) {
  CFArrayRef list = CGWindowListCopyWindowInfo(
    kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
    kCGNullWindowID);
  NSDictionary* found = nil;
  for (NSDictionary* w in (__bridge NSArray*)list) {
    if ([w[(id)kCGWindowOwnerPID] intValue] == pid &&
        [w[(id)kCGWindowLayer] intValue] == 0) {
      found = w;
      break;
    }
  }
  if (list) CFRelease(list);
  return found;
}

static int front(pid_t pid) {
  NSRunningApplication* app =
    [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
  if (!app) return 0;
  [app activateWithOptions:NSApplicationActivateAllWindows];
  usleep(150000);
  return 1;
}

static void post_key(pid_t pid, CGKeyCode k, int shift) {
  CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
  if (shift) {
    CGEventRef sd = CGEventCreateKeyboardEvent(src, 56, true);
    CGEventPostToPid(pid, sd); CFRelease(sd);
  }
  CGEventRef d = CGEventCreateKeyboardEvent(src, k, true);
  CGEventRef u = CGEventCreateKeyboardEvent(src, k, false);
  if (shift) { CGEventSetFlags(d, kCGEventFlagMaskShift); CGEventSetFlags(u, kCGEventFlagMaskShift); }
  CGEventPostToPid(pid, d); usleep(20000);
  CGEventPostToPid(pid, u); usleep(20000);
  CFRelease(d); CFRelease(u);
  if (shift) {
    CGEventRef su = CGEventCreateKeyboardEvent(src, 56, false);
    CGEventPostToPid(pid, su); CFRelease(su);
  }
  if (src) CFRelease(src);
  usleep(40000);
}

// Window-content point -> global screen point. kCGWindowBounds is the
// frame including the title bar; the content sits below it.
static int to_screen(pid_t pid, double x, double y, CGPoint* out) {
  NSDictionary* w = window_of(pid);
  if (!w) return 0;
  CGRect b;
  CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)w[(id)kCGWindowBounds], &b);
  // Title bar height from the standard frame/content difference.
  NSRect fr = NSMakeRect(0, 0, 100, 100);
  NSRect cr = [NSWindow contentRectForFrameRect:fr
                                      styleMask:NSWindowStyleMaskTitled];
  double title = fr.size.height - cr.size.height;
  *out = CGPointMake(b.origin.x + x, b.origin.y + title + y);
  return 1;
}

static void post_mouse(pid_t pid, CGEventType t, CGPoint p) {
  CGEventRef e = CGEventCreateMouseEvent(NULL, t, p, kCGMouseButtonLeft);
  CGEventPost(kCGHIDEventTap, e);
  CFRelease(e);
  usleep(40000);
  (void)pid;
}

int main(int argc, char** argv) {
  @autoreleasepool {
    if (argc < 3) {
      fprintf(stderr, "usage: macwin wid|front|keys|click|move <pid> [...]\n");
      return 2;
    }
    const char* cmd = argv[1];
    pid_t pid = (pid_t)atoi(argv[2]);
    if (!strcmp(cmd, "wid")) {
      NSDictionary* w = window_of(pid);
      printf("%u\n", w ? [w[(id)kCGWindowNumber] unsignedIntValue] : 0);
      return w ? 0 : 1;
    }
    if (!strcmp(cmd, "front")) return front(pid) ? 0 : 1;
    if (!strcmp(cmd, "keys") && argc >= 4) {
      if (!AXIsProcessTrusted()) {
        fprintf(stderr, "macwin: this terminal lacks Accessibility permission "
                        "(System Settings > Privacy & Security > Accessibility)\n");
        return 3;
      }
      front(pid);
      const char* s = argv[3];
      for (size_t i = 0; s[i]; i++) {
        char c = s[i];
        if (c == '\\' && s[i+1]) {
          char n = s[++i];
          c = n == 'r' ? '\r' : n == 'e' ? '\033' : n == 'b' ? '\b' : n == 't' ? '\t'
            : n == 'U' ? '\x01' : n == 'D' ? '\x02' : n == 'L' ? '\x03' : n == 'R' ? '\x04' : n;
        }
        CGKeyCode k; int shift;
        if (!lookup(c, &k, &shift)) { fprintf(stderr, "macwin: no key for 0x%02x\n", c); return 4; }
        post_key(pid, k, shift);
      }
      return 0;
    }
    if ((!strcmp(cmd, "click") || !strcmp(cmd, "move")) && argc >= 5) {
      CGPoint p;
      front(pid);
      if (!to_screen(pid, atof(argv[3]), atof(argv[4]), &p)) return 1;
      post_mouse(pid, kCGEventMouseMoved, p);
      if (!strcmp(cmd, "click")) {
        post_mouse(pid, kCGEventLeftMouseDown, p);
        post_mouse(pid, kCGEventLeftMouseUp, p);
      }
      return 0;
    }
    fprintf(stderr, "macwin: bad command\n");
    return 2;
  }
}
