defmodule NervesHub.DeviceLink.ScriptRefsTest do
  @moduledoc """
  Running a script leaves two things behind: a reference in the session, and a
  timeout on the connection in case the device never answers.

  Both have to be released on both paths, and only one of them is visible from
  here. A timeout that fires leaves its bookkeeping behind unless something
  explicitly cancels it, and a connection is held for weeks at a time — so the
  leak is slow enough to miss and permanent enough to matter.
  """

  use ExUnit.Case, async: true

  alias NervesHub.DeviceLink
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.DeviceLink.Session

  defp session() do
    %Session{
      device_info: %DeviceInfo{device_id: 1, device_identifier: "script-device"},
      device_api_version: "2.3.0"
    }
  end

  defp run_script(session, text \\ "IO.puts(:hi)") do
    {session, effects} = DeviceLink.device_notify(session, {:run_script, self(), text})

    ref =
      Enum.find_value(effects, fn
        {:push, "scripts/run", %{"ref" => ref}} -> ref
        _ -> nil
      end)

    {session, effects, ref}
  end

  test "running a script pushes it and arms a timeout keyed on the same ref" do
    {session, effects, ref} = run_script(session())

    assert {:push, "scripts/run", %{"text" => "IO.puts(:hi)", "ref" => ^ref}} =
             Enum.find(effects, &match?({:push, _, _}, &1))

    assert {:send_after, {:script_ref, ^ref}, {:clear_script_ref, ^ref}, 15_000} =
             Enum.find(effects, &match?({:send_after, _, _, _}, &1))

    assert Map.has_key?(session.script_refs, ref)
  end

  test "a device that answers releases both the reference and the timeout" do
    {session, _effects, ref} = run_script(session())

    {session, effects} =
      DeviceLink.device_message(session, "scripts/run", %{
        "ref" => ref,
        "output" => "hi",
        "return" => ":ok"
      })

    assert_received {:output, "hi\n:ok"}

    assert {:cancel_timer, {:script_ref, ref}} in effects,
           "answering must cancel the timeout, or its entry outlives the connection"

    refute Map.has_key?(session.script_refs, ref)
  end

  test "a device that never answers releases both when the timeout fires" do
    {session, _effects, ref} = run_script(session())

    {session, effects} = DeviceLink.device_notify(session, {:clear_script_ref, ref})

    assert {:cancel_timer, {:script_ref, ref}} in effects,
           "the timeout must cancel its own bookkeeping once it has fired"

    refute Map.has_key?(session.script_refs, ref)
  end

  test "an answer for an unknown ref is ignored rather than replied to" do
    {session, effects} =
      DeviceLink.device_message(session(), "scripts/run", %{
        "ref" => "never-issued",
        "output" => "hi",
        "return" => ":ok"
      })

    assert effects == []
    assert session.script_refs == %{}
    refute_received {:output, _}
  end

  test "nothing accumulates across many scripts" do
    session =
      Enum.reduce(1..50, session(), fn _, session ->
        {session, _effects, ref} = run_script(session)

        {session, _effects} =
          DeviceLink.device_message(session, "scripts/run", %{
            "ref" => ref,
            "output" => "",
            "return" => ":ok"
          })

        session
      end)

    assert session.script_refs == %{},
           "script references accumulated over #{map_size(session.script_refs)} runs"
  end

  test "a device too old for scripts is told so, and nothing is armed" do
    session = %{session() | device_api_version: "2.0.0"}

    {session, effects} = DeviceLink.device_notify(session, {:run_script, self(), "IO.puts(:hi)"})

    assert_received {:error, :incompatible_version}
    assert effects == []
    assert session.script_refs == %{}
  end
end
