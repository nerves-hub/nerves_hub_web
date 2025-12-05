defmodule NervesHubWeb.Components.DeploymentGroupPage.ReleaseHistory do
  use NervesHubWeb, :live_component

  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> ok()
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col p-6 gap-6">
      <div class="w-full">
        <div class="flex flex-col bg-zinc-900 border border-zinc-700 rounded">
          <div class="flex justify-between items-center h-14 px-4 border-b border-zinc-700">
            <div class="text-base text-neutral-50 font-medium">Release History</div>
          </div>

          <div :if={@releases == []} class="flex flex-col items-center justify-center p-12 gap-4">
            <div class="text-zinc-400">No releases yet</div>
            <div class="text-sm text-zinc-500">
              Release history will appear here when you change the firmware version in settings.
            </div>
          </div>

          <div :if={@releases != []} class="overflow-x-auto">
            <table class="w-full">
              <thead class="border-b border-zinc-700">
                <tr>
                  <th class="text-left px-4 py-3 text-sm font-medium text-zinc-400">Released</th>
                  <th class="text-left px-4 py-3 text-sm font-medium text-zinc-400">Firmware Version</th>
                  <th class="text-left px-4 py-3 text-sm font-medium text-zinc-400">UUID</th>
                  <th class="text-left px-4 py-3 text-sm font-medium text-zinc-400">Archive</th>
                  <th class="text-left px-4 py-3 text-sm font-medium text-zinc-400">Released By</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={release <- @releases} class="border-b border-zinc-800 hover:bg-zinc-800/50">
                  <td class="px-4 py-3 text-sm text-zinc-300">
                    <div class="flex flex-col">
                      <span>{Calendar.strftime(release.inserted_at, "%B %d, %Y")}</span>
                      <span class="text-xs text-zinc-500">{Calendar.strftime(release.inserted_at, "%I:%M %p")}</span>
                    </div>
                  </td>
                  <td class="px-4 py-3 text-sm text-zinc-300 font-medium">
                    {release.firmware.version}
                  </td>
                  <td class="px-4 py-3 text-sm text-zinc-400 font-mono">
                    {release.firmware.uuid}
                  </td>
                  <td class="px-4 py-3 text-sm text-zinc-400">
                    <span :if={release.archive}>
                      {release.archive.version} ({String.slice(release.archive.uuid, 0..7)})
                    </span>
                    <span :if={!release.archive} class="text-zinc-500 italic">
                      None
                    </span>
                  </td>
                  <td class="px-4 py-3 text-sm text-zinc-400">
                    {release.user.name}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
