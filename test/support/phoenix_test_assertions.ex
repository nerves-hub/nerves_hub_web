# PhoenixTest is a test-only dependency, but test/support is also compiled in dev.
if Code.ensure_loaded?(PhoenixTest) do
  defmodule NervesHub.Support.PhoenixTestAssertions do
    @moduledoc """
    `assert_has` and `refute_has` that raise on options PhoenixTest doesn't know.

    PhoenixTest silently ignores unknown options, so `with:` in place of `text:`
    leaves an assertion that only checks the selector matches something.
    """

    # the options documented for assert_has/3 and refute_has/3 in PhoenixTest 0.12.1
    @options [:at, :checked, :count, :exact, :label, :selected, :text, :timeout, :value]

    def assert_has(session, selector, opts_or_text) do
      PhoenixTest.assert_has(session, selector, validate_options!(opts_or_text))
    end

    def assert_has(session, selector, text, opts) do
      PhoenixTest.assert_has(session, selector, text, validate_options!(opts))
    end

    def refute_has(session, selector, opts_or_text) do
      PhoenixTest.refute_has(session, selector, validate_options!(opts_or_text))
    end

    def refute_has(session, selector, text, opts) do
      PhoenixTest.refute_has(session, selector, text, validate_options!(opts))
    end

    defp validate_options!(opts) when is_list(opts), do: Keyword.validate!(opts, @options)
    defp validate_options!(text), do: text
  end
end
