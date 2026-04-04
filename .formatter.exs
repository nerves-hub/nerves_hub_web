# Used by "mix format"
[
  heex_line_length: 200,
  import_deps: [:assert_eventually, :ecto],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{heex,ex,exs}"],
  plugins: [Phoenix.LiveView.HTMLFormatter, Quokka],
  attribute_formatters: %{class: CanonicalTailwind},
  quokka: [
    autosort: [:defstruct],
    exclude: [piped_functions: [:subquery]]
  ]
]
