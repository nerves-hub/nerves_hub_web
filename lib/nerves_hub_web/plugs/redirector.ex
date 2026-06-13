defmodule NervesHubWeb.Plugs.Redirector do
  import Phoenix.Controller, only: [redirect: 2]

  @spec init(Keyword.t()) :: Keyword.t()
  def init([to: _] = opts), do: opts
  def init([external: _] = opts), do: opts
  def init(_default), do: raise("Missing required to: / external: option in redirect")

  @spec call(Plug.Conn.t(), Keyword.t()) :: Plug.Conn.t()
  def call(conn, to: to) do
    redirect(conn, to: append_query_string(conn, to))
  end

  def call(conn, external: url) do
    external =
      url
      |> URI.parse()
      |> merge_query_string(conn)
      |> URI.to_string()

    redirect(conn, external: external)
  end

  @spec append_query_string(Plug.Conn.t(), String.t()) :: String.t()
  defp append_query_string(%Plug.Conn{query_string: ""}, path), do: path
  defp append_query_string(%Plug.Conn{query_string: query}, path), do: "#{path}?#{query}"

  @spec merge_query_string(URI.t(), Plug.Conn.t()) :: URI.t()
  defp merge_query_string(%URI{query: nil} = destination_uri, %Plug.Conn{query_string: source}) do
    %{destination_uri | query: source}
  end

  defp merge_query_string(%URI{query: destination} = destination_uri, %Plug.Conn{query_string: source}) do
    merged_query =
      Map.merge(
        URI.decode_query(destination),
        URI.decode_query(source)
      )

    %{destination_uri | query: URI.encode_query(merged_query)}
  end
end
