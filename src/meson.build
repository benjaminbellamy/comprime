comprime_sources = files(
  'main.vala',
  'application.vala',
  'window.vala',
  'encoder.vala',
  'quality.vala',
)

comprime_resources = gnome.compile_resources(
  'comprime-resources',
  'comprime.gresource.xml',
  source_dir: meson.current_source_dir(),
  c_name: 'comprime',
)

comprime_deps = [
  dependency('glib-2.0', version: '>= 2.80'),
  dependency('gio-2.0', version: '>= 2.80'),
  dependency('gtk4', version: '>= 4.16'),
  dependency('libadwaita-1', version: '>= 1.6'),
]

executable('comprime',
  comprime_sources,
  comprime_resources,
  dependencies: comprime_deps,
  vala_args: ['--target-glib=2.80'],
  install: true,
)
