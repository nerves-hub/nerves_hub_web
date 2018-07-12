defmodule NervesHubWeb.SessionView do
  use NervesHubWeb, :view

  def permit_uninvited_signups do
    Application.get_env(:nerves_hub, NervesHubWeb.AccountController)[:allow_signups]
  end
end
