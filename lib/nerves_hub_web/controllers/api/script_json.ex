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
      text: script.text,
      tags: script.tags
    }
  end
end
