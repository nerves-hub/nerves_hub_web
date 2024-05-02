defmodule NervesHubWeb.API.ScriptView do
  use NervesHubWeb, :api_view

  def render("index.json", %{scripts: scripts}) do
    %{
      data: render_many(scripts, __MODULE__, "command.json")
    }
  end

  def render("command.json", %{command: command}) do
    %{
      id: command.id,
      name: command.name,
      text: command.text
    }
  end
end
