defmodule NervesHub.Products.Product do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.Org
  alias NervesHub.Archives.Archive
  alias NervesHub.Devices.CACertificate
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.UpdateStat
  alias NervesHub.Extensions.ProductExtensionsSetting
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.UpdateTool
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Products.CustomHealthMetricsLabel
  alias NervesHub.Products.Notification
  alias NervesHub.Products.SharedSecretAuth
  alias NervesHub.Scripts.Script

  @required_params [:name, :org_id]

  @type t :: %__MODULE__{}

  @derive {Phoenix.Param, key: :name}
  schema "products" do
    has_many(:devices, Device, where: [deleted_at: nil])
    has_many(:firmwares, Firmware)
    has_many(:jitp, CACertificate.JITP)
    has_many(:archives, Archive)
    has_many(:scripts, Script)
    has_many(:deployment_groups, DeploymentGroup)
    has_many(:update_stats, UpdateStat, on_delete: :nilify_all)
    has_many(:notifications, Notification, on_delete: :delete_all)
    has_many(:custom_health_metrics_labels, CustomHealthMetricsLabel, on_delete: :delete_all)

    has_many(:shared_secret_auths, SharedSecretAuth, preload_order: [desc: :deactivated_at, asc: :id])

    belongs_to(:org, Org, where: [deleted_at: nil])

    field(:name, :string)
    field(:deleted_at, :utc_datetime)
    # Defaults to `true` so new products require unique firmware versions; the DB
    # column defaults to `false`, so existing products keep the prior behaviour.
    field(:require_unique_firmware_version, :boolean, default: true)

    # Which firmware formats this product accepts. fwup alone by default; a
    # product accepts another format only once someone opts it in.
    field(:allowed_update_tools, {:array, :string}, default: ["fwup"])

    # Allows an ESP-IDF image with no Secure Boot v2 signature block. ESP-specific
    # rather than a general `allow_unsigned_firmware`: fwup archives are always
    # verified, and no setting changes that.
    field(:allow_unsigned_esp_idf_firmware, :boolean, default: false)
    embeds_one(:extensions, ProductExtensionsSetting, on_replace: :update)

    field(:device_count, :integer, virtual: true)

    field(:connected_devices_count, :integer, virtual: true, default: 0)
    field(:disconnected_devices_count, :integer, virtual: true, default: 0)

    timestamps()
  end

  def change_user_role(struct, params) do
    cast(struct, params, ~w(role)a)
    |> validate_required(~w(role)a)
  end

  @doc false
  def changeset(product, params) do
    product
    |> cast(
      params,
      @required_params ++
        [:require_unique_firmware_version, :allowed_update_tools, :allow_unsigned_esp_idf_firmware]
    )
    |> cast_embed(:extensions)
    |> update_change(:name, &trim/1)
    |> validate_required(@required_params)
    |> validate_allowed_update_tools()
    |> unique_constraint(:name, name: :products_org_id_name_index)
  end

  @doc """
  Whether this product accepts firmware handled by `tool`.
  """
  @spec accepts_update_tool?(t(), String.t()) :: boolean()
  def accepts_update_tool?(%__MODULE__{allowed_update_tools: tools}, tool) do
    tool in (tools || ["fwup"])
  end

  # A tool must exist, and must be enabled for this instance — a product listing
  # a format the instance will not recognise is a setting that reads as on and
  # behaves as off.
  #
  # `validate_change/3` only fires when the field is being changed, so an
  # instance that turns a format off does not invalidate the products that had
  # already opted into it.
  defp validate_allowed_update_tools(changeset) do
    known = Map.keys(UpdateTool.known())
    enabled = Map.keys(UpdateTool.all())

    validate_change(changeset, :allowed_update_tools, fn :allowed_update_tools, tools ->
      unknown = Enum.reject(tools, &(&1 in known))
      disabled = Enum.filter(tools, &(&1 in known and &1 not in enabled))

      cond do
        unknown != [] ->
          [allowed_update_tools: "unknown update tool(s): #{Enum.join(unknown, ", ")}"]

        disabled != [] ->
          [
            allowed_update_tools: "not enabled on this NervesHub instance: #{Enum.join(disabled, ", ")}"
          ]

        true ->
          []
      end
    end)
  end

  def delete_changeset(product, _params \\ %{}) do
    deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

    product
    |> change()
    |> put_change(:deleted_at, deleted_at)
  end

  defp trim(string) when is_binary(string) do
    string
    |> String.split(" ", trim: true)
    |> Enum.join(" ")
  end

  defp trim(string), do: string
end
