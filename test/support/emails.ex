defmodule NervesHub.Support.Emails do
  @moduledoc """
  Emails are delivered from `NervesHub.Workers.SendEmail` jobs, and the test
  environment runs Oban in `:manual` mode, so queueing one doesn't send it.

  Call `send_queued_emails/0` between the code under test and any
  `assert_email_sent/1`. It drains the queue in the calling process, which is
  what puts the message in the test's mailbox for the Swoosh assertions to find.
  """

  def send_queued_emails() do
    Oban.drain_queue(queue: :email)
  end
end
