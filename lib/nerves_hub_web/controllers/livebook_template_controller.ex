defmodule NervesHubWeb.LivebookTemplateController do
  use NervesHubWeb, :controller

  def generate(conn, params) do
    decoded =
      params["encoded_params"]
      |> Base.decode64!(padding: false)
      |> JSON.decode!()

    output = template(decoded["node"], decoded["cookie"])

    conn
    |> markdown_content_type()
    |> send_resp(200, to_string(output))
  end

  defp markdown_content_type(%Plug.Conn{resp_headers: resp_headers} = conn) do
    %{conn | resp_headers: [{"content-type", "text/markdown"} | resp_headers]}
  end

  defp template(node_hostname, cookie) do
    attrs =
      %{
        "assign_to" => "",
        "code" => "Toolshed.uname()\n\nToolshed.uptime()\n\nToolshed.hostname()",
        "cookie_source" => "text",
        "cookie_text" => cookie,
        "node_source" => "text",
        "node_text" => node_hostname
      }
      |> JSON.encode!()
      |> Base.encode64(padding: false)

    ~s"""
    # Live Nerves Device

    ```elixir
    Mix.install([
      {:kino, "~> 0.15.0"}
    ])
    ```

    ## Section

    <!-- livebook:{"attrs":"#{attrs}","chunks":null,"kind":"Elixir.Kino.RemoteExecutionCell","livebook_object":"smart_cell"} -->

    ```elixir
    require Kino.RPC
    node = :"#{node_hostname}"
    Node.set_cookie(node, :"#{cookie}")

    Kino.RPC.eval_string(
      node,
      ~S\"\"\"
      Toolshed.uname()

      Toolshed.uptime()

      Toolshed.hostname()
      \"\"\",
      file: __ENV__.file
    )
    ```

    ```elixir

    ```
    """
  end
end
