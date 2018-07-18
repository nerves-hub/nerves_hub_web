defmodule NervesHub.Accounts.Email do
  use Bamboo.Phoenix, view: NervesHubWeb.EmailView

  alias NervesHubCore.Accounts.{Invite, Tenant, User}

  @from {"NervesHub", "no-reply@nerves-hub.org"}

  def invite(%Invite{} = invite, %Tenant{} = tenant) do
    new_email()
    |> from(@from)
    |> to(invite.email)
    |> subject("Welcome to NervesHub!")
    |> put_layout({NervesHubWeb.LayoutView, :email})
    |> render("invite.html", invite: invite, tenant: tenant)
  end

  def forgot_password(%User{email: email, password_reset_token: token} = user)
      when is_binary(token) do
    new_email()
    |> from(@from)
    |> to(email)
    |> subject("Reset NervesHub Password")
    |> put_layout({NervesHubWeb.LayoutView, :email})
    |> render("forgot_password.html", user: user)
  end
end
