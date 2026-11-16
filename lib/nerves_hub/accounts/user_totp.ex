defmodule NervesHub.Accounts.UserTOTP do
  @moduledoc """
  A user's authenticator app: the TOTP secret it shares with NervesHub, and
  the recovery codes for signing in without it.

  A user has two-factor authentication on exactly when they have one of
  these. See `NervesHub.Accounts.TwoFactor`.
  """
  use Ecto.Schema

  alias NervesHub.Accounts.User
  alias NervesHub.Types.Encrypted

  @type t :: %__MODULE__{}

  schema "user_totps" do
    belongs_to(:user, User)

    field(:secret, Encrypted, redact: true)
    field(:last_used_at, :utc_datetime)
    field(:recovery_codes, {:array, :binary}, default: [], redact: true)

    timestamps()
  end
end
