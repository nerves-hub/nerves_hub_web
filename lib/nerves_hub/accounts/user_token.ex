defmodule NervesHub.Accounts.UserToken do
  use Ecto.Schema

  import Ecto.Query

  alias NervesHub.Accounts.User

  @rand_size 32
  @hash_algorithm :sha512

  @session_validity_in_days 60

  @type t :: %__MODULE__{}

  schema "user_tokens" do
    belongs_to(:user, User)

    field(:token, :string)
    field(:context, :string)
    field(:note, :string)

    field(:last_used, :utc_datetime)

    timestamps()
  end

  @doc """
  Generates a token that will be stored in a signed place,
  such as session or cookie. As they are signed, those
  tokens do not need to be hashed.

  The reason why we store session tokens in the database, even
  though Phoenix already provides a session cookie, is because
  Phoenix' default session cookies are not persisted, they are
  simply signed and potentially encrypted. This means they are
  valid indefinitely, unless you change the signing/encryption
  salt.

  Therefore, storing them allows individual user
  sessions to be expired.
  """
  def build_session_token(user, note) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %__MODULE__{token: token, context: "session", user_id: user.id, note: trim(note)}}
  end

  @doc """
  Builds a token and its hash to be used in instances where a tokens storage is not
  guaranteed to be secure.

  For example, the non-hashed token can be sent to the user's email while the
  hashed part is stored in the database. The original token cannot be reconstructed,
  which means anyone with read-only access to the database cannot directly use
  the token in the application to gain access.
  """
  def build_hashed_token(user, context, note) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    friendly_token = "nhu_" <> Base.url_encode64(token, padding: false)

    {friendly_token,
     %__MODULE__{
       token: hashed_token,
       context: context,
       note: trim(note),
       user_id: user.id
     }}
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the User found by the token, if any.

  The token is valid if it matches the value in the database and it has
  not expired (after @session_validity_in_days).
  """
  def verify_session_token_query(token) do
    query =
      from(token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        where: is_nil(user.deleted_at),
        select: user
      )

    {:ok, query}
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the User found by the token, if any.
  """
  def verify_api_token_query(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from(token in by_token_and_context_query(hashed_token, "api"),
            join: user in assoc(token, :user),
            where: is_nil(user.deleted_at),
            select: user
          )

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc """
  Checks if the token is valid and returns a query for updating the `last_used` field.
  """
  def mark_last_used_query(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)
        query = by_token_and_context_query(hashed_token, "api")
        {:ok, query}

      :error ->
        :error
    end
  end

  @doc """
  Returns the token struct for the given token value and context.
  """
  def by_token_and_context_query(token, context) do
    from(__MODULE__, where: [token: ^token, context: ^context])
  end

  defp trim(string) when is_binary(string) do
    string
    |> String.split(" ", trim: true)
    |> Enum.join(" ")
  end

  defp trim(string), do: string
end
