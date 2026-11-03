emoji_tsv = custom_target('emoji-data',
  input: [
    'unicode/emoji-test.txt',
    'unicode/cldr-en.xml',
    'unicode/cldr-en-derived.xml',
  ],
  output: 'emoji-data.tsv',
  command: [
    python, files('../build-aux/gen_emoji_data.py'),
    '--emoji-test', '@INPUT0@',
    '--cldr', '@INPUT1@',
    '--cldr', '@INPUT2@',
    '--output', '@OUTPUT@',
  ],
)

emozi_resources = gnome.compile_resources('emozi-resources',
  'emozi.gresource.xml',
  source_dir: [meson.current_source_dir(), meson.current_build_dir()],
  dependencies: emoji_tsv,
  c_name: 'emozi',
)

install_data('@0@.desktop'.format(app_id),
  install_dir: get_option('datadir') / 'applications')

# Desktops only read autostart entries from $XDG_CONFIG_DIRS (/etc/xdg), so a
# prefix-relative sysconfdir (/usr/local/etc) would never be seen.
autostart_sysconfdir = get_option('sysconfdir')
if not autostart_sysconfdir.startswith('/')
  autostart_sysconfdir = '/etc'
endif
install_data('@0@-autostart.desktop'.format(app_id),
  rename: '@0@.desktop'.format(app_id),
  install_dir: autostart_sysconfdir / 'xdg' / 'autostart')

install_data('icons/@0@.svg'.format(app_id),
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps')

gnome.post_install(gtk_update_icon_cache: true, update_desktop_database: true)
