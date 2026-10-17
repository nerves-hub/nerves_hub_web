defmodule NervesHubWeb.LayoutsTest do
  # Sets the Featurebase signing key in the application env.
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest

  alias NervesHubWeb.Layouts

  @user %{name: "Ada", email: "ada@example.com", id: 42, inserted_at: ~N[2026-01-02 03:04:05]}

  setup do
    previous = Application.get_env(:nerves_hub, :featurebase_signing_token)
    on_exit(fn -> Application.put_env(:nerves_hub, :featurebase_signing_token, previous) end)
  end

  defp render_sdk() do
    render_component(&Layouts.featurebase_sdk/1, current_scope: %{user: @user}, app_id: "app")
  end

  describe "featurebase_sdk/1" do
    test "boots Featurebase with an HS256 JWT of the user's details" do
      Application.put_env(:nerves_hub, :featurebase_signing_token, "signing-key")

      [jwt] = Regex.run(~r/featurebaseJwt: "([^"]+)"/, render_sdk(), capture: :all_but_first)
      [header, payload, signature] = String.split(jwt, ".")

      expected = :crypto.mac(:hmac, :sha256, "signing-key", header <> "." <> payload)
      assert Base.url_decode64!(signature, padding: false) == expected

      assert header |> Base.url_decode64!(padding: false) |> JSON.decode!() == %{"alg" => "HS256", "typ" => "JWT"}

      assert payload |> Base.url_decode64!(padding: false) |> JSON.decode!() == %{
               "name" => "Ada",
               "email" => "ada@example.com",
               "userId" => "42",
               "createdAt" => "2026-01-02 03:04:05",
               "theme" => "light",
               "language" => "en"
             }
    end

    test "renders nothing without a signing key" do
      Application.put_env(:nerves_hub, :featurebase_signing_token, nil)

      refute render_sdk() =~ "Featurebase"
    end
  end
end
