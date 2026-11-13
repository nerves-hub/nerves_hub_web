defmodule NervesHub.Accounts.UserCLISession do
  @moduledoc """
  A CLI login waiting for someone signed in to the web to confirm it.

  The CLI holds `token`, which it polls with, and shows its user
  `confirmation_code`, which they type in on the web to find the login.
  `requested_at` and `requested_from` say when and from where the CLI started
  it, so whoever confirms can tell whether it was them.
  """

  @type t() :: %__MODULE__{
          confirmation_code: pos_integer() | nil,
          expires_at: integer() | nil,
          note: String.t() | nil,
          requested_at: integer() | nil,
          requested_from: String.t() | nil,
          status: :waiting | :ready | :verified | nil,
          token: String.t() | nil,
          user_id: pos_integer() | nil,
          user_token: String.t() | nil
        }

  defstruct [
    :confirmation_code,
    :expires_at,
    :note,
    :requested_at,
    :requested_from,
    :status,
    :token,
    :user_id,
    :user_token
  ]
end
