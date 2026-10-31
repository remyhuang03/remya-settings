#include "my_application.h"
#include <unistd.h>

int main(int argc, char** argv) {
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
  g_autofree gchar* directory = g_path_get_dirname(executable);
  if (argc > 1 && g_strcmp0(argv[1], "--gui") == 0) {
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
