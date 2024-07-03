defmodule NervesHub.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Changeset

  alias NervesHub.Accounts.User

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
    |> cast(attrs, [:note, :user_id])
    |> update_change(:note, &trim/1)
    |> put_change(:token, generate(user))
    |> validate_required([:token, :note, :user_id])
    |> validate_format(:token, ~r/^nhu_[a-zA-Z0-9]{36}$/)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:token)
  end

  defp generate(user) do
    secret =
      <<user.name::binary, user.email::binary, DateTime.to_unix(DateTime.utc_now())::32>>

    <<initial::160>> = Plug.Crypto.KeyGenerator.generate(secret, "user-#{user.id}", length: 20)

    # Make sure we only have 30 bytes of Base62 to enforce a 36 digit token with prefix
    <<rand::30-bytes, _::binary>> = Base62.encode(initial) |> String.pad_leading(30, "0")
    crc = :erlang.crc32(rand) |> Base62.encode() |> String.pad_leading(6, "0")

    "nhu_#{rand}#{crc}"
  end

  defp trim(string) when is_binary(string) do
    string
    |> String.split(" ", trim: true)
    |> Enum.join(" ")
  end

  defp trim(string), do: string
end
