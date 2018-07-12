defmodule NervesHub.Accounts.Email do
  use Phoenix.Swoosh, view: NervesHubWeb.EmailView, layout: {NervesHubWeb.LayoutView, :email}

  alias NervesHubCore.Accounts.{Invite, Tenant, User}
  alias NervesHub.Mailer
  alias Swoosh.Email

  @from {"NervesHub", "no-reply@nerves-hub.org"}

  def send(:invite, %Invite{} = invite, %Tenant{} = tenant) do
    %Email{}
    |> from(@from)
    |> to(invite.email)
    |> subject("Welcome to NervesHub!")
    |> render_body("invite.html", invite: invite, tenant: tenant)
    |> Mailer.deliver()
  end

  def send(:forgot_password, %User{email: email, password_reset_token: token} = user)
      when is_binary(token) do
    %Email{}
    |> from(@from)
    |> to(email)
    |> subject("Reset NervesHub Password")
    |> render_body("forgot_password.html", user: user)
    |> Mailer.deliver()
  end
end
