defmodule NervesHub.ManagedDeployments.DeploymentRelease do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__
  alias NervesHub.Accounts.User
  alias NervesHub.Archives.Archive
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.Products.ApiKey
  alias NervesHub.Repo

  @type t :: %__MODULE__{}

  @typedoc """
  Whether the deltas a release's devices need are ready: one or more are still
  being built (`:preparing`), one or more gave up (`:failed`), or there is
  nothing left to wait for (`:ready`).
  """
  @type delta_status :: :ready | :preparing | :failed

  @typedoc """
  Where a release's connecting code runs relative to its deployment group's:
  before it (`:first`), after it (`:last`), or instead of it (`:override`).
  """
  @type connecting_code_mode :: :first | :last | :override

  schema "deployment_releases" do
    belongs_to(:deployment_group, DeploymentGroup)

    has_many(:steps, DeploymentWorkflowStep, preload_order: [asc: :number])

    belongs_to(:firmware, Firmware)
    belongs_to(:archive, Archive)
    belongs_to(:created_by, User)
    # Set instead of `created_by` when a product API key made the release.
    belongs_to(:created_by_api_key, ApiKey)

    field(:description, :string)
    field(:notes, :string)
    field(:number, :integer)
    field(:required, :boolean, default: false)

    field(:connecting_code, :string)
    field(:connecting_code_mode, Ecto.Enum, values: [:first, :last, :override], default: :last)

    field(:delta_status, Ecto.Enum, values: [:ready, :preparing, :failed], default: :ready)

    timestamps()
  end

  # What a release takes from params when it's made. Its firmware and archive
  # are given to `new_changeset/5` already found, and with the description and
  # notes they're fixed from then on.
  @create_fields [:description, :notes, :required, :connecting_code, :connecting_code_mode]

  # What can still change once it's made, through `edit_changeset/2`.
  @edit_fields [:required, :connecting_code, :connecting_code_mode]

  @doc """
  A changeset for a new release of `deployment_group`, numbered after its last.

  `firmware` and `archive` come already loaded. From `params` it takes the
  description, notes, whether it's required, and the connecting code and where
  that runs, and ignores anything else there. It's refused if the firmware and
  archive are the same as the current release's.

  Inserting it doesn't make it the group's current release:
  `NervesHub.ManagedDeployments.create_deployment_release/6` does that. The
  Releases tab also builds one only to check a form's input.

  In a group that's on with delta updates on, it starts `:preparing`, as
  `hold_for_deltas/2` says.
  """
  @spec new_changeset(DeploymentGroup.t(), Firmware.t() | nil, Archive.t() | nil, map(), User.t() | ApiKey.t() | nil) ::
          Ecto.Changeset.t()
  def new_changeset(deployment_group, firmware \\ nil, archive \\ nil, params \\ %{}, created_by \\ nil) do
    change(%__MODULE__{})
    |> cast(params, @create_fields)
    |> hold_for_deltas(deployment_group)
    |> put_assoc(:deployment_group, deployment_group)
    |> put_assoc(:firmware, firmware)
    |> put_assoc(:archive, archive)
    |> put_created_by(created_by)
    |> generate_workflow_steps(deployment_group.workflow_definition)
    |> put_change(:number, 1)
    |> validate_length(:description, max: 100)
    |> validate_length(:notes, max: 1_000)
    # A `null` in a request is cast over the defaults, and the columns refuse it.
    |> validate_required([:firmware, :required, :connecting_code_mode])
    |> validate_firmware(deployment_group)
    |> validate_differs_from_current_release(deployment_group)
    |> validate_created_by_api_key(deployment_group.product_id)
    |> validate_change(:created_by, fn :created_by, created_by_assoc ->
      created_by = created_by_assoc.data

      User
      |> join(:inner, [u], o in assoc(u, :orgs))
      |> join(:inner, [_, o], p in assoc(o, :products))
      |> where([u], u.id == ^created_by.id)
      |> where([_, _, p], p.id == ^deployment_group.product_id)
      |> Repo.one()
      |> case do
        nil -> [created_by: "invalid associated user"]
        _user -> []
      end
    end)
    |> prepare_changes(fn changeset ->
      dg = get_field(changeset, :deployment_group)
      query = from(DeploymentRelease, where: [deployment_group_id: ^dg.id])
      number = changeset.repo.aggregate(query, :count) + 1
      put_change(changeset, :number, number)
    end)
  end

  @doc """
  Holds a release's devices back until its deltas are queued, when saving
  `changeset` will queue some: a new release, or one just marked required, in a
  group that's on with delta updates on.

  The deltas are queued after the release commits, since queueing runs a
  transaction of its own. Until then nothing has been queued for the release to
  wait on, and a release reading `:ready` would be sent as whole firmware. So it
  reads `:preparing`, and the recalculation that follows the queueing settles
  it. If that never runs, the deployment group's orchestrator settles it on its
  next tick (`NervesHub.ManagedDeployments.settle_delta_statuses/1`).
  """
  @spec hold_for_deltas(Ecto.Changeset.t(), DeploymentGroup.t()) :: Ecto.Changeset.t()
  def hold_for_deltas(changeset, %DeploymentGroup{is_active: true, delta_updatable: true}) do
    new? = is_nil(changeset.data.id)

    if new? or get_change(changeset, :required) == true do
      put_change(changeset, :delta_status, :preparing)
    else
      changeset
    end
  end

  def hold_for_deltas(changeset, _deployment_group), do: changeset

  @doc """
  Record whether the deltas this release's devices need are ready.
  """
  @spec delta_status_changeset(t(), delta_status()) :: Ecto.Changeset.t()
  def delta_status_changeset(%__MODULE__{} = release, delta_status) do
    release
    |> cast(%{delta_status: delta_status}, [:delta_status])
    |> validate_required([:delta_status])
  end

  @doc """
  What can still change on a release once it's made, all at once: whether it's
  required, its connecting code, and where that code runs.

  A required release is one every device in the deployment group passes through:
  a device that has not reached it yet is updated to it before anything newer.
  """
  @spec edit_changeset(t(), map()) :: Ecto.Changeset.t()
  def edit_changeset(%__MODULE__{} = release, params) do
    release
    |> cast(params, @edit_fields)
    |> validate_required([:required, :connecting_code_mode])
  end

  # A release with the same firmware and archive as the current one would send
  # devices nothing new. Required and connecting code are changed on the
  # release itself, so they're no reason to create another.
  defp validate_differs_from_current_release(changeset, %DeploymentGroup{current_release: %__MODULE__{} = current}) do
    if assoc_id(changeset, :firmware) == current.firmware_id and assoc_id(changeset, :archive) == current.archive_id do
      add_error(changeset, :firmware, "The current release already has this firmware and archive")
    else
      changeset
    end
  end

  defp validate_differs_from_current_release(changeset, _deployment_group), do: changeset

  defp assoc_id(changeset, field) do
    case get_field(changeset, field) do
      %{id: id} -> id
      _ -> nil
    end
  end

  @doc """
  Records who made a release: a person, or a product API key.
  """
  @spec put_created_by(Ecto.Changeset.t(), User.t() | ApiKey.t() | nil) :: Ecto.Changeset.t()
  def put_created_by(changeset, %ApiKey{} = api_key), do: put_assoc(changeset, :created_by_api_key, api_key)
  def put_created_by(changeset, user), do: put_assoc(changeset, :created_by, user)

  @doc """
  Refuses a release made by a product API key from a product other than
  `product_id`.

  A key reaches its own product's routes only, so this guards against a caller
  passing the wrong key rather than anything a request can do.
  """
  @spec validate_created_by_api_key(Ecto.Changeset.t(), pos_integer()) :: Ecto.Changeset.t()
  def validate_created_by_api_key(changeset, product_id) do
    validate_change(changeset, :created_by_api_key, fn :created_by_api_key, %{data: api_key} ->
      if api_key.product_id == product_id do
        []
      else
        [created_by_api_key: "belongs to another product"]
      end
    end)
  end

  defp validate_firmware(changeset, deployment_group) do
    validate_change(changeset, :firmware, fn :firmware, firmware_assoc ->
      firmware = firmware_assoc.data

      if not is_nil(firmware) && firmware.product_id != deployment_group.product_id do
        [firmware: "invalid firmware selected"]
      else
        []
      end
    end)
  end

  defp generate_workflow_steps(changeset, nil), do: changeset

  defp generate_workflow_steps(changeset, workflow_definition) do
    put_assoc(changeset, :steps, workflow_step_changesets(workflow_definition))
  end

  @doc """
  The steps a release made from `workflow_definition` walks through, as
  changesets, ending in the catch_all a definition may leave out.
  """
  @spec workflow_step_changesets(map()) :: [Ecto.Changeset.t()]
  def workflow_step_changesets(workflow_definition) do
    {steps, _} =
      Enum.map_reduce(workflow_definition["steps"] || [], 1, fn step, count ->
        {DeploymentWorkflowStep.new_changeset(step, count), count + 1}
      end)

    maybe_add_catch_all(steps)
  end

  # A definition that has been through the schema always has at least one step, so
  # this only sees an empty list from something that wrote `workflow_definition`
  # without going through the changeset. Failing here would take out release
  # creation for the deployment group, so give it the catch_all and carry on.
  defp maybe_add_catch_all([]), do: [DeploymentWorkflowStep.new_catch_all(1)]

  defp maybe_add_catch_all(steps) do
    last = List.last(steps)

    if get_field(last, :type) == :catch_all do
      steps
    else
      number = get_field(last, :number) + 1
      steps ++ [DeploymentWorkflowStep.new_catch_all(number)]
    end
  end
end
