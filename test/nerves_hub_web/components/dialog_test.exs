defmodule NervesHubWeb.Components.DialogTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest

  alias NervesHubWeb.Components.Dialog
  alias Phoenix.LiveView.JS

  defp render(assigns, template), do: assigns |> template.() |> rendered_to_string() |> LazyHTML.from_fragment()

  describe "confirm/1" do
    test "puts Cancel before the action, under the body, with no close button" do
      html =
        render(%{}, fn assigns ->
          ~H"""
          <Dialog.confirm id="ask" title="Delete soil-probe?" on_cancel={JS.push("cancel")}>
            <p>This can't be undone.</p>
            <:actions><button id="act">Delete soil-probe</button></:actions>
          </Dialog.confirm>
          """
        end)

      assert html |> LazyHTML.query("#ask-title") |> LazyHTML.text() =~ "Delete soil-probe?"
      assert html |> LazyHTML.query("#ask-description p") |> LazyHTML.text() == "This can't be undone."

      footer = LazyHTML.query(html, "#ask-content > div:last-child")

      assert footer |> LazyHTML.query("button") |> Enum.map(&String.trim(LazyHTML.text(&1))) == [
               "Cancel",
               "Delete soil-probe"
             ]

      assert html |> LazyHTML.query("[aria-label='close'], [aria-label='Close']") |> Enum.empty?()
    end

    test "takes a title with markup from the heading slot" do
      html =
        render(%{}, fn assigns ->
          ~H"""
          <Dialog.confirm id="ask" on_cancel={JS.push("cancel")}>
            <:heading>Delete <span class="font-mono">2.4.0</span>?</:heading>
            <p>Devices keep running it.</p>
          </Dialog.confirm>
          """
        end)

      assert html |> LazyHTML.query("#ask-title span.font-mono") |> LazyHTML.text() == "2.4.0"

      assert html |> LazyHTML.query("#ask-title") |> LazyHTML.text() |> String.split() |> Enum.join(" ") ==
               "Delete 2.4.0?"

      assert html |> LazyHTML.query("#ask-subtitle") |> Enum.empty?()
    end

    test "puts the subtitle under the title, outside the description" do
      html =
        render(%{}, fn assigns ->
          ~H"""
          <Dialog.confirm id="ask" title="Delete 2.4.0?" on_cancel={JS.push("cancel")}>
            <:subtitle>b8f2c0d1-6a3e-4f0b-9c1d-27a4d5f0e41c</:subtitle>
            <p>Devices keep running it.</p>
          </Dialog.confirm>
          """
        end)

      assert html |> LazyHTML.query("#ask-title + #ask-subtitle") |> LazyHTML.text() |> String.trim() ==
               "b8f2c0d1-6a3e-4f0b-9c1d-27a4d5f0e41c"

      assert html |> LazyHTML.query("#ask-description #ask-subtitle") |> Enum.empty?()
    end

    test "puts the note at the start of the footer, before Cancel" do
      html =
        render(%{}, fn assigns ->
          ~H"""
          <Dialog.confirm id="ask" title="Copy the key" on_cancel={JS.push("cancel")}>
            <p>Shown once.</p>
            <:note>Manage · created just now</:note>
            <:actions><button id="act">Done</button></:actions>
          </Dialog.confirm>
          """
        end)

      footer = LazyHTML.query(html, "#ask-content > div:last-child")

      assert footer |> LazyHTML.query("#ask-note:first-child") |> LazyHTML.text() == "Manage · created just now"

      assert footer |> LazyHTML.query("button") |> Enum.map(&String.trim(LazyHTML.text(&1))) == ["Cancel", "Done"]
      assert html |> LazyHTML.query("#ask-description #ask-note") |> Enum.empty?()
    end

    test "can only be closed by its own buttons when it isn't dismissible" do
      html =
        render(%{}, fn assigns ->
          ~H"""
          <Dialog.confirm id="ask" title="Copy the key" on_cancel={JS.push("cancel")} dismissible={false}>
            <p>Shown once.</p>
            <:actions><button id="act">I've copied it</button></:actions>
          </Dialog.confirm>
          """
        end)

      assert html |> LazyHTML.query("#ask-content button") |> Enum.map(&String.trim(LazyHTML.text(&1))) == [
               "I've copied it"
             ]

      assert html |> LazyHTML.query("#ask-container[phx-click-away]") |> Enum.empty?()
      assert html |> LazyHTML.query("#ask-container[phx-window-keydown]") |> Enum.empty?()

      dismissible =
        render(%{}, fn assigns ->
          ~H|<Dialog.confirm id="ask" title="Sure?" on_cancel={JS.push("cancel")}>Sure.</Dialog.confirm>|
        end)

      refute dismissible |> LazyHTML.query("#ask-container[phx-click-away][phx-window-keydown]") |> Enum.empty?()
    end

    # A popover inside, such as the API key role picker, hangs past the footer.
    test "clips nothing inside it" do
      html =
        render(%{}, fn assigns ->
          ~H"""
          <Dialog.confirm id="ask" title="Create a key" on_cancel={JS.push("cancel")} wide>
            <p>Name it.</p>
            <:note>A note</:note>
            <:actions><button>Create key</button></:actions>
          </Dialog.confirm>
          """
        end)

      classes =
        html
        |> LazyHTML.query("#ask-container, #ask-container *")
        |> Enum.flat_map(&LazyHTML.attribute(&1, "class"))
        |> Enum.flat_map(&String.split/1)

      assert classes != []
      refute Enum.any?(classes, &String.contains?(&1, "overflow"))
    end

    test "is 440px wide, or 480px when wide" do
      narrow =
        render(%{}, fn assigns ->
          ~H|<Dialog.confirm id="ask" title="Sure?" on_cancel={JS.push("cancel")}>Sure.</Dialog.confirm>|
        end)

      wide =
        render(%{}, fn assigns ->
          ~H|<Dialog.confirm id="ask" title="Sure?" on_cancel={JS.push("cancel")} wide>Sure.</Dialog.confirm>|
        end)

      refute narrow |> LazyHTML.query("#ask-container.sm\\:max-w-110") |> Enum.empty?()
      refute wide |> LazyHTML.query("#ask-container.sm\\:max-w-120") |> Enum.empty?()
    end
  end
end
