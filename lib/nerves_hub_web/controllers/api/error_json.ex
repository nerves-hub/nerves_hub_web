defmodule NervesHubWeb.API.ErrorJSON do
  @moduledoc false

  def render("401.json", _) do
    %{errors: %{detail: "Resource Not Found or Authorization Insufficient"}}
  end

  def render("404.json", _) do
    %{errors: %{detail: "Resource Not Found or Authorization Insufficient"}}
  end

  def render("400.json", %{reason: reason}) do
    %{errors: %{detail: reason}}
  end

  def render("422.json", %{reason: reason}) do
    %{errors: %{detail: reason}}
  end

  def render("500.json", %{reason: reason}) do
    %{errors: %{detail: reason}}
  end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.json" becomes
  # "Not Found".
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
