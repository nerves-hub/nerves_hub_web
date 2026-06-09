defmodule NervesHub.Workers.DeleteExpiredCLISessionRecords do
  use Oban.Worker,
    queue: :cleanup,
    max_attempts: 1

  alias NervesHub.Accounts

  @impl Oban.Worker
  def perform(_) do
    Accounts.delete_expired_cli_session_records()
    :ok
  end
end
