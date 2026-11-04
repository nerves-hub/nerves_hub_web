defmodule NervesHub.Workers.SendEmail do
  @moduledoc """
  Renders and delivers one email.

  The job carries the recipient, a template key and that template's assigns
  rather than a rendered message, so both the rendering and the SMTP
  conversation happen here instead of in the web request that asked for the
  email. See `NervesHub.Accounts.UserNotifier` for the functions that queue
  these jobs.

  A recipient that `NervesHub.Accounts.EmailAddress.valid?/1` rejects cancels
  the job: the SMTP adapter would raise on every attempt. New addresses are
  checked when they are entered, so this only catches ones stored before that
  check existed.
  """

  use Oban.Worker,
    queue: :email,
    max_attempts: 5

  alias NervesHub.Accounts.EmailAddress
  alias NervesHub.Accounts.UserNotifier

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"template" => template, "to" => recipient, "assigns" => assigns}}) do
    if EmailAddress.valid?(recipient) do
      with {:ok, _email} <- UserNotifier.render_and_deliver(template, recipient, assigns) do
        :ok
      end
    else
      {:cancel, :invalid_recipient}
    end
  end
end
