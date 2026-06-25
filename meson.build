project('comprime', ['vala', 'c'],
  version: '1.0.0',
  meson_version: '>= 1.0.0',
  license: 'GPL-3.0-or-later',
)

app_id = 'fr.benjaminbellamy.comprime'

dependency('glib-2.0', version: '>= 2.80')
dependency('gtk4', version: '>= 4.16')
dependency('libadwaita-1', version: '>= 1.6')

gnome = import('gnome')
i18n = import('i18n')

subdir('data')
subdir('src')

gnome.post_install(
  glib_compile_schemas: true,
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)
