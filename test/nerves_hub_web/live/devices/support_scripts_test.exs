defmodule NervesHubWeb.Live.Devices.SupportScriptsTest do
  # Uses set_mimic_global because the Mimic stub has to be visible
  # from the Task spawned by Phoenix.LiveView.start_async/3, which
  # runs under a separate task supervisor and does not inherit the
  # per-process Mimic context.
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  alias NervesHub.Scripts.Runner

  setup :set_mimic_global

  describe "support scripts" do
    # Reproduces https://github.com/nerves-hub/nerves_hub_web/issues/2607
    #
    # When more than one support script has output assigned at the same
    # time, the device-details template renders the same DOM ids
    # ("support-script" + "support-script-output") for each script. The
    # xterm.js hook calls document.getElementById("support-script-output"),
    # which always returns the first match, so each subsequent script's
    # terminal renders the earlier script's output (FIFO).
    #
    # Phoenix.LiveViewTest also enforces unique ids on render, so this
    # test currently fails with `(RuntimeError) Duplicate id found while
    # testing LiveView: support-script` — that error IS the bug. The fix
    # should make each script's output panel ids unique (e.g. by
    # appending the script's id), at which point this test will pass.
    test "running multiple scripts produces uniquely identifiable output panels (#2607)", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user
    } do
      {:ok, script_1} =
        NervesHub.Scripts.create(product, user, %{name: "Script 1", text: "ignored"})

      {:ok, script_2} =
        NervesHub.Scripts.create(product, user, %{name: "Script 2", text: "ignored"})

      test_pid = self()

      stub_runner = fn _device, script ->
        send(test_pid, {:runner_called, script.name})
        {:ok, "output for #{script.name}"}
      end

      # `Scripts.Runner.send/3` has a default timeout argument, but the
      # LiveView only calls the arity-2 form, so we stub both arities to
      # be safe.
      Runner
      |> stub(:send, stub_runner)
      |> stub(:send, fn device, script, _timeout -> stub_runner.(device, script) end)

      {:ok, view, _html} =
        live(conn, "/org/#{org.name}/#{product.name}/devices/#{device.identifier}")

      render_click(view, "run-script", %{"id" => to_string(script_1.id)})
      render_click(view, "run-script", %{"id" => to_string(script_2.id)})

      assert_receive {:runner_called, "Script 1"}, 1_000
      assert_receive {:runner_called, "Script 2"}, 1_000

      html = eventually_both_outputs(view)

      assert html =~ "output for Script 1"
      assert html =~ "output for Script 2"

      {:ok, document} = Floki.parse_document(html)

      hook_ids =
        document
        |> Floki.find("[phx-hook=\"SupportScriptOutput\"]")
        |> Enum.flat_map(&Floki.attribute(&1, "id"))

      hidden_output_ids =
        document
        |> Floki.find("[id^=\"support-script-output\"]")
        |> Enum.flat_map(&Floki.attribute(&1, "id"))

      assert length(hook_ids) == 2,
             "Expected an xterm container per running script, got ids: #{inspect(hook_ids)}"

      assert hook_ids == Enum.uniq(hook_ids),
             "Each script's xterm container needs a unique DOM id (issue #2607). Got: #{inspect(hook_ids)}"

      assert hidden_output_ids == Enum.uniq(hidden_output_ids),
             "Each script's hidden output element needs a unique DOM id (issue #2607). Got: #{inspect(hidden_output_ids)}"
    end
  end

  defp eventually_both_outputs(view, attempts \\ 40)

  defp eventually_both_outputs(_view, 0) do
    flunk("LiveView never rendered both script outputs")
  end

  defp eventually_both_outputs(view, attempts) do
    html = render(view)

    if html =~ "output for Script 1" and html =~ "output for Script 2" do
      html
    else
      Process.sleep(50)
      eventually_both_outputs(view, attempts - 1)
    end
  end
end
