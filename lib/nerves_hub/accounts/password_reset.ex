defmodule NervesHub.Accounts.PasswordReset do
  use Ecto.Schema

  import Ecto.Changeset

  alias __MODULE__
  @type t :: %__MODULE__{}

  @optional_params []
  @required_params [:email]
  schema "password_resets" do
    field(:email, :string, virtual: true)
  end

  def changeset(%PasswordReset{} = password_reset, params) do
    password_reset
    |> cast(params, @required_params ++ @optional_params)
    |> validate_required(@required_params)
  end
end
