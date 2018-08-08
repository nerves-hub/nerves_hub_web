defmodule NervesHubWWWWeb.Controllers.ActionBtnHelpers do
  import Phoenix.Controller
  alias NervesHubWWWWeb.ActionBtnView

  def render_success(conn, template, assigns) do
    form_html = Phoenix.View.render_to_string(conn.private.phoenix_view, template, Keyword.merge([conn: conn], assigns))
   
    conn
    |> put_view(ActionBtnView)
    |> render("success.json", html: form_html)
  end

  def render_error(conn, template, assigns) do
    form_html = Phoenix.View.render_to_string(conn.private.phoenix_view, template, Keyword.merge([conn: conn], assigns))

    conn
    |> put_view(ActionBtnView)
    |> render("error.json", html: form_html)
  end

  def render_success(conn) do
    conn
    |> put_view(ActionBtnView)
    |> render("success.json", %{})
  end
end
