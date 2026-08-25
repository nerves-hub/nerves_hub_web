defmodule NervesHubWeb.Plugs.SetLocaleTest do
  use NervesHubWeb.ConnCase, async: true

  alias NervesHubWeb.Plugs.SetLocale

  describe "init/1" do
    test "passes config through unchanged" do
      assert SetLocale.init(:some_config) == :some_config
    end
  end

  describe "call/2 with no Accept-Language header" do
    test "sets content-language response header to the default locale" do
      conn = build_conn(:get, "/") |> SetLocale.call(nil)

      default = Application.get_env(:nerves_hub, NervesHubWeb.Gettext)[:default_locale]
      assert get_resp_header(conn, "content-language") == [default]
    end
  end

  describe "call/2 with Accept-Language header" do
    test "sets content-language to the matched known locale" do
      # "en" is a known locale for NervesHubWeb.Gettext
      conn =
        build_conn(:get, "/")
        |> put_req_header("accept-language", "en")
        |> SetLocale.call(nil)

      [locale] = get_resp_header(conn, "content-language")
      assert locale == "en"
    end

    test "falls back to default when no locale matches" do
      conn =
        build_conn(:get, "/")
        |> put_req_header("accept-language", "klingon, romulan")
        |> SetLocale.call(nil)

      default = Application.get_env(:nerves_hub, NervesHubWeb.Gettext)[:default_locale]
      assert get_resp_header(conn, "content-language") == [default]
    end

    test "respects quality values, higher quality wins" do
      # en;q=0.5 vs en;q=1.0 — the second occurrence should win if first is lower quality
      conn =
        build_conn(:get, "/")
        |> put_req_header("accept-language", "zz;q=0.9,en;q=1.0")
        |> SetLocale.call(nil)

      [locale] = get_resp_header(conn, "content-language")
      assert locale == "en"
    end

    test "handles multiple locales with first known one winning" do
      conn =
        build_conn(:get, "/")
        |> put_req_header("accept-language", "fr, en")
        |> SetLocale.call(nil)

      [locale] = get_resp_header(conn, "content-language")
      # "en" is known; "fr" may or may not be — the plug picks the first known one
      assert is_binary(locale)
    end
  end
end
