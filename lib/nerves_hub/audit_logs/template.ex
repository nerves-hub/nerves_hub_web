defmodule NervesHub.AuditLogs.Template do
  @moduledoc """
  An audit log description written with placeholders, such as
  `"%{actor} rebooted device %{resource}"`.

  An entry written from a template keeps the template and the values that fill
  it, as well as the plain `description` they make. A value is either text,
  stored as given, or a reference to a record (a user, API key, device,
  deployment group, firmware or archive), stored with the name it had when the entry was
  written.

  The web UI shows a reference under the record's current name and links to
  it, so an entry follows a renamed user or deployment group. The stored name
  is what it shows once the record is gone or the viewer can't see it, and
  what `description` holds, so the CSV export and older releases read the
  entry as before.

  `%{actor}` and `%{resource}` always name the entry's actor and resource; a
  template passes values for any other placeholder it uses.

  Placeholders are found in the template only, never in the values, so text a
  device sends (a failure reason) can't add a link or a reference.
  """

  alias NervesHub.Accounts.User
  alias NervesHub.Archives.Archive
  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareMetadata
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Products.ApiKey
  alias NervesHub.Products.Product

  @enforce_keys [:text]
  defstruct [:text, values: %{}]

  @type t :: %__MODULE__{text: String.t(), values: %{optional(atom()) => value()}}

  @typedoc "What a template is filled from when it is written."
  @type value ::
          String.t()
          | integer()
          | nil
          | User.t()
          | ApiKey.t()
          | Device.t()
          | DeploymentGroup.t()
          | Firmware.t()
          | FirmwareMetadata.t()
          | FirmwareMetadata.metadata()
          | Archive.t()
          | Product.t()

  @typedoc """
  A reference as an entry stores it. `id` is the record's id, or its UUID for
  firmware and archives, whose pages are found by UUID.
  """
  @type ref :: %{String.t() => String.t() | integer()}

  @typedoc "A value as an entry stores it."
  @type stored_value :: String.t() | ref()

  @placeholder ~r/%\{(\w+)\}/
  @implicit ["actor", "resource"]

  @doc """
  A template and the values for its placeholders, other than `%{actor}` and
  `%{resource}`.

  Raises if the template uses a placeholder it has no value for, which a test
  of the template that calls this catches.
  """
  @spec new(String.t(), keyword() | map()) :: t()
  def new(text, values \\ []) do
    values = Map.new(values)
    given = Enum.map(Map.keys(values), &Atom.to_string/1)

    case placeholders(text) -- (@implicit ++ given) do
      [] -> %__MODULE__{text: text, values: values}
      missing -> raise ArgumentError, "no value for #{Enum.map_join(missing, ", ", &"%{#{&1}}")} in #{inspect(text)}"
    end
  end

  @doc """
  The values an entry stores for `template`, keyed by placeholder, with the
  entry's actor and resource as `actor` and `resource`.
  """
  @spec dump_values(t(), struct(), struct()) :: %{String.t() => stored_value()}
  def dump_values(%__MODULE__{values: values}, actor, resource) do
    %{actor: actor, resource: resource}
    |> Map.merge(values)
    |> Map.new(fn {key, value} -> {to_string(key), dump_value(value)} end)
  end

  defp dump_value(nil), do: ""
  defp dump_value(value) when is_binary(value), do: value
  defp dump_value(value) when is_integer(value), do: Integer.to_string(value)
  defp dump_value(%User{} = user), do: reference("user", user.id, user.name)

  # An API key acting for a user isn't loaded again, so its stored name says
  # what it is, as the description always has.
  defp dump_value(%ApiKey{} = key), do: reference("api_key", key.id, "API key #{key.name}")

  defp dump_value(%Device{} = device), do: reference("device", device.id, device.identifier)
  defp dump_value(%DeploymentGroup{} = group), do: reference("deployment_group", group.id, group.name)
  defp dump_value(%Firmware{uuid: uuid}), do: reference("firmware", uuid, uuid)
  defp dump_value(%FirmwareMetadata{uuid: uuid}), do: reference("firmware", uuid, uuid)
  defp dump_value(%Archive{uuid: uuid}), do: reference("archive", uuid, uuid)

  # A product is the resource of a device move's entry in each product. Nothing
  # loads it again, so it shows the name it had.
  defp dump_value(%Product{} = product), do: reference("product", product.id, product.name)

  # Firmware metadata as `Firmwares.metadata_from_firmware/1` builds it, a
  # plain map, which is what a device holds right after an update.
  defp dump_value(%{uuid: uuid} = metadata) when is_binary(uuid) and not is_struct(metadata),
    do: reference("firmware", uuid, uuid)

  # Anything else interpolation would have taken (an atom, a float), as text,
  # so writing an entry never fails where an interpolated description didn't.
  defp dump_value(value), do: to_string(value)

  defp reference(type, id, name), do: %{"type" => type, "id" => id, "name" => name}

  @doc """
  Splits a template into its text and its placeholders, in order.

      iex> NervesHub.AuditLogs.Template.parse("%{actor} rebooted %{resource}")
      [{:placeholder, "actor"}, " rebooted ", {:placeholder, "resource"}]
  """
  @spec parse(String.t()) :: [String.t() | {:placeholder, String.t()}]
  def parse(text) do
    @placeholder
    |> Regex.split(text, include_captures: true, trim: true)
    |> Enum.map(fn part ->
      case Regex.run(@placeholder, part, capture: :all_but_first) do
        [name] when byte_size(name) + 3 == byte_size(part) -> {:placeholder, name}
        _ -> part
      end
    end)
  end

  @doc """
  The plain text of a template, with each reference under its stored name.

  A placeholder with no stored value is left as written.
  """
  @spec to_text(String.t(), %{String.t() => stored_value()}) :: String.t()
  def to_text(text, values) do
    text
    |> parse()
    |> Enum.map_join(fn
      {:placeholder, name} -> values |> Map.get(name) |> value_text(name)
      part -> part
    end)
  end

  defp value_text(%{"name" => name}, _placeholder), do: name
  defp value_text(text, _placeholder) when is_binary(text), do: text
  defp value_text(nil, placeholder), do: "%{#{placeholder}}"

  @doc """
  The `{type, id}` of every reference in `values`, the keys
  `NervesHub.AuditLogs.load_references/3` returns records under.
  """
  @spec reference_keys(%{String.t() => stored_value()} | nil) :: [{String.t(), String.t() | integer()}]
  def reference_keys(nil), do: []

  def reference_keys(values) do
    for {_placeholder, %{"type" => type, "id" => id}} <- values, do: {type, id}
  end

  defp placeholders(text) do
    @placeholder
    |> Regex.scan(text, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end
end
