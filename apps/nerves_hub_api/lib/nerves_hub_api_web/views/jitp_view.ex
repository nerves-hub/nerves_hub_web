defmodule NervesHubAPIWeb.JITPView do
  use NervesHubAPIWeb, :view
  alias NervesHubAPIWeb.JITPView

  def render("show.json", %{jitp: jitp}) do
    %{data: render_one(jitp, JITPView, "jitp.json")}
  end

  def render("jitp.json", %{jitp: jitp}) do
    %{
      product: jitp.product.name,
      description: jitp.description,
      tags: jitp.tags
    }
  end
end
