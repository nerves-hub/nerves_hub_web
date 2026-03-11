defmodule NervesHubWeb.API.ErrorJSON do
  @moduledoc false

  def render("401.json", %{reason: reason}) when is_binary(reason) do
    %{errors: %{detail: reason}}
  end

  def render("401.json", _assigns) do
    %{errors: %{detail: "Resource Not Found or Authorization Insufficient"}}
  end

  def render("403.json", %{message: message}) do
    %{errors: %{detail: message}}
  end

  def render("404.json", _) do
    %{errors: %{detail: "Resource Not Found or Authorization Insufficient"}}
  end

  def render("400.json", %{reason: reason}) do
    message =
      cond do
        is_binary(reason) -> reason
        is_map(reason) && Map.has_key?(reason, :message) -> Map.get(reason, :message)
        true -> "Invalid request"
      end

    %{errors: %{detail: message}}
  end

  def render("422.json", %{reason: reason}) do
    %{errors: %{detail: reason}}
  end

  def render("500.json", _) do
    %{errors: %{detail: "Sorry, an unexpected error occurred. The masters of the web have been notified."}}
  end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.json" becomes
  # "Not Found".
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
