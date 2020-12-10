defmodule NervesHubWebCore.Accounts.EmailTest do
  use ExUnit.Case, async: true
  use Bamboo.Test

  alias NervesHubWebCore.Accounts.{Email, Invite, Org, OrgUser, User}
  alias NervesHubWebCore.{EmailView, Mailer}

  test "invite email" do
    invite = %Invite{email: "foo@bar.com"}
    org = %Org{name: "My Org Name"}

    email = Email.invite(invite, org)

    assert email.to == invite.email
    assert email.html_body =~ org.name
    assert email.html_body =~ "#{EmailView.base_url()}/invite/#{invite.token}"
  end

  test "forgot_password email" do
    user = %User{
      username: "sad_guy",
      email: "sad_guy@forgot_password.com",
      password_reset_token: "ultrarandomresettoken"
    }

    email = Email.forgot_password(user)

    assert email.to == user.email
    assert email.html_body =~ user.username

    assert email.html_body =~
             "#{EmailView.base_url()}/password-reset/#{user.password_reset_token}"
  end

  test "org user created email" do
    org = %Org{name: "My Org Name"}

    email = Email.org_user_created("nunya@bidness.com", org)

    assert email.to == "nunya@bidness.com"

    assert email.html_body =~
             "You've been added to the <strong>#{org.name}</strong> organization on #{
               EmailView.base_url()
             }."
  end

  test "tell org about new user" do
    org = %Org{name: "My Org Name"}

    new_user = %User{
      username: "happy_guy",
      email: "happy_guy@knows_password.com",
      password_reset_token: "ultrarandomresettoken"
    }

    org_users_emails = ["abc@def.com", "ghi@jkl.com", "mno@pqr.com"]

    org_users =
      org_users_emails
      |> Enum.map(fn email -> %OrgUser{user: %User{email: email}} end)

    email = Email.tell_org_user_added(org, org_users, "Instigator", new_user)
    # Not sending new guy this email
    refute "happy_guy@knows_password.com" in email.bcc

    Enum.each(org_users_emails, fn user_email ->
      assert user_email in email.bcc
    end)

    email |> Mailer.deliver_now()

    assert_email_delivered_with(
      subject: "[NervesHub] User Instigator added #{new_user.username} to #{org.name}"
    )
  end

  test "tell org about removing a user" do
    org = %Org{name: "My Org Name"}

    user = %User{
      username: "sad_guy",
      email: "sad_guy@knows_password.com",
      password_reset_token: "ultrarandomresettoken"
    }

    org_users_emails = ["abc@def.com", "ghi@jkl.com", "mno@pqr.com"]

    org_users =
      org_users_emails
      |> Enum.map(fn email -> %OrgUser{user: %User{email: email}} end)

    email = Email.tell_org_user_removed(org, org_users, "Instigator", user)
    # Not sending new guy this email
    refute "sad_guy@knows_password.com" in email.bcc

    Enum.each(org_users_emails, fn user_email ->
      assert user_email in email.bcc
    end)

    email |> Mailer.deliver_now()

    assert_email_delivered_with(
      subject: "[NervesHub] User Instigator removed #{user.username} from #{org.name}"
    )
  end
end
