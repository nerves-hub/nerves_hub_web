defmodule NervesHub.Accounts.UserToken do
  use Ecto.Schema

  import Ecto.Query

  alias NervesHub.Accounts.User
  alias NervesHub.Utils.Base62

  @rand_size 32
  @hash_algorithm :sha512

  @session_validity_in_days 60

  @type t :: %__MODULE__{}

  schema "user_tokens" do
    belongs_to(:user, User)

    field(:token, :binary)
    field(:context, :string)
    field(:note, :string)

    field(:last_used, :utc_datetime)

    # This is needed to keep the old token format working.
    # Safe to remove once we only support the new format.
    field(:old_token, :string)

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
    token = base62_safe_token()
    crc = :erlang.crc32(token)

    hashed_token = :crypto.hash(@hash_algorithm, token)

    friendly_token = "nhu_" <> Base62.encode(<<token::binary, crc::32>>)

    {friendly_token,
     %__MODULE__{
       token: hashed_token,
       context: context,
       note: trim(note),
       user_id: user.id
     }}
  end

  defp base62_safe_token() do
    case :crypto.strong_rand_bytes(@rand_size) do
      # Base62 is an integer based calculation and cannot
      # deal with leading null bytes since they are ignored
      # so we generate another one to avoid that problem
      <<0, _::binary>> -> base62_safe_token()
      token -> token
    end
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
  @spec verify_api_token_query(String.t()) :: {:ok, Ecto.Query.t()} | :error
  # TODO: This first match is the V1 token that will need to be removed when deprecated
  def verify_api_token_query(<<"nhu_", hmac::30-bytes, crc_str::6-bytes>> = token) do
    with {:ok, crc_bin} <- Base62.decode(crc_str),
         crc = :crypto.bytes_to_integer(crc_bin),
         :ok <- assert_crc(hmac, crc) do
      query =
        from(ut in __MODULE__,
          join: user in assoc(ut, :user),
          where: is_nil(user.deleted_at),
          where: ut.context == "api",
          where: ut.old_token == ^token,
          select: user
        )

      {:ok, query}
    else
      _ -> :error
    end
  end

  def verify_api_token_query(<<"nhu_", token_with_crc::binary>>) do
    with {:ok, <<token::32-bytes, crc::32>>} <- Base62.decode(token_with_crc),
         :ok <- assert_crc(token, crc) do
      hashed_token = :crypto.hash(@hash_algorithm, token)

      query =
        from(ut in by_token_and_context_query(hashed_token, "api"),
          join: user in assoc(ut, :user),
          where: is_nil(user.deleted_at),
          select: user
        )

      {:ok, query}
    else
      _ -> :error
    end
  end

  def verify_api_token_query(_token), do: :error

  defp assert_crc(token, crc) do
    if :erlang.crc32(token) == crc do
      :ok
    else
      :crc_mismatch
    end
  end

  @doc """
  Checks if the token is valid and returns a query for updating the `last_used` field.
  """
  def mark_last_used_query(token) do
    case verify_token_format(token) do
      {:ok, hashed_token} ->
        query = by_token_and_context_query(hashed_token, "api")

        {:ok, query}

      _ ->
        :error
    end
  end

  @spec verify_token_format(String.t()) :: {:ok, String.t()} | :crc_mismatch | :invalid
  def verify_token_format(token) do
    with <<"nh", _u, "_", token_with_crc::binary>> <- token,
         {:ok, <<token::32-bytes, crc::32>>} <- Base62.decode(token_with_crc),
         :ok <- assert_crc(token, crc) do
      {:ok, :crypto.hash(@hash_algorithm, token)}
    else
      :crc_mismatch ->
        :crc_mismatch

      _ ->
        :invalid
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
