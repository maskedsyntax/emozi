conf = configuration_data()
conf.set_quoted('APP_ID', app_id)
conf.set_quoted('VERSION', meson.project_version())
build_config_h = configure_file(output: 'build-config.h', configuration: conf)

core_sources = files(
  'core/emoji.vala',
  'core/emoji-store.vala',
  'core/search.vala',
  'core/usage-store.vala',
  'core/config.vala',
)

emozi_sources = core_sources + files(
  'main.vala',
  'application.vala',
  'build-config.vapi',
  'core/coverage.vala',
  'ui/emoji-grid.vala',
  'ui/category-bar.vala',
  'ui/variant-popover.vala',
  'ui/picker-window.vala',
  'platform/caret-tracker.vala',
  'platform/positioner.vala',
  'platform/cinnamon-shortcut.vala',
  'platform/emozi-x11.vapi',
)

x11_helper_lib = static_library('emozi-x11', 'platform/emozi-x11.c',
  dependencies: [gtk_dep, gdk_x11_dep, x11_dep, xtst_dep],
  c_args: ['-Wall', '-Wextra', '-Wno-unused-parameter', '-Werror=implicit-function-declaration'],
  override_options: ['warning_level=2'],
)

executable('emozi',
  emozi_sources,
  emozi_resources,
  build_config_h,
  dependencies: [glib_dep, gobject_dep, gio_dep, gtk_dep, gdk_x11_dep, atspi_dep, m_dep],
  link_with: x11_helper_lib,
  include_directories: include_directories('platform'),
  vala_args: ['--target-glib=2.66'],
  install: true,
)
