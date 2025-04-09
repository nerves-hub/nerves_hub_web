defmodule NervesHubWeb.API.KeyJSON do
  @moduledoc false

  def index(%{keys: keys}) do
    %{data: for(key <- keys, do: key(key))}
  end

  def show(%{key: key}) do
    %{data: key(key)}
  end

  def key(key) do
    %{
      name: key.name,
      key: key.key
    }
  end
end
