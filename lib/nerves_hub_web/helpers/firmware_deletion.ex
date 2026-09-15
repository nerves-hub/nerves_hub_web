defmodule NervesHubWeb.Helpers.FirmwareDeletion do
  @moduledoc """
  Turns `NervesHub.Firmwares` deletion blockers and warnings into operator copy.

  The same sentence has to appear in three places — the tooltip on a disabled
  delete button, the flash when a delete is refused anyway, and the API's error
  body — so the wording lives here rather than in each of them.
  """

  alias NervesHub.Firmwares
  alias NervesHub.Firmwares.Firmware
  alias NervesHubWeb.Components.DateTimes

  @doc """
  One sentence explaining why firmware cannot be deleted.

  Takes the whole blocker list and speaks to the first one: a user fixes them
  one at a time, and naming every obstacle at once reads as noise.
  """
  @spec blockers_message([Firmwares.deletion_blocker()]) :: String.t() | nil
  def blockers_message([]), do: nil
  def blockers_message([blocker | _rest]), do: blocker_message(blocker)

  @spec blocker_message(Firmwares.deletion_blocker()) :: String.t()
  def blocker_message(:already_deleted), do: "This firmware has already been deleted."

  def blocker_message({:current_release, deployment_groups}) do
    names = Enum.map_join(deployment_groups, ", ", & &1.name)

    "This firmware is the current release of #{names}. Give #{group_pronoun(deployment_groups)} " <>
      "another release before deleting it."
  end

  def blocker_message({:inflight_updates, 1}) do
    "A device is updating to this firmware right now. Deleting it would break that update."
  end

  def blocker_message({:inflight_updates, count}) do
    "#{count} devices are updating to this firmware right now. Deleting it would break those updates."
  end

  @doc """
  What to tell a user before they confirm a deletion, or `nil` if there is
  nothing worth saying.
  """
  @spec warnings_message([Firmwares.deletion_warning()]) :: String.t() | nil
  def warnings_message([]), do: nil

  def warnings_message(warnings) do
    Enum.map_join(warnings, " ", &warning_message/1)
  end

  @spec warning_message(Firmwares.deletion_warning()) :: String.t()
  def warning_message({:delta_source, 1}) do
    "One firmware delta is built from this firmware. Deleting it means devices running " <>
      "this version will download whole firmware instead of a delta."
  end

  def warning_message({:delta_source, count}) do
    "#{count} firmware deltas are built from this firmware. Deleting it means devices running " <>
      "this version will download whole firmware instead of deltas."
  end

  @doc """
  Who deleted this firmware and when, as a plain sentence.

  For the places that have room for a "Deleted" badge but not the whole story —
  the firmware list and a deployment group's release history — where it becomes
  the badge's title. The firmware page itself says it in full.
  """
  @spec deleted_summary(Firmware.t(), String.t() | nil) :: String.t()
  def deleted_summary(%Firmware{} = firmware, time_zone) do
    who =
      case firmware.deleted_by do
        %{name: name} -> " by #{name}"
        _ -> ""
      end

    "Deleted#{who} on #{DateTimes.to_local_string(firmware.deleted_at, time_zone)}"
  end

  defp group_pronoun([_one]), do: "it"
  defp group_pronoun(_many), do: "them"
end
