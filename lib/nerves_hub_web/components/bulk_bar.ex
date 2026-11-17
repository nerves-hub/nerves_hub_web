defmodule NervesHubWeb.Components.BulkBar do
  @moduledoc """
  The bar that floats at the foot of a product's devices list while devices
  are selected, with what can be done to all of them at once.

  Each action opens a popover above the bar (`@menu`, one at a time, kept by
  the LiveView), whose form sends the same events the list has always handled:
  `tag-devices`, `move-devices-deployment-group`, `push-firmware-to-devices`,
  `move-devices-product` and the update toggles. Each of those closes the
  popover again.
  """
  use NervesHubWeb, :component

  alias NervesHubWeb.Helpers.Authorization
  alias Phoenix.LiveView.JS

  @menus ~w(tags group firmware updates move)

  @doc "The popovers the bar can open."
  @spec menus() :: [String.t(), ...]
  def menus(), do: @menus

  attr(:selected_devices, :list, required: true)
  attr(:select_all_matching, :boolean, required: true)
  attr(:total_entries, :integer, required: true)
  attr(:menu, :string, default: nil)
  attr(:peek_open, :boolean, default: false)
  attr(:current_scope, :map, required: true)
  attr(:product, :map, required: true)
  attr(:target_product, :map, default: nil)
  attr(:move_target_org_ids, :list, required: true)
  attr(:selected_have_deployment_groups, :boolean, required: true)
  attr(:selected_shared_deployment_group, :map, default: nil)
  attr(:valid_deployment_groups_for_selected, :list, required: true)
  attr(:target_deployment_group, :map, default: nil)
  attr(:available_firmwares_for_filtered_platform, :list, required: true)
  attr(:target_firmware, :map, default: nil)
  attr(:valid_tags, :boolean, required: true)
  attr(:device_tags, :string, required: true, doc: "the tag being typed, not yet a chip")
  attr(:bulk_tags, :list, required: true, doc: "the tags added as chips")
  attr(:tag_operation, :string, required: true)
  attr(:available_tags, :list, required: true)

  def render(assigns) do
    assigns = assign(assigns, :count, selected_count(assigns))

    ~H"""
    <div
      :if={@selected_devices != []}
      id="bulk-bar-wrapper"
      class={[
        "@container pointer-events-none fixed right-0 bottom-6 left-(--sidebar-width) z-40 flex justify-center px-4 max-sm:bottom-3 max-sm:left-0 max-sm:px-3 collapsed:left-16",
        @peek_open && "lg:right-150"
      ]}
    >
      <div
        id="bulk-bar"
        role="toolbar"
        aria-label="Selected devices"
        class={
          [
            "pointer-events-auto flex max-w-full items-center gap-1.5 rounded-md border border-line-control bg-surface-raised py-2 pr-2 pl-4 shadow-overlay max-md:flex-wrap",
            # On a phone: a dark bar of icons over labels. The top bar says how
            # many are selected, and its Done clears them.
            "max-sm:w-full max-sm:flex-nowrap max-sm:gap-0 max-sm:rounded-xl max-sm:border-zinc-800 max-sm:bg-zinc-900 max-sm:p-1.5"
          ]
        }
      >
        <div class="mr-1.5 flex items-center gap-3 border-r border-line-default pr-3 max-sm:hidden">
          <span id="bulk-selected" class="text-ui/4 font-semibold whitespace-nowrap text-content-strong">
            <span class="font-mono">{delimit(@count)}</span> selected
          </span>
          <button
            :if={not @select_all_matching and @count < @total_entries}
            id="bulk-select-all"
            type="button"
            phx-click="select-all-matching"
            class="cursor-pointer text-ui/4 font-medium whitespace-nowrap text-primary hover:underline light:text-indigo-600"
          >
            Select all <span class="font-mono">{delimit(@total_entries)}</span>
          </button>
        </div>

        <.menu :if={Authorization.authorized?(:"device:tags", @current_scope)} id="tags" label="Tags" short_label="Tags" icon="lucide-tag" menu={@menu}>
          <form id="bulk-tag-input" phx-change="validate-tags" phx-submit="tag-devices">
            <.popover_body title={"Tags on #{delimit(@count)} #{devices(@count)}"}>
              <div role="radiogroup" aria-label="Change" class="flex gap-0.5 rounded-md border border-line-default bg-surface-muted p-0.5">
                <label :for={{value, label} <- [{"add", "Add"}, {"remove", "Remove"}, {"set", "Replace all"}]} class={segment_class()}>
                  <input type="radio" name="tag_operation" value={value} checked={@tag_operation == value} class="sr-only" />
                  {label}
                </label>
              </div>

              <input type="hidden" name="tags" value={Enum.join(@bulk_tags, ",")} />
              <div class="flex min-h-7.5 flex-wrap items-center gap-1 rounded border border-line-control bg-surface-raised px-1 py-0.5 focus-within:border-primary">
                <span
                  :for={tag <- @bulk_tags}
                  data-tag={tag}
                  class="flex h-5.5 items-center gap-1 rounded border border-line-default bg-surface-muted pr-1 pl-1.5 text-xs font-medium text-content-body"
                >
                  {tag}
                  <button
                    type="button"
                    phx-click="bulk-remove-tag"
                    phx-value-tag={tag}
                    aria-label={"Remove #{tag}"}
                    class="flex cursor-pointer rounded-sm text-content-faint hover:text-content-strong"
                  >
                    <span class="lucide-x size-3" aria-hidden="true"></span>
                  </button>
                </span>
                <div
                  id="bulk-tag-autocomplete"
                  class="relative min-w-20 grow basis-20"
                  phx-hook="TagAutocomplete"
                  data-commit-event="bulk-add-tag"
                  data-available-tags={Jason.encode!(@available_tags -- @bulk_tags)}
                >
                  <label for="input_set_tags" class="sr-only">Tags</label>
                  <input
                    type="text"
                    class="h-5.5 w-full border-0 bg-transparent p-0 pl-1 text-ui/4 text-content-strong placeholder:text-content-faint focus:ring-0"
                    name="new_tag"
                    id="input_set_tags"
                    value={@device_tags}
                    placeholder={if @bulk_tags == [], do: "beta, field-units"}
                    autocomplete="off"
                    data-tag-input
                    phx-debounce="300"
                    phx-mounted={JS.focus()}
                  />
                  <ul
                    id="input_set_tags-suggestions"
                    phx-update="ignore"
                    data-tag-suggestions
                    role="listbox"
                    hidden
                    class="absolute bottom-full -left-1 z-10 mb-1.5 max-h-56 w-56 overflow-y-auto rounded-md border border-line-strong bg-surface-raised py-1 shadow-overlay"
                  >
                  </ul>
                </div>
              </div>

              <p class={["text-xs/4", if(@valid_tags, do: "text-content-muted", else: "text-alert")]}>
                {if @valid_tags, do: "Separate tags with a comma. A tag can't contain spaces.", else: "A tag can't contain spaces."}
              </p>
            </.popover_body>

            <.popover_footer>
              <.button
                style="primary"
                size="sm"
                type="submit"
                data-confirm={@tag_operation == "set" && replace_confirmation(@count)}
                disabled={not @valid_tags or (@bulk_tags == [] and String.trim(@device_tags) == "")}
              >
                {tag_submit_label(@tag_operation)} <span class="font-mono">{delimit(@count)}</span> {devices(@count)}
              </.button>
            </.popover_footer>
          </form>
        </.menu>

        <.menu id="group" label="Deployment group" short_label="Group" icon="lucide-rocket" menu={@menu}>
          <form id="deployment-set" phx-change="target-deployment-group" phx-submit="move-devices-deployment-group">
            <.popover_body title={"Deployment group for #{delimit(@count)} #{devices(@count)}"}>
              <p :if={@selected_shared_deployment_group && not @select_all_matching} class="text-xs/4 text-content-muted">
                Currently in <span class="font-medium text-content-body">{@selected_shared_deployment_group.name}</span>
              </p>
              <label for="set_deployment_group" class="sr-only">Set deployment group</label>
              <select
                name="deployment_group"
                id="set_deployment_group"
                class={[input_class(), "w-full"]}
                disabled={@valid_deployment_groups_for_selected == []}
              >
                <option value="">
                  {if @valid_deployment_groups_for_selected == [], do: "No group matches these devices", else: "Choose a group"}
                </option>
                <option
                  :for={group <- @valid_deployment_groups_for_selected}
                  value={group.id}
                  selected={@target_deployment_group && @target_deployment_group.id == group.id}
                >
                  {group.name} · {group.current_release.firmware.platform} · {group.current_release.firmware.architecture}
                </option>
              </select>
            </.popover_body>

            <.popover_footer>
              <.button
                :if={@selected_have_deployment_groups or @select_all_matching}
                id="remove-devices-from-deployment-group"
                style="danger"
                size="sm"
                class="mr-auto"
                phx-click="remove-devices-from-deployment-group"
                data-confirm="This will remove all selected devices from their deployment groups. Would you like to continue?"
              >
                Remove from group
              </.button>
              <.button
                style="primary"
                size="sm"
                type="submit"
                data-confirm={@target_deployment_group && "This will add the selected devices to #{@target_deployment_group.name}. Would you like to continue?"}
                disabled={is_nil(@target_deployment_group)}
              >
                Add to group
              </.button>
            </.popover_footer>
          </form>
        </.menu>

        <.menu id="firmware" label="Send firmware" short_label="Firmware" icon="lucide-download" menu={@menu}>
          <form
            :if={@available_firmwares_for_filtered_platform != [] and not @select_all_matching}
            id="push-firmware"
            phx-change="target-firmware"
            phx-submit="push-firmware-to-devices"
          >
            <.popover_body title={"Send firmware to #{delimit(@count)} #{devices(@count)}"}>
              <label for="firmware_select" class="sr-only">Firmware</label>
              <select name="firmware" id="firmware_select" class={[input_class(), "w-full"]}>
                <option value="">Choose firmware</option>
                <option
                  :for={firmware <- @available_firmwares_for_filtered_platform}
                  value={firmware.uuid}
                  selected={@target_firmware && @target_firmware.uuid == firmware.uuid}
                >
                  {firmware.version} ({String.slice(firmware.uuid, 0..7)})
                </option>
              </select>
              <p class="text-xs/4 text-content-muted">Each device starts the update when it next checks in, outside any deployment group.</p>
            </.popover_body>

            <.popover_footer>
              <.button
                style="primary"
                size="sm"
                type="submit"
                data-confirm="This will send the selected firmware to all selected devices. Would you like to continue?"
                disabled={is_nil(@target_firmware)}
              >
                Send to <span class="font-mono">{delimit(@count)}</span> {devices(@count)}
              </.button>
            </.popover_footer>
          </form>

          <.popover_body :if={@available_firmwares_for_filtered_platform == [] or @select_all_matching} title="Send firmware">
            <p id="bulk-firmware-unavailable" class="text-ui/4.5 text-content-muted">
              {firmware_unavailable(@select_all_matching)}
            </p>
          </.popover_body>
        </.menu>

        <.menu id="updates" label="Updates" short_label="Updates" icon="lucide-circle-arrow-up" compact_only_icon chevron menu={@menu} align="right">
          <div role="menu" aria-label="Updates" class="flex w-56 flex-col py-1 max-sm:w-full max-sm:py-2">
            <form id="enable-updates" phx-submit="enable-updates-for-devices">
              <button type="submit" role="menuitem" class={menu_item_class()} data-confirm="This will enable updates for all selected devices">
                <span class="lucide-circle-check size-3.5 text-content-muted" aria-hidden="true"></span> Enable updates
              </button>
            </form>
            <form id="disable-updates" phx-submit="disable-updates-for-devices">
              <button type="submit" role="menuitem" class={menu_item_class()} data-confirm="This will disable updates for all selected devices">
                <span class="lucide-circle-slash size-3.5 text-content-muted" aria-hidden="true"></span> Disable updates
              </button>
            </form>
            <form id="clear-penalty-box" phx-submit="clear-penalty-box-for-devices">
              <button type="submit" role="menuitem" class={menu_item_class()} data-confirm="This will clear the penalty box for all selected devices">
                <span class="lucide-rotate-ccw size-3.5 text-content-muted" aria-hidden="true"></span> Clear penalty box
              </button>
            </form>
          </div>
        </.menu>

        <.menu id="move" label="Move to product" short_label="Move" icon="lucide-arrow-right-left" menu={@menu} align="right">
          <form id="product-move" phx-change="target-product" phx-submit="move-devices-product">
            <.popover_body title={"Move #{delimit(@count)} #{devices(@count)}"}>
              <label for="move_to" class="text-xs/4 font-medium text-content-muted">Move device(s) to product:</label>
              <select name="product_id" id="move_to" class={[input_class(), "w-full"]}>
                <option value="">Choose a product</option>
                <optgroup :for={org <- move_target_orgs(@current_scope, @move_target_org_ids, @product)} label={org.name}>
                  <option
                    :for={product <- other_products(org, @product)}
                    value={product.id}
                    selected={@target_product && @target_product.id == product.id}
                  >
                    {product.name}
                  </option>
                </optgroup>
              </select>
              <p class="text-xs/4 text-content-muted">
                Their signing keys are copied to the product's organization if it doesn't have them, and a deployment group there may update them.
              </p>
            </.popover_body>

            <.popover_footer>
              <.button style="primary" size="sm" type="submit" data-confirm={move_alert(@target_product)} disabled={is_nil(@target_product)}>
                Move <span class="font-mono">{delimit(@count)}</span> {devices(@count)}
              </.button>
            </.popover_footer>
          </form>
        </.menu>

        <.button square size="sm" id="bulk-deselect" class="ml-1 border-transparent shadow-none max-sm:hidden" aria-label="Clear selection" phx-click="deselect-all">
          <span class="lucide-x" aria-hidden="true"></span>
        </.button>
      </div>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:label, :string, required: true)
  attr(:short_label, :string, required: true, doc: "the label under the icon on a phone")
  attr(:icon, :string, default: nil)
  attr(:chevron, :boolean, default: false)
  attr(:compact_only_icon, :boolean, default: false, doc: "show the icon only when the bar is too narrow for labels")
  attr(:menu, :string, default: nil)
  attr(:align, :string, default: "left", values: ~w(left right))
  slot(:inner_block, required: true)

  # A button on the bar, and the popover it opens above it. Clicking anywhere
  # outside the two, or pressing esc, closes the popover. Where the bar has less
  # room than its labels need (beside the peek, or on a narrow window), the
  # buttons drop to their icons; the label stays for screen readers and as a
  # tooltip. On a phone every button is its icon over a short label, and the
  # popover is a sheet across the screen above the bar.
  defp menu(assigns) do
    assigns = assign(assigns, :open, assigns.menu == assigns.id)

    ~H"""
    <div class="relative max-sm:static max-sm:min-w-0 max-sm:flex-1" phx-click-away={@open && "close-bulk-menu"}>
      <.button
        id={"bulk-#{@id}"}
        size="sm"
        title={@label}
        aria-expanded={to_string(@open)}
        aria-controls={@open && "bulk-popover"}
        phx-click="bulk-menu"
        phx-value-menu={@id}
        class={[
          "whitespace-nowrap",
          "max-sm:h-13 max-sm:w-full max-sm:flex-col max-sm:justify-center max-sm:gap-1 max-sm:rounded-lg max-sm:border-transparent max-sm:bg-transparent max-sm:px-1 max-sm:text-xs max-sm:font-normal max-sm:text-zinc-100 max-sm:shadow-none",
          @open &&
            "border-line-strong bg-base-800 text-content-strong max-sm:border-transparent max-sm:bg-white/12 max-sm:text-white light:border-base-400 light:bg-surface-muted max-sm:light:border-transparent max-sm:light:bg-white/12"
        ]}
      >
        <%!-- Wrapped, so the button's own rule for icon colour and size, which
              outranks a phone override, doesn't reach it. --%>
        <span
          :if={@icon}
          class={["flex text-content-muted max-sm:text-zinc-400", @open && "max-sm:text-white", @compact_only_icon && "@min-[60rem]:hidden"]}
          aria-hidden="true"
        >
          <span class={[@icon, "size-3.5 max-sm:size-4.5"]}></span>
        </span>
        <span class="max-sm:hidden @max-[60rem]:sr-only">{@label}</span>
        <span class="truncate sm:hidden">{@short_label}</span>
        <span :if={@chevron} class={["lucide-chevron-down transition-transform @max-[60rem]:hidden", @open && "rotate-180"]} aria-hidden="true"></span>
      </.button>

      <div
        :if={@open}
        id="bulk-popover"
        role="dialog"
        aria-label={@label}
        phx-window-keydown="close-bulk-menu"
        phx-key="escape"
        class={[
          "absolute bottom-full mb-2 overflow-hidden rounded-md border border-line-control bg-surface-raised shadow-overlay",
          "max-sm:fixed max-sm:inset-x-3 max-sm:bottom-20 max-sm:mb-0 max-sm:rounded-xl",
          if(@align == "right", do: "right-0", else: "left-0")
        ]}
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr(:title, :any, required: true)
  attr(:rest, :global)
  slot(:inner_block, required: true)

  defp popover_body(assigns) do
    ~H"""
    <div class="flex w-85 max-w-[calc(100vw-2rem)] flex-col gap-3 p-3 max-sm:w-full max-sm:max-w-none max-sm:p-4" {@rest}>
      <p class="text-ui/4 font-semibold text-content-strong">{@title}</p>
      {render_slot(@inner_block)}
    </div>
    """
  end

  slot(:inner_block, required: true)

  defp popover_footer(assigns) do
    ~H"""
    <div class="flex items-center justify-end gap-2 border-t border-line-default bg-surface-muted px-3 py-2.5">
      <.button size="sm" phx-click="close-bulk-menu">Cancel</.button>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp selected_count(%{select_all_matching: true, total_entries: total}), do: total
  defp selected_count(%{selected_devices: selected}), do: length(selected)

  defp delimit(count), do: Number.Delimit.number_to_delimited(count, precision: 0)

  defp devices(1), do: "device"
  defp devices(_count), do: "devices"

  defp tag_submit_label("add"), do: "Add to"
  defp tag_submit_label("remove"), do: "Remove from"
  defp tag_submit_label(_set), do: "Replace on"

  defp replace_confirmation(count) do
    "This will replace the tags on #{delimit(count)} #{devices(count)}, discarding the tags they already have. Would you like to continue?"
  end

  defp firmware_unavailable(true = _select_all_matching),
    do: "Firmware can only be sent to devices selected on this page. Clear the selection and choose them here."

  defp firmware_unavailable(false),
    do: "Filter the list to one platform first, so every firmware offered fits all the selected devices."

  defp move_target_orgs(scope, org_ids, product) do
    Enum.filter(scope.user.orgs, fn org ->
      org.id in org_ids and other_products(org, product) != []
    end)
  end

  defp other_products(org, product), do: Enum.reject(org.products, &(&1.id == product.id))

  defp move_alert(nil), do: false

  defp move_alert(%{name: product_name}) do
    """
    This will move the selected device(s) to the #{product_name} product

    Any existing signing keys the devices may use will attempt to be migrated if they do not exist on the target organization.

    Moving devices may also trigger an update if there are matching deployments on the new product. It is up to the user to ensure any required signing keys are on the device before migrating them to a new product with a new firmware or the device may fail to update.

    Do you wish to continue?
    """
  end

  defp segment_class() do
    [
      "relative flex-1 cursor-pointer rounded px-2.5 py-1.5 text-center text-xs leading-none font-medium whitespace-nowrap text-content-muted hover:text-content-strong",
      "has-checked:bg-primary has-checked:text-primary-content has-checked:shadow-control light:has-checked:bg-indigo-600",
      "has-focus-visible:outline-2 has-focus-visible:outline-offset-1 has-focus-visible:outline-focus-ring"
    ]
  end

  defp input_class(),
    do:
      "h-7.5 rounded border border-line-control bg-surface-raised px-2.5 py-0 text-ui/4 text-content-body placeholder:text-content-faint focus:border-primary focus:ring-0 disabled:text-content-faint"

  defp menu_item_class(),
    do:
      "flex w-full cursor-pointer items-center gap-2 px-3 py-1.75 text-left text-ui/4 text-content-body hover:bg-base-800 hover:text-content-strong light:hover:bg-surface-muted max-sm:px-4 max-sm:py-3 max-sm:text-sm"
end
