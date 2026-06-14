defmodule NervesHub.Accounts.UserCLISession do
  defstruct [
    :confirmation_code,
    :expires_at,
    :note,
    :status,
    :token,
    :user_id,
    :user_token
  ]
end
