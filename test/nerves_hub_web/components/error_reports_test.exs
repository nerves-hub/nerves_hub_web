defmodule NervesHubWeb.Components.ErrorReportsTest do
  use ExUnit.Case, async: true

  alias NervesHubWeb.Components.ErrorReports

  describe "context_entries/1" do
    test "labels the vitals the protocol names, first" do
      assert [
               {"Reboots", "3", true},
               {"Uptime", "3 h 12 min", true},
               {"Free memory", "11.8 MB", true},
               {"queue", "uploads", false}
             ] =
               ErrorReports.context_entries(%{
                 "queue" => "uploads",
                 "free_memory_bytes" => "11800000",
                 "uptime_ms" => "11520000",
                 "reboot_count" => "3"
               })
    end

    # Context values come from the device. One too large for a float must not
    # take the error page down with an ArithmeticError.
    test "shows a byte count it can't divide as the device sent it" do
      huge = String.duplicate("9", 400)

      assert [{"Free memory", ^huge, true}] = ErrorReports.context_entries(%{"free_memory_bytes" => huge})
      assert [{"Free memory", "-5", true}] = ErrorReports.context_entries(%{"free_memory_bytes" => "-5"})
    end
  end
end
