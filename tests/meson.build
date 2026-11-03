test_core = executable('test-core',
  core_sources + files('test-core.vala'),
  dependencies: [glib_dep, gobject_dep, gio_dep, m_dep],
)

test('core', test_core, args: [emoji_tsv], depends: emoji_tsv)

desktop_validate = find_program('desktop-file-validate', required: false)
if desktop_validate.found()
  foreach f : ['io.github.maskedsyntax.Emozi.desktop', 'io.github.maskedsyntax.Emozi-autostart.desktop']
    test('validate-' + f, desktop_validate, args: [meson.project_source_root() / 'data' / f])
  endforeach
endif
