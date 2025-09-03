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
      key: key.key,
      name: key.name
    }
  end
end
