// xshot: capture the root window to a PPM file.
// Promoted from the /tmp prototype used in the 2026-09-20 Xvfb proofs.
// Usage: xshot <display> <outfile.ppm>
// Build: gcc -O2 -o xshot xshot.c -lX11
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
  if (argc < 3) { fprintf(stderr, "usage: xshot <dpy> <out.ppm>\n"); return 2; }
  Display *d = XOpenDisplay(argv[1]);
  if (!d) { fprintf(stderr, "no display %s\n", argv[1]); return 1; }
  Window root = DefaultRootWindow(d);
  int w = DisplayWidth(d, DefaultScreen(d));
  int h = DisplayHeight(d, DefaultScreen(d));
  XImage *img = XGetImage(d, root, 0, 0, w, h, AllPlanes, ZPixmap);
  if (!img) { fprintf(stderr, "XGetImage failed\n"); return 1; }
  FILE *f = fopen(argv[2], "wb");
  if (!f) { perror("fopen"); return 1; }
  fprintf(f, "P6\n%d %d\n255\n", w, h);
  for (int y = 0; y < h; y++)
    for (int x = 0; x < w; x++) {
      unsigned long p = XGetPixel(img, x, y);
      unsigned char rgb[3] = {
        (p >> 16) & 0xff, (p >> 8) & 0xff, p & 0xff};
      fwrite(rgb, 1, 3, f);
    }
  fclose(f);
  printf("shot %dx%d -> %s\n", w, h, argv[2]);
  XDestroyImage(img);
  XCloseDisplay(d);
  return 0;
}
