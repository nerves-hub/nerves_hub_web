defmodule NervesHub.Accounts.UserNotifierTest do
  use NervesHub.DataCase, async: true

  import NervesHub.Support.Emails
  import Swoosh.X.TestAssertions

  alias NervesHub.Accounts
  alias NervesHub.Accounts.User
  alias NervesHub.Accounts.UserNotifier
  alias NervesHub.Fixtures
  alias NervesHub.Workers.SendEmail

  test "emails are queued rather than sent" do
    user = %User{name: "Tony", email: "tony@salami.com"}

    {:ok, _job} = UserNotifier.deliver_welcome_email(user)

    assert_enqueued(worker: SendEmail, args: %{template: "welcome", to: user.email})
    refute_email_sent()

    send_queued_emails()

    assert_email_sent(to: user.email, subject: "NervesHub: Welcome Tony!")
  end

  test "invite email for someone without an account" do
    invite = %{email: "foo@bar.com", token: "token"}
    org = %{name: "My Org Name"}

    {:ok, _job} =
      UserNotifier.deliver_user_invite(
        invite.email,
        org,
        %User{name: "Tony"},
        "/invite/token",
        false
      )

    send_queued_emails()

    assert_email_sent(fn email ->
      assert email.to == [{"", invite.email}]
      assert email.html_body =~ org.name
      assert email.html_body =~ "/invite/#{invite.token}"
      assert email.html_body =~ "Create an account with"
    end)
  end

  test "invite email for someone who already has an account" do
    invite = %{email: "foo@bar.com", token: "token"}
    org = %{name: "My Org Name"}

    {:ok, _job} =
      UserNotifier.deliver_user_invite(
        invite.email,
        org,
        %User{name: "Tony"},
        "/invite/token",
        true
      )

    send_queued_emails()

    # assert_email_sent/1 uses this function as a predicate, so the last
    # expression has to be an assert - a trailing refute returns false and
    # reads as "no email matched"
    assert_email_sent(fn email ->
      assert email.to == [{"", invite.email}]
      assert email.html_body =~ "/invite/#{invite.token}"
      refute email.html_body =~ "Create an account with"
      assert email.html_body =~ "Accept the invitation"
    end)
  end

  test "forgot_password email" do
    user = %User{
      name: "Sad Guy",
      email: "sad_guy@forgot_password.com"
    }

    password_reset_token = "ultrarandomresettoken"

    {:ok, _job} =
      UserNotifier.deliver_reset_password_instructions(
        user,
        "/password-reset/#{password_reset_token}"
      )

    send_queued_emails()

    assert_email_sent(fn email ->
      assert email.to == [{"", user.email}]
      assert email.html_body =~ user.name
      assert email.html_body =~ "/password-reset/#{password_reset_token}"
    end)
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

    send_queued_emails()

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

    send_queued_emails()

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
