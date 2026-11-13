defmodule NervesHub.Workers.SendEmailTest do
  use NervesHub.DataCase, async: true

  import Swoosh.X.TestAssertions

  alias NervesHub.Workers.SendEmail

  test "cancels an email to an address the mailer can't send to" do
    args = %{template: "welcome", to: "lil.i.a.n...lec.a.ros@gmail.com", assigns: %{user_name: "Jane"}}

    assert {:cancel, :invalid_recipient} = perform_job(SendEmail, args)
    refute_email_sent()
  end

  test "sends an email to a valid address" do
    args = %{template: "welcome", to: "jane@example.com", assigns: %{user_name: "Jane"}}

    assert :ok = perform_job(SendEmail, args)
    assert_email_sent(to: "jane@example.com", subject: "NervesHub: Welcome Jane!")
  end
end
