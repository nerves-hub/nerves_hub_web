defmodule NervesHubWeb.Components.BreadcrumbTest do
  use ExUnit.Case, async: true

  import NervesHubWeb.Components.Breadcrumb
  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest

  test "links back to the list and marks the last crumb as the page" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.breadcrumb navigate="/org/acme/kiosk/firmware" root_label="Firmware">
        <:crumb mono>1.8.1</:crumb>
        <:note>esp32 · xtensa</:note>
      </.breadcrumb>
      """)

    nav = html |> LazyHTML.from_fragment() |> LazyHTML.query("nav[aria-label='Breadcrumb']")

    assert nav |> LazyHTML.query("a[href='/org/acme/kiosk/firmware']") |> LazyHTML.text() =~ "Firmware"
    assert nav |> LazyHTML.query("[aria-current='page'].font-mono") |> LazyHTML.text() =~ "1.8.1"
    assert nav |> LazyHTML.query("span.font-mono.max-sm\\:hidden") |> LazyHTML.text() =~ "esp32 · xtensa"
  end

  test "only the last of several crumbs is the page" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.breadcrumb navigate="/org/acme/kiosk/scripts" root_label="Support scripts">
        <:crumb>Reboot</:crumb>
        <:crumb>Edit</:crumb>
      </.breadcrumb>
      """)

    current = html |> LazyHTML.from_fragment() |> LazyHTML.query("[aria-current='page']")

    assert Enum.count(current) == 1
    assert LazyHTML.text(current) =~ "Edit"
  end
end
