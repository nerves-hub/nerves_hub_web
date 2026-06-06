defmodule NervesHub.Accounts.UserCLISession do
  use Memento.Table, attributes: [:token, :status, :expires_at, :user_token, :user_id]
end
