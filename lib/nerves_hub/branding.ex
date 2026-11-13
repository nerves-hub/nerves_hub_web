defmodule NervesHub.Branding do
  @moduledoc """
  How this instance names itself to people.

  NervesHub is run under other names (NervesCloud, for one), so text that
  names the product to the people using it, such as Slack messages and the
  buttons on them, asks here rather than saying "NervesHub". Set with
  `FRIENDLY_PLATFORM_NAME`.
  """

  @doc "The name people know this instance by. `NervesHub` unless configured."
  @spec friendly_platform_name() :: String.t()
  def friendly_platform_name() do
    case Application.get_env(:nerves_hub, :friendly_platform_name) do
      name when is_binary(name) and name != "" -> name
      _ -> "NervesHub"
    end
  end
end
