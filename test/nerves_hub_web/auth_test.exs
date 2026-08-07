defmodule NervesHubWeb.AuthTest do
  # async: false because these tests mutate the global `:external_login_return_urls`
  # application env that `return_to_target/1` reads.
  use ExUnit.Case, async: false

  alias NervesHubWeb.Auth

  describe "return_to_target/1" do
    setup do
      previous = Application.get_env(:nerves_hub, :external_login_return_urls)

      Application.put_env(:nerves_hub, :external_login_return_urls, [
        "https://admin.example.com",
        "https://console.example.com:8443"
      ])

      on_exit(fn ->
        if previous do
          Application.put_env(:nerves_hub, :external_login_return_urls, previous)
        else
          Application.delete_env(:nerves_hub, :external_login_return_urls)
        end
      end)

      :ok
    end

    test "nil falls back to the default signed-in path" do
      assert Auth.return_to_target(nil) == :default
    end

    test "a local path passes through unchanged" do
      assert Auth.return_to_target("/orgs") == {:local, "/orgs"}
    end

    test "a local path keeps its query string" do
      assert Auth.return_to_target("/oauth/authorize?client_id=abc") ==
               {:local, "/oauth/authorize?client_id=abc"}
    end

    test "a protocol-relative URL is rejected (open-redirect protection)" do
      assert Auth.return_to_target("//evil.example.com") == :default
      assert Auth.return_to_target("//evil.example.com/path") == :default
    end

    test "an allow-listed external URL is honored, verbatim including path and query" do
      url = "https://admin.example.com/oauth/authorize?client_id=abc"
      assert Auth.return_to_target(url) == {:external, url}
    end

    test "an allow-listed external origin with no path is honored" do
      assert Auth.return_to_target("https://admin.example.com") ==
               {:external, "https://admin.example.com"}
    end

    test "an allow-listed external URL including its explicit port is honored" do
      url = "https://console.example.com:8443/oauth/authorize"
      assert Auth.return_to_target(url) == {:external, url}
    end

    test "a non-allow-listed host is rejected" do
      assert Auth.return_to_target("https://evil.example.com/steal") == :default
    end

    test "a subdomain of an allow-listed host is rejected" do
      assert Auth.return_to_target("https://evil.admin.example.com/steal") == :default
    end

    test "a matching host on a different scheme is rejected" do
      assert Auth.return_to_target("http://admin.example.com/oauth/authorize") == :default
    end

    test "a matching host/scheme on a different port is rejected" do
      # allow-list entry is console.example.com:8443, default https port (443) must not match
      assert Auth.return_to_target("https://console.example.com/oauth/authorize") == :default
    end

    test "a URL without a host is rejected" do
      assert Auth.return_to_target("https:///no-host") == :default
    end

    test "a non-http scheme with no host (e.g. javascript:) is rejected" do
      assert Auth.return_to_target("javascript:alert(1)") == :default
      assert Auth.return_to_target("mailto:someone@example.com") == :default
    end

    test "a non-binary value falls back to the default" do
      assert Auth.return_to_target(123) == :default
      assert Auth.return_to_target(%{}) == :default
    end

    test "nothing is allowed when the allow-list is empty" do
      Application.put_env(:nerves_hub, :external_login_return_urls, [])
      assert Auth.return_to_target("https://admin.example.com/oauth/authorize") == :default
    end
  end
end
