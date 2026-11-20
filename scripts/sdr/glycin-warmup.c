/* LD_PRELOAD shim for apps that load a GdkPixbuf from inside a GObject
 * class_init (e.g. Viking 1.11). With gdk-pixbuf >= 2.44 every decode goes
 * through glycin, whose worker threads then need GLib's type-init lock that
 * the main thread is holding, and the app hangs before showing a window.
 * Fix: right after gtk_init*(), load one tiny image so glycin finishes its own
 * type registration before the app's class_init runs. (It cannot be done in
 * a constructor: the dynamic loader's lock is held there.) */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <gtk/gtk.h>
static const guint8 png1x1[] = {
  0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a,0x00,0x00,0x00,0x0d,0x49,0x48,0x44,0x52,
  0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x06,0x00,0x00,0x00,0x1f,0x15,0xc4,
  0x89,0x00,0x00,0x00,0x0d,0x49,0x44,0x41,0x54,0x78,0x9c,0x63,0x60,0x60,0x60,0xf8,
  0x0f,0x00,0x01,0x04,0x01,0x00,0x5f,0xe5,0xc3,0x4b,0x00,0x00,0x00,0x00,0x49,0x45,
  0x4e,0x44,0xae,0x42,0x60,0x82 };
static void warmup(void) {
  static gboolean done;
  if (done) return;
  done = TRUE;
  GInputStream *s = g_memory_input_stream_new_from_data(png1x1, sizeof png1x1, NULL);
  GdkPixbuf *p = gdk_pixbuf_new_from_stream(s, NULL, NULL);
  if (p) g_object_unref(p);
  g_object_unref(s);
}
void gtk_init(int *argc, char ***argv) {
  void (*real)(int *, char ***) = dlsym(RTLD_NEXT, "gtk_init");
  real(argc, argv); warmup();
}
gboolean gtk_init_check(int *argc, char ***argv) {
  gboolean (*real)(int *, char ***) = dlsym(RTLD_NEXT, "gtk_init_check");
  gboolean r = real(argc, argv); warmup(); return r;
}
gboolean gtk_init_with_args(int *argc, char ***argv, const char *ps, const GOptionEntry *e, const char *td, GError **err) {
  gboolean (*real)(int *, char ***, const char *, const GOptionEntry *, const char *, GError **) = dlsym(RTLD_NEXT, "gtk_init_with_args");
  gboolean r = real(argc, argv, ps, e, td, err); warmup(); return r;
}
