defmodule NervesHubWWW.Accounts.EmailTest do
  use ExUnit.Case, async: true

  alias NervesHubWebCore.Accounts.{Invite, Org, User}
  alias NervesHubWWW.Accounts.Email
  alias NervesHubWWWWeb.EmailView

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
             "You've been added to the <strong>#{org.name}</strong> organization on nerves-hub.org."
  end
end
