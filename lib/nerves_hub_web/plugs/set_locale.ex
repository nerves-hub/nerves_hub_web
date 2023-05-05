defmodule NervesHubWeb.Plugs.SetLocale do
  import Plug.Conn

  def init(default), do: default

  def call(conn, _config) do
    conn
    |> get_locale_from_header()
    |> case do
      nil ->
        conn
        |> put_resp_header(
          "content-language",
          Application.get_env(:nerves_hub, NervesHubWeb.Gettext)[:default_locale]
        )

      locale ->
        Gettext.put_locale(NervesHubWeb.Gettext, locale)

        conn
        |> put_resp_header("content-language", locale)
    end
  end

  defp get_locale_from_header(conn) do
    conn
    |> extract_accept_language()
    |> Enum.find(nil, fn accepted_locale ->
      Gettext.known_locales(NervesHubWeb.Gettext)
      |> Enum.member?(accepted_locale)
    end)
  end

  defp extract_accept_language(conn) do
    case Plug.Conn.get_req_header(conn, "accept-language") do
      [value | _] ->
        value
        |> String.split(",")
        |> Enum.map(&parse_language_option/1)
        |> Enum.sort(&(&1.quality > &2.quality))
        |> Enum.map(& &1.tag)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp parse_language_option(string) do
    captures = Regex.named_captures(~r/^\s?(?<tag>[\w\-]+)(?:;q=(?<quality>[\d\.]+))?$/i, string)

    quality =
      case Float.parse(captures["quality"] || "1.0") do
        {val, _} -> val
        _ -> 1.0
      end

    %{tag: captures["tag"], quality: quality}
  end
end
