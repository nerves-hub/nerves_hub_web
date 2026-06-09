defmodule NervesHubWeb.API.ScriptJSON do
  @moduledoc false

  def index(%{scripts: scripts, pagination: pagination}) do
    %{
      data: for(script <- scripts, do: script(script, :index)),
      pagination: pagination
    }
  end

  def show(%{script: script}) do
    %{
      data: script(script, :show)
    }
  end

  defp script(script, :index) do
    %{
      id: script.id,
      name: script.name,
      tags: script.tags
    }
  end

  defp script(script, :show) do
    %{
      id: script.id,
      name: script.name,
      text: script.text,
      tags: script.tags,
      inserted_at: script.inserted_at,
      updated_at: script.updated_at,
      created_by: %{
        id: script.created_by.id,
        name: script.created_by.name,
        email: script.created_by.email
      }
    }
  end
end
