defmodule NervesHub.Accounts.Org do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__
  alias NervesHub.Accounts.OrgKey
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Devices.CACertificate
  alias NervesHub.Devices.Device
  alias NervesHub.Products.Product
  alias NervesHub.Repo

  @params [:name]

  # Labels, at least two, without a trailing dot or a wildcard.
  @hostname_format ~r/\A(?!-)[a-z0-9-]{1,63}(?<!-)(\.(?!-)[a-z0-9-]{1,63}(?<!-))+\z/

  @type id :: pos_integer() | nil
  @type t :: %__MODULE__{id: id()}

  @derive {Phoenix.Param, key: :name}
  schema "orgs" do
    has_many(:org_keys, OrgKey)
    has_many(:products, Product, where: [deleted_at: nil])
    has_many(:devices, Device, where: [deleted_at: nil])
    has_many(:ca_certificates, CACertificate)

    has_many(:org_users, OrgUser, where: [deleted_at: nil])
    has_many(:users, through: [:org_users, :user])

    field(:name, :string)
    field(:deleted_at, :utc_datetime)
    field(:audit_log_days_to_keep, :integer)

    # Hostnames this org's devices connect to. Several orgs can share one, and only
    # they can connect to it. Not in any changeset an org's own users can reach, or
    # one org could claim another's.
    field(:device_hostnames, {:array, :string}, default: [])

    embeds_one :settings, __MODULE__.Settings do
      field(:firmware_proxy_url, :string)
    end

    field(:connected_devices_count, :integer, virtual: true, default: 0)
    field(:disconnected_devices_count, :integer, virtual: true, default: 0)

    timestamps()
  end

  def changeset(%Org{} = org, params \\ %{}) do
    org
    |> cast(params, @params)
    |> validate_required(@params)
    |> unique_constraint(:name)
    |> validate_format(:name, ~r/^[A-Za-z0-9-_]+$/)
  end

  def device_hostnames_changeset(%Org{} = org, hostnames) do
    org
    |> cast(%{device_hostnames: Enum.map(hostnames, &normalize_hostname/1)}, [:device_hostnames])
    |> update_change(:device_hostnames, &Enum.uniq/1)
    |> validate_change(:device_hostnames, fn :device_hostnames, hostnames ->
      for hostname <- hostnames,
          byte_size(hostname) > 253 or not Regex.match?(@hostname_format, hostname) do
        {:device_hostnames, "#{inspect(hostname)} must be a full hostname, with no wildcard"}
      end
    end)
  end

  @doc "DNS names aren't case sensitive, and a client may send a trailing dot."
  @spec normalize_hostname(String.t()) :: String.t()
  def normalize_hostname(hostname) do
    hostname |> String.trim() |> String.trim_trailing(".") |> String.downcase()
  end

  def add_user(struct, params) do
    cast(struct, params, [:role])
    |> validate_required([:role])
    |> unique_constraint(
      :org_users,
      name: "org_users_index",
      message: "is already member"
    )
  end

  def change_user_role(struct, params \\ %{}) do
    cast(struct, params, ~w(role)a)
    |> validate_required(~w(role)a)
  end

  def creation_changeset(%Org{} = org, params) do
    org
    |> changeset(params)
  end

  def update_changeset(%Org{} = org, params) do
    org
    |> changeset(params)
  end

  def delete_changeset(%Org{} = org) do
    deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

    change(org, deleted_at: deleted_at)
  end

  def with_org_keys(%Org{} = o) do
    o
    |> Repo.preload(:org_keys)
  end

  def with_org_keys(org_query) do
    org_query
    |> preload(:org_keys)
  end
end
