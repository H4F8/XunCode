#include "my_application.h"
#include <flutter_linux/flutter_linux.h>

// This function demonstrates how to interact with a Flutter method channel in
// C++. It is currently a no-op and only exists to keep the template complete.
FLATTEN void fl_register_plugins(FlPluginRegistry* registry) {}

int main(int argc, char** argv) {
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
