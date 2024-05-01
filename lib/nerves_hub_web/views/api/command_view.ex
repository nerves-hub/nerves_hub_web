defmodule NervesHubWeb.API.CommandView do
  use NervesHubWeb, :api_view

  def render("index.json", %{commands: commands}) do
    %{
      data: render_many(commands, __MODULE__, "command.json")
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
