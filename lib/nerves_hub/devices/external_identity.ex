defmodule NervesHub.Devices.ExternalIdentity do
  @moduledoc """
  An identity a device holds on a network that NervesHub does not operate.

  Devices increasingly reach the outside world over something other than their
  NervesHub socket — an iroh endpoint, a NetBird or Tailscale peer, a plain
  WireGuard interface. Those networks each name a device by a long-lived public
  key, and each keeps *where* the device currently is (endpoint addresses, relay
  assignment) separate and changeable. This schema records that pairing so an
  operator can see, and act on, a device's identity elsewhere.

  ## What `identifier` means

  `identifier` is **the value the device cryptographically proves possession
  of** — its iroh endpoint id, or its WireGuard/NetBird/Tailscale public key.

  It is deliberately not "whatever handle that service's UI shows you".
  Control-plane handles (a NetBird peer id, a Tailscale `StableNodeID`, an
  assigned overlay IP) can be reassigned and belong in `details`. Keeping
  `identifier` to the proven key is what lets it be matched against a peer that
  has just completed a handshake, which is the point of storing it.

  ## `details`

  Free-form, per-service, and expected to change: relay URLs, an assigned IP, a
  connection ticket. Nothing in here is authoritative and nothing in here should
  ever be a secret — this is an identity record, not a credential store.

  ## `service` and `instance`

  These answer two different questions, and it is worth keeping them apart.

  `service` is the *protocol* — iroh, WireGuard, and so on. It decides how the
  identifier should be read and what the details mean.

  `instance` is *which endpoint of that protocol on this device*. A device can
  run two iroh endpoints — a console and an application, say — each holding its
  own key. WireGuard has the same shape with `wg0` and `wg1`. Most services are
  singletons and stay on `"default"`.

  Telling them apart by `identifier` instead does not work: an endpoint whose key
  is rotated would insert a second row rather than update the first, and the dead
  key would linger forever with nothing marking it stale. A discriminator has to
  be stable, which rules out the value being tracked.

  ## Uniqueness

  Two unique indexes back this table:

    * `(device_id, service, instance)` — one identity per endpoint, so "this
      device's iroh console ticket" has exactly one answer.
    * `(service, identifier)` — two devices cannot claim the same key, and one
      device cannot report the same key under two instances. This is what catches
      a cloned SD card: imaging a provisioned device copies its `/data`, so every
      device in the batch boots holding the same key. Without this the fleet
      simply misbehaves; with it, the second device to report fails loudly.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Devices.Device

  @type t :: %__MODULE__{}

  @required_params [:device_id, :service, :identifier]
  @optional_params [:instance, :details, :source, :last_reported_at]

  @default_instance "default"

  # An iroh endpoint id is 64 hex characters and a WireGuard key 44 base64
  # characters, so this is generous. It exists to bound what a device can write,
  # not to describe any real key.
  @max_identifier_length 255

  # Likewise a ceiling rather than an expectation: an iroh ticket plus its relay
  # URLs is well under a kilobyte.
  @max_details_bytes 4_096

  schema "device_external_identities" do
    belongs_to(:device, Device)

    field(:service, Ecto.Enum, values: [:iroh, :netbird, :tailscale, :wireguard])
    field(:instance, :string, default: @default_instance)
    field(:identifier, :string)
    field(:details, :map, default: %{})

    field(:source, Ecto.Enum,
      values: [:device_reported, :operator],
      default: :device_reported
    )

    field(:last_reported_at, :utc_datetime)

    timestamps()
  end

  @doc """
  Build a changeset for an external identity.

  Both unique constraints are declared so a violation comes back as a changeset
  error rather than a raised `Postgrex.Error` — a device reporting a duplicated
  key is a situation to surface, not to crash on.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = identity, params) do
    identity
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> validate_length(:identifier, min: 1, max: @max_identifier_length)
    |> validate_length(:instance, min: 1, max: @max_identifier_length)
    |> validate_details_size()
    |> foreign_key_constraint(:device_id)
    |> unique_constraint([:device_id, :service, :instance],
      name: :device_external_identities_device_id_service_instance_index
    )
    |> unique_constraint([:service, :identifier],
      name: :device_external_identities_service_identifier_index
    )
  end

  @doc """
  The services this schema knows how to record.
  """
  @spec services() :: [atom()]
  def services(), do: Ecto.Enum.values(__MODULE__, :service)

  @doc """
  The instance name used when a device doesn't distinguish one.

  Most services are singletons, so most identities carry this.
  """
  @spec default_instance() :: String.t()
  def default_instance(), do: @default_instance

  @doc """
  The largest `details` payload that will be accepted, in bytes.
  """
  def max_details_bytes(), do: @max_details_bytes

  # `details` is written straight from a device-supplied payload, so it needs a
  # ceiling. Encoding is the only honest way to measure it, and a map that will
  # not encode cannot be stored in a jsonb column either.
  defp validate_details_size(changeset) do
    case get_change(changeset, :details) do
      nil ->
        changeset

      details ->
        case Jason.encode(details) do
          {:ok, encoded} when byte_size(encoded) <= @max_details_bytes ->
            changeset

          {:ok, _encoded} ->
            add_error(changeset, :details, "must be at most %{count} bytes when encoded", count: @max_details_bytes)

          {:error, _} ->
            add_error(changeset, :details, "must be JSON encodable")
        end
    end
  end
end
