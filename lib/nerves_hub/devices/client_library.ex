defmodule NervesHub.Devices.ClientLibrary do
  @moduledoc """
  Which client library a device connects with, read from the `User-Agent`
  header on its websocket upgrade.

  A client names itself with a product token, `<name>/<version>`:

      User-Agent: NHL/2.13.0

  The libraries listed here are recorded under a fixed name, whichever of their
  tokens a client sends: NervesHubLink is `nerves_hub_link` whether it sends
  `NHL` or `nerves_hub_link`.

  Any other client opts in by putting `custom:` in front of its name, and is
  recorded under that, prefix included: `custom:acme-link/1.4.0` is
  `custom:acme-link`. The prefix keeps what a client says about itself apart
  from the listed names. Without it, an unlisted token is skipped, which is
  what keeps out the defaults HTTP libraries send when the client sets no
  User-Agent: Mint's `mint/1.7.1`, which every NervesHubLink that doesn't send
  its own token sends, or `ESP32 Websocket Client`.

  The name after `custom:` can be at most 64 letters, digits, `.`, `_` and
  `-`, which keeps a `LowCardinality` column in ClickHouse to something like a
  list of clients.

  The version must be SemVer. Without one, the library is still recorded and
  the version is `nil`. A header that names no client is unknown, `nil` for
  both.

  See `docs/device_client_identification.md` for what clients send.
  """

  @libraries %{
    "NHL" => "nerves_hub_link",
    "nerves_hub_link" => "nerves_hub_link",
    "nerves-hub-link-agent" => "nerves_hub_link_agent",
    "nerves-hub-link-esp32" => "nerves_hub_link_esp32",
    "nerves_hub_link_atomvm_esp32" => "nerves_hub_link_atomvm_esp32"
  }

  @custom_prefix "custom:"

  @max_custom_name_length 64

  # Room for any real release, pre-release and build metadata included.
  @max_version_length 64

  @unknown %{lib: nil, lib_version: nil}

  @type t :: %{lib: String.t() | nil, lib_version: String.t() | nil}

  @doc """
  The client library and version a `User-Agent` header names.

  The first product token that names a client wins, listed or `custom:`, so a
  client puts its own token first and may follow it with others (its HTTP
  stack, say). Tokens inside a parenthesised comment are skipped: they describe
  something else, such as the platform the client runs on.

      iex> from_user_agent("NHL/2.13.0")
      %{lib: "nerves_hub_link", lib_version: "2.13.0"}

      iex> from_user_agent("custom:acme-link/1.4.0")
      %{lib: "custom:acme-link", lib_version: "1.4.0"}

      iex> from_user_agent("mint/1.7.1")
      %{lib: nil, lib_version: nil}
  """
  @spec from_user_agent(String.t() | nil) :: t()
  def from_user_agent(user_agent) when is_binary(user_agent) do
    user_agent
    |> strip_comments()
    |> String.split()
    |> Enum.find_value(@unknown, &library/1)
  end

  def from_user_agent(_user_agent), do: @unknown

  # Comments can nest, so innermost ones are removed until none are left.
  defp strip_comments(user_agent) do
    case Regex.replace(~r/\([^()]*\)/, user_agent, " ") do
      ^user_agent -> user_agent
      stripped -> strip_comments(stripped)
    end
  end

  defp library(token) do
    [name | version] = String.split(token, "/", parts: 2)

    case Map.fetch(@libraries, name) do
      {:ok, lib} -> %{lib: lib, lib_version: semver(version)}
      :error -> if custom_name?(name), do: %{lib: name, lib_version: semver(version)}
    end
  end

  defp custom_name?(@custom_prefix <> name) when byte_size(name) <= @max_custom_name_length,
    do: name =~ ~r/\A[A-Za-z0-9][A-Za-z0-9._-]*\z/

  defp custom_name?(_name), do: false

  defp semver([version]) when byte_size(version) <= @max_version_length do
    case Version.parse(version) do
      {:ok, _version} -> version
      :error -> nil
    end
  end

  defp semver(_version), do: nil
end
