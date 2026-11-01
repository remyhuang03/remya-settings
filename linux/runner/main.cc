#include "my_application.h"
#include <unistd.h>

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
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
  g_autofree gchar* directory = g_path_get_dirname(executable);
  if (argc > 1 && g_strcmp0(argv[1], "--gui") == 0) {
    prefer_integrated_gpu();
    g_autoptr(MyApplication) app = my_application_new();
    return g_application_run(G_APPLICATION(app), argc, argv);
  }
  g_autofree gchar* service = g_build_filename(directory, "libexec", "remya-settings-service", nullptr);
  if (argc > 1 && g_strcmp0(argv[1], "--service") == 0) {
#ifndef NDEBUG
    char* args[] = {service, const_cast<char*>("--debug-root"), const_cast<char*>(REMYA_REPOSITORY_DIR), nullptr};
#else
    char* args[] = {service, nullptr};
#endif
    execv(service, args);
  } else {
#ifndef NDEBUG
    // Debug launch activates the sibling bundle without installed D-Bus metadata.
    g_autoptr(GSubprocess) daemon = g_subprocess_new(G_SUBPROCESS_FLAGS_NONE, nullptr, service, "--debug-root", REMYA_REPOSITORY_DIR, nullptr);
    g_autoptr(GDBusConnection) bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
    for (int attempt = 0; bus != nullptr && attempt < 200; ++attempt) {
      g_autoptr(GVariant) reply = g_dbus_connection_call_sync(bus, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner", g_variant_new("(s)", "top.remya.settings.Service1"), G_VARIANT_TYPE("(b)"), G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, nullptr);
      gboolean ready = FALSE;
      if (reply != nullptr) g_variant_get(reply, "(b)", &ready);
      if (ready) break;
      g_usleep(10000);
    }
#endif
    g_autofree gchar* cli = g_build_filename(directory, "libexec", "remya_settings_cli", nullptr);
    if (argc == 1) {
      char* args[] = {cli, const_cast<char*>("open"), const_cast<char*>("home"), nullptr};
      execv(cli, args);
    } else { argv[0] = cli; execv(cli, argv); }
  }
  g_printerr("Unable to launch the Settings service or CLI. Rebuild or reinstall Settings.\n");
  return 1;
}
