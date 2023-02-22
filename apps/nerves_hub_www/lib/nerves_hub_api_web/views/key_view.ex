defmodule NervesHubAPIWeb.KeyView do
  use NervesHubAPIWeb, :view
  alias NervesHubAPIWeb.KeyView

  def render("index.json", %{keys: keys}) do
    %{data: render_many(keys, KeyView, "key.json")}
  end

  def render("show.json", %{key: key}) do
    %{data: render_one(key, KeyView, "key.json")}
  end

  def render("key.json", %{key: key}) do
    %{
      name: key.name,
      key: key.key
    }
  end
end
