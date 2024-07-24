defmodule NervesHubWeb.API.ErrorView do
  use NervesHubWeb, :api_view

  def render("401.json", _) do
    %{errors: %{detail: "Not Authenticated"}}
  end

  def render("404.json", _) do
    %{errors: %{detail: "Resource Not Found or Authorization Insufficient"}}
  end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.json" becomes
  # "Not Found".
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
