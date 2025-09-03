defmodule NervesHubWeb.API.ScriptJSON do
  @moduledoc false

  def index(%{scripts: scripts}) do
    %{
      data: for(script <- scripts, do: script(script))
    }
  end

  defp script(script) do
    %{
      id: script.id,
      name: script.name,
      tags: script.tags,
      text: script.text
    }
  end
end
