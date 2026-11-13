#include "my_application.h"

// Settings needs no discrete GPU, and its drivers cost over 100 MB in every window.
// An explicit EGL vendor is kept, and so are machines where only NVIDIA can drive the
// display. Session-wide offload defaults would keep NVIDIA loaded, so they are replaced.
static void prefer_integrated_gpu() {
  constexpr const char* mesa = "/usr/share/glvnd/egl_vendor.d/50_mesa.json";
  if (g_getenv("__EGL_VENDOR_LIBRARY_FILENAMES") != nullptr || !g_file_test(mesa, G_FILE_TEST_EXISTS)) return;
  g_autoptr(GDir) cards = g_dir_open("/sys/class/drm", 0, nullptr);
  const gchar* name = nullptr;
  gboolean other_gpu = FALSE;
  while (cards != nullptr && (name = g_dir_read_name(cards)) != nullptr) {
    g_autofree gchar* path = g_build_filename("/sys/class/drm", name, "device", "vendor", nullptr);
    g_autofree gchar* vendor = nullptr;
    if (g_str_has_prefix(name, "card") && g_file_get_contents(path, &vendor, nullptr, nullptr) && !g_str_has_prefix(vendor, "0x10de")) {
      other_gpu = TRUE;
    }
  }
  if (!other_gpu) return;
  g_setenv("__EGL_VENDOR_LIBRARY_FILENAMES", mesa, TRUE);
  g_setenv("__GLX_VENDOR_LIBRARY_NAME", "mesa", TRUE);
  g_setenv("__NV_PRIME_RENDER_OFFLOAD", "0", TRUE);
}

int main(int argc, char** argv) {
  prefer_integrated_gpu();
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
