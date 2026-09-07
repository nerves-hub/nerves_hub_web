defmodule NervesHub.ErrorReports.ErrorGroup do
  @moduledoc """
  One distinct error in a product, and everything true of it over time.

  The occurrences themselves live in ClickHouse as
  `NervesHub.ErrorReports.ErrorReport`; this is the row a person acts on. The
  two are joined by `fingerprint`.

  ## Why this is in PostgreSQL

  Three properties, and ClickHouse gives none of them well.

  It is **mutable** — a status that a person changes, counters that move on
  every occurrence. It is **bounded**, in the hundreds to low thousands per
  product, because it is one row per distinct bug rather than one per crash.
  And it has to **outlive its occurrences**: those are dropped after thirty
  days, and "this has happened forty thousand times since March" should still
  be answerable in June.

  ## Status

    * `:unresolved` — the default, and what the product page lists.
    * `:resolved` — somebody shipped a fix. A later occurrence reopens it and
      stamps `regressed_at`.
    * `:muted` — known about, deliberately out of the queue. Muting keeps
      counting and does not reopen; that is the whole difference from
      resolving.

  ## Counters

  `occurrence_count`, `last_seen_at` and `last_seen_firmware_uuid` are not
  written through these changesets. They are moved by the coalescing upsert in
  `NervesHub.ErrorReports.GroupBuffer`, which exists because a device in a crash
  loop would otherwise put every node in a lock queue on this one row.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.User
  alias NervesHub.Products.Product

  @type t :: %__MODULE__{}

  @statuses [:unresolved, :resolved, :muted]

  @required [
    :product_id,
    :fingerprint,
    :fingerprint_version,
    :kind,
    :reason,
    :first_seen_at,
    :last_seen_at
  ]

  @optional [
    :source,
    :top_frame_module,
    :top_frame_function,
    :top_frame_file,
    :top_frame_line,
    :first_seen_firmware_uuid,
    :last_seen_firmware_uuid,
    :occurrence_count
  ]

  schema "error_groups" do
    belongs_to(:product, Product)

    field(:fingerprint, :string)
    field(:fingerprint_version, :integer, default: 1)

    field(:kind, :string)
    field(:source, :string, default: "logger")
    field(:reason, :string)

    field(:top_frame_module, :string)
    field(:top_frame_function, :string)
    field(:top_frame_file, :string)
    field(:top_frame_line, :integer)

    field(:status, Ecto.Enum, values: @statuses, default: :unresolved)
    field(:occurrence_count, :integer, default: 0)

    field(:first_seen_at, :utc_datetime_usec)
    field(:last_seen_at, :utc_datetime_usec)
    field(:first_seen_firmware_uuid, :string)
    field(:last_seen_firmware_uuid, :string)

    field(:resolved_at, :utc_datetime_usec)
    belongs_to(:resolved_by, User)
    field(:resolved_in_firmware_uuid, :string)

    field(:regressed_at, :utc_datetime_usec)

    field(:muted_at, :utc_datetime_usec)
    belongs_to(:muted_by, User)

    timestamps()
  end

  @doc "The statuses a group can be in."
  def statuses(), do: @statuses

  @doc """
  Builds a group from the first occurrence that produced it.
  """
  @spec create_changeset(map()) :: Ecto.Changeset.t()
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> foreign_key_constraint(:product_id)
    |> unique_constraint([:product_id, :fingerprint])
  end

  @doc """
  Marks a group resolved.

  `firmware_uuid` is the release the fix is expected to be in. Nothing reads it
  yet — the reopen rule is currently "any occurrence after `resolved_at`" — but
  it is recorded now so the firmware-aware rule can replace it later without a
  migration or a backfill.
  """
  @spec resolve_changeset(t(), User.t(), String.t() | nil) :: Ecto.Changeset.t()
  def resolve_changeset(%__MODULE__{} = group, %User{} = user, firmware_uuid \\ nil) do
    change(group, %{
      status: :resolved,
      resolved_at: DateTime.utc_now(),
      resolved_by_id: user.id,
      resolved_in_firmware_uuid: firmware_uuid,
      # Cleared so that a group resolved after a regression does not keep
      # showing the previous one's badge.
      regressed_at: nil
    })
  end

  @doc """
  Silences a group without claiming it is fixed.
  """
  @spec mute_changeset(t(), User.t()) :: Ecto.Changeset.t()
  def mute_changeset(%__MODULE__{} = group, %User{} = user) do
    change(group, %{status: :muted, muted_at: DateTime.utc_now(), muted_by_id: user.id})
  end

  @doc """
  Returns a group to the queue, from either resolved or muted.
  """
  @spec reopen_changeset(t()) :: Ecto.Changeset.t()
  def reopen_changeset(%__MODULE__{} = group) do
    change(group, %{
      status: :unresolved,
      resolved_at: nil,
      resolved_by_id: nil,
      resolved_in_firmware_uuid: nil,
      muted_at: nil,
      muted_by_id: nil
    })
  end
end
