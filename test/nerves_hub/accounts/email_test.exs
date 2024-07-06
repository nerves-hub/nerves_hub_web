defmodule NervesHub.Accounts.EmailTest do
  use ExUnit.Case, async: true

  import Swoosh.TestAssertions

  alias NervesHub.Accounts.{SwooshEmail, User}
  alias NervesHub.EmailView
  alias NervesHub.SwooshMailer

  test "invite email" do
    invite = %{email: "foo@bar.com", token: "token"}
    org = %{name: "My Org Name"}

    email = SwooshEmail.invite(invite, org, %User{name: "Tony"})

    assert email.to == [{"", invite.email}]
    assert email.html_body =~ org.name
    assert email.html_body =~ "#{EmailView.base_url()}/invite/#{invite.token}"
  end

  test "forgot_password email" do
    user = %{
      name: "Sad Guy",
      email: "sad_guy@forgot_password.com",
      password_reset_token: "ultrarandomresettoken"
    }

    email = SwooshEmail.forgot_password(user)

    assert email.to == [{"", user.email}]
    assert email.html_body =~ user.name

    assert email.html_body =~
             "#{EmailView.base_url()}/password-reset/#{user.password_reset_token}"
  end

  test "org user created email" do
    org = %{name: "My Org Name"}

    email = SwooshEmail.org_user_created("nunya@bidness.com", org, %User{name: "Tony"})

    assert email.to == [{"", "nunya@bidness.com"}]

    assert email.html_body =~
             "You've been added to the <strong>#{org.name}</strong> organization on #{EmailView.base_url()} by Tony."
  end

  test "tell org about new user" do
    org = %{name: "My Org Name"}

    new_user = %{
      name: "Happy Guy",
      email: "happy_guy@knows_password.com",
      password_reset_token: "ultrarandomresettoken"
    }

    org_users_emails = ["abc@def.com", "ghi@jkl.com", "mno@pqr.com"]

    org_users =
      Enum.map(org_users_emails, fn email ->
        %{user: %{email: email}}
      end)

    email =
      SwooshEmail.tell_org_user_added(org, org_users, %User{name: "Instigator"}, new_user)

    # Not sending new guy this email
    refute "happy_guy@knows_password.com" in email.bcc

    Enum.each(org_users_emails, fn user_email ->
      assert {"", user_email} in email.bcc
    end)

    email |> SwooshMailer.deliver()

    assert_email_sent(subject: "Instigator added #{new_user.name} to #{org.name}")
  end

  test "tell org about removing a user" do
    org = %{name: "My Org Name"}

    user = %{
      name: "Sad Guy",
      email: "sad_guy@knows_password.com",
      password_reset_token: "ultrarandomresettoken"
    }

    org_users_emails = ["abc@def.com", "ghi@jkl.com", "mno@pqr.com"]

    org_users =
      Enum.map(org_users_emails, fn email ->
        %{user: %{email: email}}
      end)

    email = SwooshEmail.tell_org_user_removed(org, org_users, %User{name: "Instigator"}, user)

    # Not sending new guy this email
    refute "sad_guy@knows_password.com" in email.bcc

    Enum.each(org_users_emails, fn user_email ->
      assert {"", user_email} in email.bcc
    end)

    email |> SwooshMailer.deliver()

    assert_email_sent(subject: "Instigator removed #{user.name} from #{org.name}")
  end
end
