defmodule NervesHub.Devices.NetworkIdentity do
  @moduledoc """
  An identity held on a network that NervesHub does not operate.

  Devices increasingly reach the outside world over something other than their
  NervesHub socket — an iroh endpoint, a NetBird or Tailscale peer, a plain
  WireGuard interface. Those networks each name a peer by a long-lived public
  key, and each keeps *where* that peer currently is (endpoint addresses, relay
  assignment) separate and changeable. This schema records that pairing so an
  operator can see, and act on, an identity elsewhere.

  ## Who holds one

  A device, a person, or nobody in particular:

    * `device_id` — reported by the device itself over its own connection.
    * `org_user_id` — a **membership**, not a user. Someone in three
      organisations holds three identities, each scoped to the one it speaks
      for, and losing the membership takes the identity's access with it.
    * neither — recorded by an operator for something NervesHub does not manage.

  Never both owners at once; a database constraint enforces it. They could
  disagree about which organisation the identity belongs to, and that answer has
  to be unambiguous.

  ## `org_id`

  Every identity names an organisation, whether or not it has an owner, because
  that is what consumers resolve a key to. It is stored rather than derived, and
  so it has to be kept true: `NervesHub.Devices.move/3` updates it in the same
  transaction that moves a device, or a moved device would keep answering for
  the organisation it left.

  ## What `identifier` means

  `identifier` is **the value the device claims possession of** — its iroh endpoint id, 
  or its WireGuard/NetBird/Tailscale public key.

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

  Three unique indexes back this table:

    * `(service, identifier)` — no two owners may claim the same key, anywhere.
      This is what makes the table a registry rather than a set of per-owner
      lists: a key resolves to one organisation, so a consumer never has two
      answers to choose between. It also catches a cloned SD card, where imaging
      a provisioned device copies its `/data` and every device in the batch boots
      holding the same key. Without it the fleet simply misbehaves; with it, the
      second device to report fails loudly.
    * `(device_id, service, instance)` and `(org_user_id, service, instance)` —
      one identity per endpoint per owner, so "this device's iroh console" has
      exactly one answer. Both are **partial**, over rows where that owner is
      set. A plain composite index would let every operator-recorded row collide
      silently, since NULL != NULL in Postgres — the same trap that keeps
      `instance` from being nullable.

  A consequence worth stating: because `(service, identifier)` is global, one key
  belongs to one organisation. Somebody working across three of them runs three
  endpoints, one per organisation, which is what `instance` is for.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.Org
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Devices.Device

  @type t :: %__MODULE__{}

  # `org_id` is required of every identity, owned or not: it is what a key
  # resolves to. The owner is optional and there is at most one of them.
  @required_params [:org_id, :service, :identifier]
  @optional_params [
    :device_id,
    :org_user_id,
    :instance,
    :details,
    :source,
    :last_reported_at
  ]

  @default_instance "default"

  # An iroh endpoint id is 64 hex characters and a WireGuard key 44 base64
  # characters, so this is generous. It exists to bound what a device can write,
  # not to describe any real key.
  @max_identifier_length 255

  # Likewise a ceiling rather than an expectation: an iroh ticket plus its relay
  # URLs is well under a kilobyte.
  @max_details_bytes 4_096

  schema "network_identities" do
    belongs_to(:org, Org)
    belongs_to(:device, Device)
    belongs_to(:org_user, OrgUser)

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
  Build a changeset for an network identity.

  Every constraint the database holds is declared, so a violation comes back as
  a changeset error rather than a raised `Postgrex.Error`. A duplicated key is a
  situation to surface — to the operator who typed it, or in the logs when a
  cloned device reports one — not to crash on.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = identity, params) do
    identity
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
    |> validate_length(:identifier, min: 1, max: @max_identifier_length)
    |> validate_length(:instance, min: 1, max: @max_identifier_length)
    |> validate_details_size()
    |> validate_single_owner()
    |> foreign_key_constraint(:org_id)
    |> foreign_key_constraint(:device_id)
    |> foreign_key_constraint(:org_user_id)
    |> unique_constraint([:service, :identifier],
      name: :network_identities_service_identifier_index
    )
    |> unique_constraint([:device_id, :service, :instance],
      name: :network_identities_device_service_instance_index
    )
    |> unique_constraint([:org_user_id, :service, :instance],
      name: :network_identities_org_user_service_instance_index
    )
    |> check_constraint(:device_id,
      name: :network_identities_one_owner,
      message: "an identity belongs to a device or a membership, not both"
    )
  end

  # Caught here as well as by the database constraint, so the message lands on a
  # field and reaches a form rather than arriving as a bare constraint error.
  defp validate_single_owner(changeset) do
    device_id = get_field(changeset, :device_id)
    org_user_id = get_field(changeset, :org_user_id)

    if device_id && org_user_id do
      add_error(changeset, :device_id, "an identity belongs to a device or a membership, not both")
    else
      changeset
    end
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
