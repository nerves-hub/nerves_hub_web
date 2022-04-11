defmodule NervesHubWebCore.Accounts.UserToken do
  use Ecto.Schema

  alias Ecto.Changeset
  alias NervesHubWebCore.Accounts.User

  @type t :: %__MODULE__{}

  schema "user_tokens" do
    belongs_to(:user, User)

    field(:token, :string)
    field(:note, :string)
    field(:last_used, :utc_datetime)

    timestamps()
  end

  def create_changeset(%User{} = user, attrs) do
    %__MODULE__{user_id: user.id}
    |> Changeset.cast(attrs, [:note, :user_id])
    |> Changeset.put_change(:token, generate(user))
    |> Changeset.validate_required([:token, :note, :user_id])
    |> Changeset.validate_format(:token, ~r/^nhu_[a-zA-Z0-9]{36}$/)
    |> Changeset.foreign_key_constraint(:user_id)
    |> Changeset.unique_constraint(:token)
  end

  def update_chagneset(%__MODULE__{} = token, attrs) do
    Changeset.cast(token, attrs, [:note, :last_used])
  end

  defp generate(user) do
    secret =
      <<user.username::binary, user.email::binary, DateTime.to_unix(DateTime.utc_now())::32>>

    <<initial::160>> = Plug.Crypto.KeyGenerator.generate(secret, "user-#{user.id}", length: 20)

    # Make sure we only have 30 bytes of Base62 to enforce a 36 digit token with prefix
    <<rand::30-bytes, _::binary>> = Base62.encode(initial) |> String.pad_leading(30, "0")
    crc = :erlang.crc32(rand) |> Base62.encode() |> String.pad_leading(6, "0")

    "nhu_#{rand}#{crc}"
  end
end
