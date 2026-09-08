defmodule NervesHub.Scripts.Script do
  use Ecto.Schema

  import Ecto.Changeset

  alias NervesHub.Accounts.User
  alias NervesHub.Products.Product
  alias NervesHub.Types.Tag

  @type t :: %__MODULE__{}
  @type language :: :elixir | :shell
  @required [:name, :text]
  @optional [:language, :tags]

  # What the device is expected to make of `text`. `nerves_hub_link` evaluates
  # it as Elixir; the Rust agent for non-Nerves Linux runs it as a shell
  # script. The server treats the text as opaque either way -- the language is
  # recorded so the author can be told what will happen to it, and so a client
  # can eventually refuse a script it cannot run rather than misinterpret one.
  @languages [:elixir, :shell]

  # Errors the Elixir parser raises for text that cannot be parsed. They all
  # carry `description`, `line` and `column`, so one clause reads them all.
  @syntax_errors [SyntaxError, TokenMissingError, MismatchedDelimiterError]

  # Every identifier in the script is parsed as this one atom -- see
  # `encode_syntax_atom/2`. The parser quotes the offending token back in some
  # of its messages, so the placeholder has to be swapped for what the author
  # actually wrote before the message is shown to them.
  @placeholder :support_script_syntax_atom
  @placeholder_name Atom.to_string(@placeholder)
  @token ~r/^:?[\p{L}_][\p{L}\p{N}_]*[?!]?/u

  schema "scripts" do
    belongs_to(:product, Product)
    belongs_to(:created_by, User, where: [deleted_at: nil])
    belongs_to(:last_updated_by, User, where: [deleted_at: nil])

    field(:name, :string)
    field(:text, :string)
    field(:language, Ecto.Enum, values: @languages, default: :elixir)
    field(:tags, Tag)
    field(:last_editor_name, :string, virtual: true)

    timestamps()
  end

  @doc """
  The languages a support script can be written in.
  """
  @spec languages() :: [language(), ...]
  def languages(), do: @languages

  @doc """
  A human readable name for a script's language.
  """
  @spec language_label(language() | nil) :: String.t()
  def language_label(:elixir), do: "Elixir"
  def language_label(:shell), do: "Shell"
  def language_label(nil), do: language_label(:elixir)

  def validate_changeset(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, @required ++ @optional)
    |> validate_required(@required)
    |> validate_length(:name, lte: 255)
    |> validate_syntax()
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

  # Only Elixir is checked. Shell text is stored as written: validating it would
  # mean either shelling out to a `bash` the release image is not guaranteed to
  # have, or carrying a shell parser, and neither is worth it to catch what the
  # script's own output will show on the first run.
  defp validate_syntax(changeset) do
    case get_field(changeset, :language) do
      :elixir -> validate_elixir_syntax(changeset)
      _other -> changeset
    end
  end

  defp validate_elixir_syntax(changeset) do
    validate_change(changeset, :text, fn :text, text ->
      case parse(text) do
        :ok ->
          []

        {:error, error} ->
          [text: "has invalid Elixir syntax at #{position(error)}: #{describe(error, text)}"]
      end
    end)
  end

  # `with_diagnostics/1` collects the warnings the parser would otherwise print
  # straight to stderr. The form validates on every change, so without it a
  # script full of deprecated syntax reprints its warnings into the logs on
  # every keystroke, attributed to nothing.
  defp parse(text) do
    {result, _diagnostics} =
      Code.with_diagnostics(fn ->
        try do
          _ = Code.string_to_quoted!(text, static_atoms_encoder: &encode_syntax_atom/2)
          :ok
        rescue
          error in @syntax_errors -> {:error, error}
        end
      end)

    result
  end

  defp position(%{line: line, column: column}) when is_integer(column) do
    "line #{line}, column #{column}"
  end

  defp position(%{line: line}), do: "line #{line}"

  defp describe(error, text) do
    String.replace(error.description, @placeholder_name, token_at(text, error) || "an identifier")
  end

  # The reported column is the start of the token the parser choked on, so the
  # author's own word can be read back out of the source. Anything that is not
  # an identifier there (an operator, a delimiter) leaves the message generic
  # rather than wrong.
  defp token_at(text, %{line: line, column: column}) when is_integer(column) do
    text
    |> String.split("\n")
    |> Enum.at(line - 1, "")
    |> String.slice((column - 1)..-1//1)
    |> then(&Regex.run(@token, &1))
    |> case do
      [token] -> token
      nil -> nil
    end
  end

  defp token_at(_text, _error), do: nil

  # The quoted result is discarded, so reusing one atom avoids growing the VM's atom table
  # with identifiers supplied through the form.
  defp encode_syntax_atom(_name, _metadata), do: {:ok, @placeholder}
end
