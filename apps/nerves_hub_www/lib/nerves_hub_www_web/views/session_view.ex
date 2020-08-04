defmodule NervesHubWWWWeb.SessionView do
  use NervesHubWWWWeb, :view

  def permit_uninvited_signups do
    Application.get_env(:nerves_hub_www, NervesHubWWWWeb.AccountController)[:allow_signups]
  end
end
