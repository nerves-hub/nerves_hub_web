defmodule NervesHubWWWWeb.ActionBtnView do


  def render(template, opts \\ [])
  def render("success.json", %{html: html}) do
    %{
      status: :ok,
      html: html
    }
  end

  def render("success.json", _opts) do
    %{status: :ok}
  end

  def render("error.json", %{html: html}) do
    %{
      status: :err,
      html: html
    }
  end

  def render("error.json", _opts) do
    %{
      status: :err
    }
  end
end

