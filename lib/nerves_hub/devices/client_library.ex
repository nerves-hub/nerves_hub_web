defmodule NervesHub.Devices.ClientLibrary do
  @moduledoc """
  Which client library a device connects with, read from the `User-Agent`
  header on its websocket upgrade.

  A client names itself with a product token, `<name>/<version>`:

      User-Agent: NHL/2.13.0

  Only the names listed here are recognised, each recorded as the library it
  stands for. Anything else is unknown and recorded as `nil` for both fields:
  no header, a name not listed here, or the default an HTTP stack sends when
  nothing is set (esp_websocket_client sends `ESP32 Websocket Client`). That
  keeps the columns to values that mean something, and keeps a
  `LowCardinality` column in ClickHouse from filling with whatever a device
  happens to send.

  The version must be SemVer. A listed name with any other version, or with
  none, records the library and leaves the version `nil`.

  See `docs/device_client_identification.md` for what clients send.
  """

  @libraries %{
    "NHL" => "nerves_hub_link",
    "nerves-hub-link-agent" => "nerves_hub_link_agent",
    "nerves-hub-link-esp32" => "nerves_hub_link_esp32",
    "nerves_hub_link_atomvm_esp32" => "nerves_hub_link_atomvm_esp32"
  }

  # Room for any real release, pre-release and build metadata included.
  @max_version_length 64

  @unknown %{lib: nil, lib_version: nil}

  @type t :: %{lib: String.t() | nil, lib_version: String.t() | nil}

  @doc """
  The client library and version a `User-Agent` header names.

  The first listed product token wins, so a client may follow its own token
  with others (its HTTP stack, say). Tokens inside a parenthesised comment are
  skipped: they describe something else, such as the platform the client runs
  on.

      iex> from_user_agent("NHL/2.13.0")
      %{lib: "nerves_hub_link", lib_version: "2.13.0"}

      iex> from_user_agent("ESP32 Websocket Client")
      %{lib: nil, lib_version: nil}
  """
  @spec from_user_agent(String.t() | nil) :: t()
  def from_user_agent(user_agent) when is_binary(user_agent) do
    user_agent
    |> strip_comments()
    |> String.split()
    |> Enum.find_value(@unknown, &known_product/1)
  end

  def from_user_agent(_user_agent), do: @unknown

  # Comments can nest, so innermost ones are removed until none are left.
  defp strip_comments(user_agent) do
    case Regex.replace(~r/\([^()]*\)/, user_agent, " ") do
      ^user_agent -> user_agent
      stripped -> strip_comments(stripped)
    end
  end

  defp known_product(token) do
    [name | version] = String.split(token, "/", parts: 2)

    case Map.fetch(@libraries, name) do
      {:ok, lib} -> %{lib: lib, lib_version: semver(version)}
      :error -> nil
    end
  end

  defp semver([version]) when byte_size(version) <= @max_version_length do
    case Version.parse(version) do
      {:ok, _version} -> version
      :error -> nil
    end
  end

  defp semver(_version), do: nil
end
