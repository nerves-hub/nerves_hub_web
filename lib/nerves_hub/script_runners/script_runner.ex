defmodule NervesHub.ScriptRunners.ScriptRunner do
  @moduledoc """
  One bulk script execution: a script body, the filter that chose its devices,
  and how far it got.

  The row is history. `text` is a snapshot of the code taken when the run was
  created, so a run still shows what ran after the script it was copied from is
  edited or deleted — which is why there is no changeset here that writes `text`
  a second time, and no `update/2` in `NervesHub.ScriptRunners`. The changesets
  below only move the run through its statuses.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.User
  alias NervesHub.Products.Product
  alias NervesHub.ScriptRunners.ScriptRunnerDevice
  alias NervesHub.Scripts.Script
  alias NervesHub.Types.Tag

  @type t :: %__MODULE__{}

  @typedoc """
  How the devices for a run were chosen: device tags, a pasted list of device
  identifiers, or membership of one or more deployment groups.
  """
  @type filter_type :: :tags | :identifiers | :deployment_groups

  @typedoc """
  A run is `:pending` until its first devices are dispatched, `:running` while
  they are being worked through, and `:completed` when every device reached a
  terminal status.
  """
  @type status :: :pending | :running | :completed

  @filter_types [:tags, :identifiers, :deployment_groups]
  @statuses [:pending, :running, :completed]
  @tag_operators [:and, :or]

  schema "script_runners" do
    belongs_to(:product, Product)
    belongs_to(:created_by, User, where: [deleted_at: nil])

    has_many(:script_runner_devices, ScriptRunnerDevice)

    field(:text, :string)
    field(:language, Ecto.Enum, values: Script.languages(), default: :elixir)

    field(:filter_type, Ecto.Enum, values: @filter_types)

    # The values the chosen `filter_type` needs. Every type's fields live here
    # rather than in three columns that are null two thirds of the time; which
    # ones matter is decided by `filter_type`, and validated as such below.
    embeds_one :filter, __MODULE__.Filter, primary_key: false, on_replace: :update do
      field(:tags, Tag, default: [])

      # Matches `DeploymentGroup.Conditions`:
      #   :and - a device must carry all of the tags
      #   :or  - a device must carry at least one of them
      #
      # No default, deliberately: the two select different fleets from the same
      # tags, so guessing on the operator's behalf means running an operator's
      # script somewhere they did not choose. Required whenever `filter_type` is
      # `:tags` -- see `validate_filter_for_type/1`.
      field(:tag_operator, Ecto.Enum, values: [:and, :or])

      field(:identifiers, {:array, :string}, default: [])
      field(:deployment_group_ids, {:array, :id}, default: [])
    end

    field(:status, Ecto.Enum, values: @statuses, default: :pending)

    field(:device_count, :integer, default: 0)
    field(:started_at, :utc_datetime_usec)
    field(:finished_at, :utc_datetime_usec)

    timestamps()
  end

  @doc """
  The filter types a run can target its devices with.
  """
  @spec filter_types() :: [filter_type(), ...]
  def filter_types(), do: @filter_types

  @doc """
  A human readable name for a filter type.
  """
  @spec filter_type_label(filter_type()) :: String.t()
  def filter_type_label(:tags), do: "Tags"
  def filter_type_label(:identifiers), do: "Device identifiers"
  def filter_type_label(:deployment_groups), do: "Deployment groups"

  @doc """
  The ways multiple tags can be combined.

  For the UI to offer: there is no default, so one of these has to be chosen
  whenever a run filters by tags.
  """
  @spec tag_operators() :: [:and | :or, ...]
  def tag_operators(), do: @tag_operators

  @doc """
  A human readable name for a tag operator.

  The same wording the deployment group form uses for the same two operators.
  """
  @spec tag_operator_label(:and | :or) :: String.t()
  def tag_operator_label(:and), do: "Require all"
  def tag_operator_label(:or), do: "Allow any"

  @doc """
  Build a run for a product.

  The only changeset that writes `text`, and the reason the module has no update
  path: see the moduledoc.
  """
  @spec create_changeset(Product.t(), User.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(product, created_by, params) do
    %__MODULE__{}
    |> cast(params, [:text, :language, :filter_type, :device_count])
    |> validate_required([:text, :filter_type])
    |> cast_embed(:filter, required: true, with: &filter_changeset/2)
    |> validate_filter_for_type()
    |> put_assoc(:product, product)
    |> foreign_key_constraint(:product_id)
    |> put_assoc(:created_by, created_by)
    |> foreign_key_constraint(:created_by_id)
  end

  @doc """
  Record that a run's devices have started being worked through.
  """
  @spec running_changeset(t()) :: Ecto.Changeset.t()
  def running_changeset(%__MODULE__{} = runner) do
    runner
    |> cast(%{status: :running, started_at: DateTime.utc_now()}, [:status, :started_at])
    |> validate_required([:status, :started_at])
  end

  @doc """
  Every device reached a terminal status.
  """
  @spec finished_changeset(t()) :: Ecto.Changeset.t()
  def finished_changeset(%__MODULE__{} = runner) do
    runner
    |> cast(%{status: :completed, finished_at: DateTime.utc_now()}, [:status, :finished_at])
    |> validate_required([:status, :finished_at])
  end

  @doc """
  Split pasted device identifiers into a list.

  Accepts what a person pastes: commas, newlines, surrounding whitespace, blank
  entries and repeats.
  """
  @spec parse_identifiers(String.t() | [String.t()] | nil) :: [String.t()]
  def parse_identifiers(nil), do: []

  def parse_identifiers(identifiers) when is_list(identifiers) do
    identifiers
    |> Enum.join(",")
    |> parse_identifiers()
  end

  def parse_identifiers(identifiers) when is_binary(identifiers) do
    identifiers
    |> String.split([",", "\n", "\r"])
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  # The filter's own fields are always cast; which of them are required is a
  # question about `filter_type`, so it is asked on the outer changeset where
  # that field can be read.
  #
  # Identifiers arrive as a pasted blob as often as a list, so they are split
  # before casting -- storing them parsed means every reader gets the same list
  # rather than re-splitting the raw paste.
  defp filter_changeset(filter, params) do
    params = normalise_identifiers(params)

    cast(filter, params, [:tags, :tag_operator, :identifiers, :deployment_group_ids])
  end

  defp normalise_identifiers(params) do
    cond do
      Map.has_key?(params, :identifiers) ->
        Map.put(params, :identifiers, parse_identifiers(params[:identifiers]))

      Map.has_key?(params, "identifiers") ->
        Map.put(params, "identifiers", parse_identifiers(params["identifiers"]))

      true ->
        params
    end
  end

  defp validate_filter_for_type(changeset) do
    case get_field(changeset, :filter_type) do
      :tags ->
        changeset
        |> validate_filter_present(:tags, "at least one tag is required")
        |> validate_tag_operator_chosen()

      :identifiers ->
        validate_filter_present(changeset, :identifiers, "at least one device identifier is required")

      :deployment_groups ->
        validate_filter_present(changeset, :deployment_group_ids, "at least one deployment group is required")

      nil ->
        changeset
    end
  end

  defp validate_filter_present(changeset, field, message) do
    case get_field(changeset, :filter) do
      %{^field => [_ | _]} -> changeset
      _empty -> add_error(changeset, :filter, message)
    end
  end

  # "All of these tags" and "any of these tags" select different fleets from the
  # same list, so which was meant is the operator's to say rather than ours to
  # assume.
  defp validate_tag_operator_chosen(changeset) do
    case get_field(changeset, :filter) do
      %{tag_operator: operator} when operator in [:and, :or] ->
        changeset

      _unchosen ->
        add_error(changeset, :filter, "a tag operator must be chosen: :and to require all tags, :or to allow any")
    end
  end
end
