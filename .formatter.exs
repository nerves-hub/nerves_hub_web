# Used by "mix format"
[
  heex_line_length: 200,
  import_deps: [:assert_eventually],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{heex,ex,exs}"],
  plugins: [Phoenix.LiveView.HTMLFormatter, Quokka],
  quokka: [
    only: [
      :defs
    ]
  ]
]
