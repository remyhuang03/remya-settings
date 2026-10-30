#include "my_application.h"

#include <flutter_linux/flutter_linux.h>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  gboolean service_mode;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  if (!self->service_mode) gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GList* windows = gtk_application_get_windows(GTK_APPLICATION(self));
  GtkWindow* existing = windows == nullptr ? nullptr : GTK_WINDOW(windows->data);
  if (existing != nullptr) {
    self->service_mode = FALSE;
    gtk_window_present(existing);
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Flutter draws the title bar; the compositor still owns window placement.
  gtk_window_set_title(window, "Remy'a Settings");
  gtk_window_set_decorated(window, FALSE);
  g_signal_connect(window, "delete-event", G_CALLBACK(gtk_widget_hide_on_delete), nullptr);

  gtk_window_set_default_size(window, 1280, 720);
  GdkGeometry geometry = {};
  geometry.min_width = 1000;
  gtk_window_set_geometry_hints(window, nullptr, &geometry, GDK_HINT_MIN_SIZE);

  // Resolve the bundled icon independently of the caller's working directory.
  g_autofree gchar* executable_path = g_file_read_link("/proc/self/exe", nullptr);
  if (executable_path != nullptr) {
    g_autofree gchar* executable_dir = g_path_get_dirname(executable_path);
    g_autofree gchar* icon_path = g_build_filename(
        executable_dir, "data", "flutter_assets", "assets", "icons",
        "settings.png", nullptr);
    g_autoptr(GError) icon_error = nullptr;
    if (!gtk_window_set_icon_from_file(window, icon_path, &icon_error)) {
      g_warning("Failed to load application icon: %s", icon_error->message);
    }
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  g_autoptr(FlStandardMethodCodec) paths_codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) paths_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), "top.remya.paths",
      FL_METHOD_CODEC(paths_codec));
  fl_method_channel_set_method_call_handler(
      paths_channel,
      [](FlMethodChannel* channel, FlMethodCall* call, gpointer data) {
        if (g_strcmp0(fl_method_call_get_name(call), "repositoryDirectory") == 0) {
          g_autoptr(FlValue) root = fl_value_new_string(REMYA_REPOSITORY_DIR);
          fl_method_call_respond_success(call, root, nullptr);
        } else if (g_strcmp0(fl_method_call_get_name(call), "show") == 0) {
          my_application_activate(G_APPLICATION(data));
          fl_method_call_respond_success(call, nullptr, nullptr);
        } else if (g_strcmp0(fl_method_call_get_name(call), "quit") == 0) {
          fl_method_call_respond_success(call, nullptr, nullptr);
          g_application_quit(G_APPLICATION(data));
        } else {
          fl_method_call_respond_not_implemented(call, nullptr);
        }
      },
      self, nullptr);

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  if (!self->service_mode) gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);
  self->service_mode = g_strv_contains(*arguments, "--service");

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  if (!g_application_get_is_remote(application)) {
    g_application_hold(application);
    g_application_activate(application);
  } else if (!self->service_mode) {
    g_application_activate(application);
  }
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_DEFAULT_FLAGS, nullptr));
}
