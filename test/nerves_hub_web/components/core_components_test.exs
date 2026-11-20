defmodule NervesHubWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import NervesHubWeb.CoreComponents
  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest

  defp dot_classes(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("span.rounded-full.inline-block")
    |> LazyHTML.attribute("class")
    |> List.first()
    |> String.split()
  end

  describe "status_dot/1" do
    test "is 8px when the caller sets no size" do
      assigns = %{}

      classes = dot_classes(rendered_to_string(~H|<.status_dot class="bg-status-online" />|))

      assert "size-2" in classes
    end

    test "takes the caller's size in place of the 8px" do
      assigns = %{}

      classes = dot_classes(rendered_to_string(~H|<.status_dot class={["size-1.5", "bg-success"]} />|))

      assert "size-1.5" in classes
      refute "size-2" in classes
    end
  end

  describe "badge/1" do
    test "leads with a 6px dot" do
      assigns = %{}

      html = rendered_to_string(~H|<.badge tone="success" dot>Healthy</.badge>|)
      dot = html |> LazyHTML.from_fragment() |> LazyHTML.query("span > span.rounded-full")

      classes = dot |> LazyHTML.attribute("class") |> List.first() |> String.split()

      assert "size-1.5" in classes
      refute "size-2" in classes
    end
  end
end
