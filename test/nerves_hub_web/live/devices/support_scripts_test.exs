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
    # The Support Scripts section presents a dropdown of all scripts and a
    # single "Run script" button. Running a script shows its output below
    # the dropdown, and selecting a different script swaps the visible
    # output for that script.
    #
    # The output panel DOM ids are derived from the selected script's id
    # (regression cover for https://github.com/nerves-hub/nerves_hub_web/issues/2607),
    # so each script renders its own uniquely identifiable terminal.
    test "running the selected script shows its output, switching scripts swaps the output", %{
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

      # No script is selected by default, so pick the first one before running.
      render_change(view, "select-script", %{"script_id" => to_string(script_1.id)})
      render_click(view, "run-script", %{"id" => to_string(script_1.id)})

      assert_receive {:runner_called, "Script 1"}, 1_000

      html = eventually_output(view, "output for Script 1")
      assert html =~ "output for Script 1"
      refute html =~ "output for Script 2"
      assert html =~ "support-script-output"

      # Switch the dropdown to the second script and run it; its output
      # replaces the first script's output.
      render_change(view, "select-script", %{"script_id" => to_string(script_2.id)})
      render_click(view, "run-script", %{"id" => to_string(script_2.id)})

      assert_receive {:runner_called, "Script 2"}, 1_000

      html = eventually_output(view, "output for Script 2")
      assert html =~ "output for Script 2"
      refute html =~ "output for Script 1"
      assert html =~ "support-script-output"
    end
  end

  defp eventually_output(view, expected, attempts \\ 40)

  defp eventually_output(_view, expected, 0) do
    flunk("LiveView never rendered #{inspect(expected)}")
  end

  defp eventually_output(view, expected, attempts) do
    html = render(view)

    if html =~ expected do
      html
    else
      Process.sleep(50)
      eventually_output(view, expected, attempts - 1)
    end
  end
end
