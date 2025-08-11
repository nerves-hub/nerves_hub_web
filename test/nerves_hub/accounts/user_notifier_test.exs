defmodule NervesHub.Accounts.UserNotifierTest do
  use NervesHub.DataCase

  import Swoosh.X.TestAssertions

  alias NervesHub.Accounts
  alias NervesHub.Accounts.User
  alias NervesHub.Accounts.UserNotifier

  alias NervesHub.Fixtures

  test "invite email" do
    invite = %{email: "foo@bar.com", token: "token"}
    org = %{name: "My Org Name"}

    {:ok, email} =
      UserNotifier.deliver_user_invite(
        invite.email,
        org,
        %User{name: "Tony"},
        "/invite/token"
      )

    assert email.to == [{"", invite.email}]
    assert email.html_body =~ org.name
    assert email.html_body =~ "/invite/#{invite.token}"
  end

  test "forgot_password email" do
    user = %User{
      name: "Sad Guy",
      email: "sad_guy@forgot_password.com"
    }

    password_reset_token = "ultrarandomresettoken"

    {:ok, email} =
      UserNotifier.deliver_reset_password_instructions(
        user,
        "/password-reset/#{password_reset_token}"
      )

    assert email.to == [{"", user.email}]
    assert email.html_body =~ user.name

    assert email.html_body =~
             "/password-reset/#{password_reset_token}"
  end

  test "org user created email" do
    org = %{name: "My Org Name"}

    user = %User{
      name: "Tony",
      email: "tony@salami.com"
    }

    invited_by = %User{
      name: "Baloney",
      email: "baloney@curedmeats.com"
    }

    {:ok, email} =
      UserNotifier.deliver_org_user_added(
        org,
        user,
        invited_by
      )

    assert email.to == [{"", "tony@salami.com"}]

    assert email.html_body =~
             "You've been added to the <strong>My Org Name</strong> organization by <strong>Baloney</strong>."
  end

  test "tell org about new user" do
    paul = Fixtures.user_fixture(name: "Paul", email: "paul@thebeatles.com")
    john = Fixtures.user_fixture(name: "John", email: "john@thebeatles.com")
    ringo = Fixtures.user_fixture(name: "Ringo", email: "ringo@thebeatles.com")
    george = Fixtures.user_fixture(name: "George", email: "george@thebeatles.com")

    the_band = Fixtures.org_fixture(paul, %{name: "TheBeatles"})

    Accounts.add_org_user(the_band, john, %{role: :admin})
    Accounts.add_org_user(the_band, ringo, %{role: :admin})
    Accounts.add_org_user(the_band, george, %{role: :admin})

    tony = Fixtures.user_fixture(name: "Tony", email: "tony@salami.com")

    UserNotifier.deliver_all_tell_org_user_added(the_band, paul, tony)

    assert_email_sent(to: john.email, subject: "NervesHub: Tony has been added to TheBeatles")
    assert_email_sent(to: ringo.email, subject: "NervesHub: Tony has been added to TheBeatles")
    assert_email_sent(to: george.email, subject: "NervesHub: Tony has been added to TheBeatles")

    refute_email_sent(to: "paul@thebeatles.com")
  end

  test "tell org about removing a user" do
    paul = Fixtures.user_fixture(name: "Paul", email: "paul@thebeatles.com")
    john = Fixtures.user_fixture(name: "John", email: "john@thebeatles.com")
    ringo = Fixtures.user_fixture(name: "Ringo", email: "ringo@thebeatles.com")
    george = Fixtures.user_fixture(name: "George", email: "george@thebeatles.com")

    the_band = Fixtures.org_fixture(paul, %{name: "TheBeatles"})

    Accounts.add_org_user(the_band, john, %{role: :admin})
    Accounts.add_org_user(the_band, ringo, %{role: :admin})
    Accounts.add_org_user(the_band, george, %{role: :admin})

    tony = Fixtures.user_fixture(name: "Tony", email: "tony@salami.com")

    UserNotifier.deliver_all_tell_org_user_removed(the_band, paul, tony)

    assert_email_sent(to: john.email, subject: "NervesHub: Tony has been removed from TheBeatles")

    assert_email_sent(
      to: ringo.email,
      subject: "NervesHub: Tony has been removed from TheBeatles"
    )

    assert_email_sent(
      to: george.email,
      subject: "NervesHub: Tony has been removed from TheBeatles"
    )

    refute_email_sent(to: "paul@thebeatles.com")
  end
end
