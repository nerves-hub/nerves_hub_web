defmodule NervesHub.ManagedDeployments.DeploymentWorkflowStep do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.User
  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHub.Types.Tag

  @type t :: %__MODULE__{}

  schema "deployment_workflow_steps" do
    belongs_to(:deployment_release, DeploymentRelease)

    many_to_many :devices, Device, join_through: "deployment_workflow_steps_devices"

    belongs_to(:skipped_by, User)
    belongs_to(:approved_by, User)

    field(:number, :integer)

    field(:name, :string)
    field(:description, :string)

    field(:type, Ecto.Enum, values: [:update_devices, :approval_required, :catch_all], default: :update_devices)

    field(:status, Ecto.Enum, values: [:waiting, :in_progress, :completed, :skipped, :error], default: :waiting)

    # Network interfaces are the humanised names the rest of the system stores
    # (see `Devices.DeviceConnection.humanized_network_interface_name/1`), not the
    # raw `wlan0`/`eth0` a device reports. Kept identical to a deployment group's
    # `release_network_interfaces` so a step filters the same way a release does.
    embeds_one :matching_conditions, __MODULE__.Conditions, primary_key: false, on_replace: :update do
      field(:tags, Tag, default: [])

      field(:network_interfaces, {:array, Ecto.Enum},
        values: [:wifi, :ethernet, :cellular, :unknown],
        default: []
      )

      field(:match_limit, :integer, default: 10)
    end

    field(:concurrency, :integer, default: 10)

    field(:approved_at, :naive_datetime)
    field(:started_at, :naive_datetime)
    field(:skipped_at, :naive_datetime)
    field(:finished_at, :naive_datetime)
  end

  @doc """
  What to call a step on screen.

  A name is required of an uploaded definition, but not every step comes from
  one: the trailing catch_all is generated, and steps stored before names were
  required still have none. Falling back on the type keeps those readable.
  """
  @spec label(t()) :: String.t()
  def label(%__MODULE__{name: name}) when is_binary(name) and name != "", do: name
  def label(%__MODULE__{type: :approval_required}), do: "Approval required"
  def label(%__MODULE__{type: :catch_all}), do: "Remaining devices"
  def label(%__MODULE__{number: number}), do: "Step #{number}"

  def new_catch_all(number) do
    change(%__MODULE__{}, %{type: :catch_all, number: number})
  end

  # A catch_all covers whatever earlier steps left, so it has no conditions of
  # its own to carry across.
  def new_changeset(%{"type" => "catch_all"} = step_definition, number) do
    %__MODULE__{}
    |> change()
    |> put_change(:type, :catch_all)
    |> maybe_put_change(:name, step_definition["name"])
    |> maybe_put_change(:description, step_definition["description"])
    |> maybe_put_change(:concurrency, step_definition["concurrent_updates"])
    |> put_change(:number, number)
  end

  # An approval step covers no devices at all — it only holds the workflow until
  # somebody says to carry on.
  def new_changeset(%{"type" => "approval_required"} = step_definition, number) do
    %__MODULE__{}
    |> change()
    |> put_change(:type, :approval_required)
    |> maybe_put_change(:name, step_definition["name"])
    |> maybe_put_change(:description, step_definition["description"])
    |> put_change(:number, number)
  end

  def new_changeset(step_definition, number) do
    %__MODULE__{}
    |> change()
    |> maybe_put_change(:name, step_definition["name"])
    |> maybe_put_change(:description, step_definition["description"])
    |> maybe_put_change(:type, step_type(step_definition["type"]))
    |> maybe_put_change(:concurrency, step_definition["concurrent_updates"])
    |> maybe_put_embed(:matching_conditions, matching_conditions(step_definition["matching_conditions"]))
    |> put_change(:number, number)
  end

  defp maybe_put_change(changeset, _field, nil), do: changeset

  defp maybe_put_change(changeset, field, value) do
    put_change(changeset, field, value)
  end

  defp maybe_put_embed(changeset, _field, nil), do: changeset

  defp maybe_put_embed(changeset, field, value) do
    put_embed(changeset, field, value)
  end

  # Definitions are uploaded by users, so the strings are mapped rather than
  # converted — `String.to_atom/1` on uploaded content grows the atom table.
  # An unrecognised type is left unset for the changeset to reject.
  defp step_type("update_devices"), do: :update_devices
  defp step_type("approval_required"), do: :approval_required
  defp step_type("catch_all"), do: :catch_all
  defp step_type(_other), do: nil

  defp matching_conditions(nil), do: nil

  # Cast rather than put the raw map: an unrecognised network interface has to
  # fail here, where it becomes a changeset error the upload can report. Written
  # through unchecked it would dump fine and then raise on every read of the
  # step, including inside the orchestrator.
  defp matching_conditions(conditions) when is_map(conditions) do
    cast(
      %__MODULE__.Conditions{},
      Map.take(conditions, ["tags", "network_interfaces", "match_limit"]),
      [:tags, :network_interfaces, :match_limit]
    )
  end

  defp matching_conditions(_other), do: nil
end
