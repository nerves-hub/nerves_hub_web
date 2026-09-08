defmodule NervesHubWeb.Components.CAHelpersTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias NervesHub.Devices.CACertificate
  alias NervesHubWeb.Components.CAHelpers

  defp status(not_after) do
    render_component(&CAHelpers.certificate_status/1, not_after: not_after)
  end

  describe "certificate_status/1" do
    test "a CA with months left is current" do
      html = status(DateTime.shift(DateTime.utc_now(), year: 1))

      assert html =~ "Current"
      assert html =~ "text-base-400"
    end

    test "a CA inside its last three months is expiring soon" do
      html = status(DateTime.shift(DateTime.utc_now(), month: 1))

      assert html =~ "Expiring Soon"
      assert html =~ "text-warning-content"
    end

    test "a CA past its not_after is expired" do
      html = status(DateTime.shift(DateTime.utc_now(), day: -1))

      assert html =~ "Expired"
      assert html =~ "text-alert-content"
    end
  end

  describe "label/1" do
    test "is the description when the CA has one" do
      assert CAHelpers.label(%CACertificate{description: "Factory signer", serial: "1"}) ==
               "Factory signer"
    end

    test "falls back to the formatted serial when the description is missing" do
      for description <- [nil, ""] do
        assert CAHelpers.label(%CACertificate{description: description, serial: "255"}) == "FF"
      end
    end
  end
end
