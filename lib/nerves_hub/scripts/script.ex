defmodule NervesHub.Scripts.Script do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.User
  alias NervesHub.Products.Product
  alias NervesHub.Types.Tag

  @type t :: %__MODULE__{}
  @required [:name, :text]
  @optional [:tags]

  schema "scripts" do
    belongs_to(:product, Product)
    belongs_to(:created_by, User, where: [deleted_at: nil])
    belongs_to(:last_updated_by, User, where: [deleted_at: nil])

    field(:name, :string)
    field(:text, :string)
    field(:tags, Tag)
    field(:last_editor_name, :string, virtual: true)

    timestamps()
  end

  def validate_changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, @required ++ @optional)
    |> validate_required(@required)
    |> validate_length(:name, lte: 255)
    |> validate_elixir_syntax()
  end

  def create_changeset(product, created_by, params) do
    validate_changeset(params)
    |> put_assoc(:product, product)
    |> foreign_key_constraint(:product_id)
    |> put_assoc(:created_by, created_by)
    |> foreign_key_constraint(:created_by_id)
  end

  def update_changeset(%__MODULE__{} = struct, edited_by, params \\ %{}) do
    struct
    |> validate_changeset(params)
    |> put_change(:last_updated_by_id, edited_by.id)
    |> foreign_key_constraint(:last_updated_by_id)
  end

  defp validate_elixir_syntax(changeset) do
    validate_change(changeset, :text, fn :text, text ->
      case Code.string_to_quoted(text, static_atoms_encoder: &encode_syntax_atom/2) do
        {:ok, _quoted} ->
          []

        {:error, {location, message, token}} ->
          line = Keyword.fetch!(location, :line)
          column = Keyword.get(location, :column)

          position =
            if column do
              "line #{line}, column #{column}"
            else
              "line #{line}"
            end

          [text: "has invalid Elixir syntax at #{position}: #{message}#{token}"]
      end
    end)
  end

  # The quoted result is discarded, so reusing one atom avoids growing the VM's atom table
  # with identifiers supplied through the form.
  defp encode_syntax_atom(_name, _metadata), do: {:ok, :support_script_syntax_atom}
end
