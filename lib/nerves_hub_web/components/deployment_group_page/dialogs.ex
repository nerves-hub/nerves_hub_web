defmodule NervesHubWeb.Components.DeploymentGroupPage.Dialogs do
  @moduledoc """
  The confirm dialogs on a deployment group's page.

  Pausing or resuming the group and moving devices into or out of it ask
  first here, drawn with `Dialog.confirm/1`. Approving or skipping a step
  falls through to `DeploymentGroups.confirm_dialog/1`, which the list shares.
  """
  use NervesHubWeb, :component
  use Gettext, backend: NervesHubWeb.Gettext

  import NervesHubWeb.Components.Fleet, only: [count_noun: 3, delimited: 1]

  alias NervesHubWeb.Components.DeploymentGroups
  alias NervesHubWeb.Components.Dialog
  alias Phoenix.LiveView.JS

  @doc """
  The dialog the page's `@confirm` asks for:

    * `{:pause, entry}` and `{:resume, entry}`, with the group's entry from
      `DeploymentGroups.load/2` for its counts
    * `{:move_in, count}`, for the devices that match the group but aren't in
      any group
    * `{:remove_unmatched, count}`, for the devices in the group that no
      longer match it
    * `{:approve, entry}` and `{:skip, entry}`, drawn by
      `DeploymentGroups.confirm_dialog/1`

  Cancelling pushes `cancel-confirm`, and each action pushes the event that
  does it.
  """
  attr(:confirm, :any, required: true)
  attr(:deployment_group, :map, required: true)

  def confirm_dialog(%{confirm: {:pause, entry}} = assigns) do
    assigns = assign(assigns, entry: entry, counts: entry.counts)

    ~H"""
    <Dialog.confirm
      id="pause-group"
      title={"Pause #{@deployment_group.name}?"}
      on_cancel={JS.push("cancel-confirm")}
      wide={@counts.updating > 0 or @counts.waiting > 0}
    >
      <p>
        It stops sending <span class="font-mono text-content-strong">{version(@deployment_group)}</span>, even to devices that connect, until it’s resumed.
      </p>
      <ul
        :if={@counts.updating > 0 or @counts.waiting > 0}
        class="flex flex-col gap-1.5 rounded-card bg-surface-muted px-3 py-2.5 text-ui text-content-body"
      >
        <li :if={@counts.updating > 0} class="flex gap-2">
          <span class="mt-2 size-1 shrink-0 rounded-full bg-content-faint" aria-hidden="true"></span>
          <span>
            <span class="font-mono text-content-strong">{delimited(@counts.updating)}</span>
            {ngettext("device taking it now finishes it", "devices taking it now finish it", @counts.updating)}
          </span>
        </li>
        <li :if={@counts.waiting > 0} class="flex gap-2">
          <span class="mt-2 size-1 shrink-0 rounded-full bg-content-faint" aria-hidden="true"></span>
          <span>
            <span class="font-mono text-content-strong">{delimited(@counts.waiting)}</span>
            {ngettext("waiting for it gets nothing until then", "waiting for it get nothing until then", @counts.waiting)}
          </span>
        </li>
      </ul>
      <:actions>
        <.button style="primary" phx-click="pause">Pause</.button>
      </:actions>
    </Dialog.confirm>
    """
  end

  def confirm_dialog(%{confirm: {:resume, entry}} = assigns) do
    assigns = assign(assigns, :waiting, entry.counts.waiting)

    ~H"""
    <Dialog.confirm id="resume-group" title={"Resume #{@deployment_group.name}?"} on_cancel={JS.push("cancel-confirm")}>
      <p>
        It starts sending <span class="font-mono text-content-strong">{version(@deployment_group)}</span> again, {to_waiting(@waiting)}
      </p>
      <:actions>
        <.button style="primary" phx-click="resume">Resume</.button>
      </:actions>
    </Dialog.confirm>
    """
  end

  def confirm_dialog(%{confirm: {:move_in, count}} = assigns) do
    assigns = assign(assigns, :count, count)

    ~H"""
    <Dialog.confirm
      id="move-devices-in"
      title={"Move #{count_noun(@count, "device", "devices")} into #{@deployment_group.name}?"}
      on_cancel={JS.push("cancel-confirm")}
    >
      <p :if={@count == 1}>
        It matches the group’s rules but isn’t in any deployment group. Once it’s in, it gets the group’s releases, starting with <span class="font-mono text-content-strong">{version(@deployment_group)}</span>.
      </p>
      <p :if={@count != 1}>
        They match its rules but aren’t in any deployment group. Once they’re in, they get its releases, starting with <span class="font-mono text-content-strong">{version(@deployment_group)}</span>.
      </p>
      <:actions>
        <.button style="primary" phx-click="move-matched-devices-to-deployment-group">Move devices</.button>
      </:actions>
    </Dialog.confirm>
    """
  end

  def confirm_dialog(%{confirm: {:remove_unmatched, count}} = assigns) do
    assigns = assign(assigns, :count, count)

    ~H"""
    <Dialog.confirm
      id="remove-unmatched-devices"
      title={"Remove #{count_noun(@count, "device", "devices")} from #{@deployment_group.name}?"}
      on_cancel={JS.push("cancel-confirm")}
    >
      <p :if={@count == 1}>
        It’s in the group but no longer matches its rules. It keeps the firmware it has, and when it next connects it joins another group it matches, if there is one.
      </p>
      <p :if={@count != 1}>
        They’re in it but no longer match its rules. They keep the firmware they have, and when one next connects it joins another group it matches, if there is one.
      </p>
      <:actions>
        <.button style="primary" phx-click="remove-unmatched-devices-from-deployment-group">Remove devices</.button>
      </:actions>
    </Dialog.confirm>
    """
  end

  def confirm_dialog(assigns), do: DeploymentGroups.confirm_dialog(assigns)

  defp version(deployment_group), do: deployment_group.current_release.firmware.version

  defp to_waiting(0), do: "though no device in it is waiting for it now."
  defp to_waiting(1), do: "to the one device in it waiting for it."
  defp to_waiting(count), do: "to the #{delimited(count)} devices in it waiting for it."
end
