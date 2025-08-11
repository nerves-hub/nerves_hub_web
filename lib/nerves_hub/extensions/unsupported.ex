defmodule NervesHub.Extensions.Unsupported do
  @moduledoc """
  A noop extension.
  """

  def enabled?() do
    false
  end
end
