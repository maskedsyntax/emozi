project('emozi', ['c', 'vala'],
  version: '0.1.0',
  license: 'MIT',
  meson_version: '>= 0.62.0',
  default_options: ['warning_level=1', 'buildtype=debugoptimized'],
)

app_id = 'io.github.maskedsyntax.Emozi'

gnome = import('gnome')
python = find_program('python3')

glib_dep = dependency('glib-2.0', version: '>= 2.66')
gobject_dep = dependency('gobject-2.0')
gio_dep = dependency('gio-2.0')
gtk_dep = dependency('gtk+-3.0', version: '>= 3.24')
gdk_x11_dep = dependency('gdk-x11-3.0')
x11_dep = dependency('x11')
xtst_dep = dependency('xtst')
atspi_dep = dependency('atspi-2')
m_dep = meson.get_compiler('c').find_library('m', required: false)

# Vala-generated C is noisy; keep our own C strict instead.
add_project_arguments('-w', '-DG_LOG_DOMAIN="emozi"', language: 'c')

subdir('data')
subdir('src')
subdir('tests')
