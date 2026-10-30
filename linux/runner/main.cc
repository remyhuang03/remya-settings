#include "my_application.h"

#include <unistd.h>

int main(int argc, char** argv) {
  if (argc > 1 && g_strcmp0(argv[1], "--service") != 0) {
    g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
    g_autofree gchar* directory = g_path_get_dirname(executable);
    g_autofree gchar* cli = g_build_filename(directory, "libexec", "remya_settings_cli", nullptr);
    argv[0] = cli;
    execv(cli, argv);
    g_printerr("Unable to launch the bundled settings CLI. Rebuild or reinstall Remya Settings.\n");
    return 1;
  }
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
