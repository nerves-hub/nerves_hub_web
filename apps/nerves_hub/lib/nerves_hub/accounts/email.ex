defmodule NervesHub.Accounts.Email do
  use Bamboo.Phoenix, view: NervesHubWeb.EmailView

  alias NervesHubCore.Accounts.{Invite, Tenant, User}
  alias NervesHub.Mailer

  @from {"NervesHub", "no-reply@nerves-hub.org"}

  def send(:invite, %Invite{} = invite, %Tenant{} = tenant) do
    new_email()
    |> from(@from)
    |> to(invite.email)
    |> subject("Welcome to NervesHub!")
    |> put_layout({NervesHubWeb.LayoutView, :email})
    |> render("invite.html", invite: invite, tenant: tenant)
    |> Mailer.deliver_now()
    |> IO.inspect
  end

  def send(:forgot_password, %User{email: email, password_reset_token: token} = user)
      when is_binary(token) do
    new_email()
    |> from(@from)
    |> to(email)
    |> subject("Reset NervesHub Password")
    |> put_layout({NervesHubWeb.LayoutView, :email})
    |> render("forgot_password.html", user: user)
    |> Mailer.deliver_now()
  end
end
