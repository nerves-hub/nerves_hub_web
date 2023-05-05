defmodule NervesHub.Tracer do
  use Spandex.Tracer, otp_app: :nerves_hub

  defoverridable start_span: 1, start_span: 2

  def start_span(name, opts \\ [])

  # Datadog's APM Deployment Tracking doesn't seem to work for span type=db, so
  # use custom instead for query
  def start_span("query", opts) do
    opts =
      if opts[:type] == :db do
        Keyword.replace(opts, :type, :custom)
      else
        opts
      end

    super("query", opts)
  end

  def start_span(name, opts), do: super(name, opts)
end
