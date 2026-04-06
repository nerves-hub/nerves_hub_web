defmodule NervesHub.Ash.Firmwares.FirmwareDelta do
  use Ash.Resource,
    domain: NervesHub.Ash.Firmwares,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource, AshGraphql.Resource]

  postgres do
    table "firmware_deltas"
    repo NervesHub.Repo
  end

  json_api do
    type "firmware-delta"
    derive_filter? false

    routes do
      base "/firmware-deltas"

      index :read
      get :read, route: "/:id"
    end
  end

  graphql do
    encode_primary_key? false
    type :firmware_delta

    queries do
      get :get_firmware_delta, :read
      list :list_firmware_deltas, :read
    end
  end

  attributes do
    integer_primary_key :id

    attribute :source_id, :integer, allow_nil?: false, public?: true
    attribute :target_id, :integer, allow_nil?: false, public?: true
    attribute :status, :atom, public?: true, constraints: [one_of: [:processing, :completed, :failed, :timed_out]]
    attribute :tool, :string, public?: true
    attribute :tool_metadata, :map, public?: true
    attribute :size, :integer, default: 0, public?: true
    attribute :source_size, :integer, default: 0, public?: true
    attribute :target_size, :integer, default: 0, public?: true
    attribute :upload_metadata, :map, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :source, NervesHub.Ash.Firmwares.Firmware do
      public? true
      source_attribute :source_id
      destination_attribute :id
    end

    belongs_to :target, NervesHub.Ash.Firmwares.Firmware do
      public? true
      source_attribute :target_id
      destination_attribute :id
    end
  end

  actions do
    defaults [:read]

    read :list_by_source do
      argument :source_id, :integer, allow_nil?: false

      filter expr(source_id == ^arg(:source_id))
    end

    read :list_by_target do
      argument :target_id, :integer, allow_nil?: false

      filter expr(target_id == ^arg(:target_id))
    end

    read :get_by_source_and_target do
      argument :source_id, :integer, allow_nil?: false
      argument :target_id, :integer, allow_nil?: false

      filter expr(source_id == ^arg(:source_id) and target_id == ^arg(:target_id))
    end

    create :create do
      accept [:source_id, :target_id, :status, :tool, :tool_metadata, :size, :source_size, :target_size, :upload_metadata]
    end

    update :update do
      primary? true
      accept [:status, :size, :upload_metadata]
    end

    update :fail do
      accept []

      manual fn changeset, _context ->
        ecto_delta = NervesHub.Repo.get!(NervesHub.Firmwares.FirmwareDelta, changeset.data.id)

        case NervesHub.Firmwares.fail_firmware_delta(ecto_delta) do
          {:ok, updated} ->
            ash_fields = [:id, :source_id, :target_id, :status, :tool, :tool_metadata, :size, :source_size, :target_size, :upload_metadata, :inserted_at, :updated_at]
            {:ok, struct!(NervesHub.Ash.Firmwares.FirmwareDelta, Map.take(updated, ash_fields))}

          {:error, error} ->
            {:error, error}
        end
      end
    end

    update :time_out do
      accept []

      manual fn changeset, _context ->
        ecto_delta = NervesHub.Repo.get!(NervesHub.Firmwares.FirmwareDelta, changeset.data.id)

        case NervesHub.Firmwares.time_out_firmware_delta(ecto_delta) do
          {:ok, updated} ->
            ash_fields = [:id, :source_id, :target_id, :status, :tool, :tool_metadata, :size, :source_size, :target_size, :upload_metadata, :inserted_at, :updated_at]
            {:ok, struct!(NervesHub.Ash.Firmwares.FirmwareDelta, Map.take(updated, ash_fields))}

          {:error, error} ->
            {:error, error}
        end
      end
    end

    destroy :destroy do
      manual fn changeset, _context ->
        ecto_delta = NervesHub.Repo.get!(NervesHub.Firmwares.FirmwareDelta, changeset.data.id)

        case NervesHub.Firmwares.delete_firmware_delta(ecto_delta) do
          {:ok, _} -> {:ok, changeset.data}
          {:error, error} -> {:error, error}
        end
      end
    end
  end

  code_interface do
    define :read
    define :get, action: :read, get_by: [:id], not_found_error?: true
    define :list_by_source, args: [:source_id]
    define :list_by_target, args: [:target_id]
    define :get_by_source_and_target, args: [:source_id, :target_id], get?: true
    define :create
    define :update
    define :fail
    define :time_out
    define :destroy
  end
end
