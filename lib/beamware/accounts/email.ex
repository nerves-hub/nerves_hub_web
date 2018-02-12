defmodule Beamware.Accounts.Email do
  use Phoenix.Swoosh, view: BeamwareWeb.EmailView, layout: {BeamwareWeb.LayoutView, :email}

  alias Beamware.Accounts.{Invite, Tenant}
  alias Beamware.Mailer
  alias Swoosh.Email

  @from {"Beamware", "no-reply@beamware.io"}

  def send(:invite, %Invite{} = invite, %Tenant{} = tenant) do
    %Email{}
    |> from(@from)
    |> to(invite.email)
    |> subject("Welcome to Beamware!")
    |> render_body("invite.html", invite: invite, tenant: tenant)
    |> Mailer.deliver()
  end
end
