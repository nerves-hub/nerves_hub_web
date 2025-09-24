# Used by "mix format"
[
  heex_line_length: 200,
  import_deps: [:assert_eventually],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{heex,ex,exs}"],
  plugins: [Phoenix.LiveView.HTMLFormatter, Quokka],
  quokka: [
    autosort: [:defstruct],
    only: [
      :blocks,
      :comment_directives,
      :configs,
      :defs,
      :deprecations,
      :pipes,
      :single_node
    ],
    exclude: [piped_functions: [:subquery]]
  ]
]
