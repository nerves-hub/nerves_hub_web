defmodule NervesHubWeb.API.ScriptView do
  use NervesHubWeb, :api_view

  def render("index.json", %{scripts: scripts}) do
    %{
      data: render_many(scripts, __MODULE__, "script.json")
    }
  end

  def render("script.json", %{script: script}) do
    %{
      id: script.id,
      name: script.name,
      text: script.text
    }
  end
end
