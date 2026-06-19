defmodule NervesHubWeb.Components.BulkActionsSidebar do
  use NervesHubWeb, :component

  def render(assigns) do
    ~H"""
    <div class="pointer-events-none fixed inset-y-0 right-0 z-40 mb-[119px] flex max-w-full pl-10 sm:pl-16">
      <div class={[
        "bg-surface-muted border-base-700 shadow-filter-slider pointer-events-auto mt-[55px] flex h-full w-screen max-w-80 flex-col border-y border-l transition-transform",
        Enum.empty?(@selected_devices) && "translate-x-full",
        Enum.empty?(@selected_devices) && "invisible"
      ]}>
        <div class="h-0 flex-1 overflow-y-auto">
          <div class="border-base-700 flex h-14 items-center border-b px-4 py-3">
            <h4 :if={length(@selected_devices) == 1 and not @select_all_matching} class="text-base font-semibold">1 device selected</h4>
            <h4 :if={length(@selected_devices) > 1 and not @select_all_matching} class="text-base font-semibold">
              {length(@selected_devices) |> Number.Delimit.number_to_delimited(precision: 0)} devices selected
            </h4>
            <h4 :if={@select_all_matching} class="text-base font-semibold">All devices selected</h4>

            <button class="ml-auto cursor-pointer p-1.5" type="button" phx-click="deselect-all">
              <svg xmlns="http://www.w3.org/2000/svg" class="size-5" viewBox="0 0 20 20" fill="none">
                <path
                  d="M10.0002 9.99998L5.8335 5.83331M10.0002 9.99998L14.1668 14.1666M10.0002 9.99998L14.1668 5.83331M10.0002 9.99998L5.8335 14.1666"
                  stroke="#A1A1AA"
                  stroke-width="1.2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
              </svg>
            </button>
          </div>

          <div class="flex flex-1 flex-col gap-6 px-4 pt-6">
            <span :if={length(@selected_devices) == @total_entries or @select_all_matching}>All available devices matching the filters have been selected.</span>
            <div :if={length(@selected_devices) != @total_entries and not @select_all_matching}>
              <span>{Number.Delimit.number_to_delimited(@total_entries - length(@selected_devices), precision: 0)} additional devices match the filters but haven't been selected.</span>
              <button class="sidebar-button" type="button" phx-click="select-all-matching">
                Select all
              </button>
            </div>
          </div>

          <div class="flex flex-1 flex-col gap-6 px-4 py-6">
            <form id="product-move" class="flex flex-col gap-2" phx-change="target-product" phx-submit="move-devices-product">
              <label for="move_to" class="sidebar-label">Move device(s) to product:</label>

              <div class="flex gap-2">
                <select name="product_id" id="move_to" class="sidebar-select" phx-update="ignore">
                  <option value="">Select product</option>
                  <%= for org <- @current_scope.user.orgs, products = org.products, length(products) > 0 do %>
                    <optgroup label={org.name}>
                      <%= for product <- products, product.id != @product.id do %>
                        <option {target_selected?(@target_product, product.name)} value={product.id}>{product.name}</option>
                      <% end %>
                    </optgroup>
                  <% end %>
                </select>

                <.button style="primary" type="submit" data-confirm={move_alert(@target_product)} {unless @target_product, do: [disabled: true], else: []}>
                  Move
                </.button>
              </div>
            </form>

            <div :if={@selected_have_deployment_groups or @select_all_matching} class="flex flex-col gap-2">
              <label class="sidebar-label">Remove from deployment group</label>
              <div class="flex items-center gap-2">
                <span :if={@selected_shared_deployment_group && not @select_all_matching} class="bg-base-800 border-base-700 flex items-center gap-1 rounded-full border py-0.5 pr-2.5 pl-1.5">
                  <svg class="size-1.5" viewBox="0 0 6 6" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <circle cx="3" cy="3" r="3" fill="#10B981" />
                  </svg>
                  <span class="text-base-300 text-xs tracking-tight">{@selected_shared_deployment_group.name}</span>
                </span>
                <span :if={is_nil(@selected_shared_deployment_group) or @select_all_matching} class="bg-base-800 border-base-700 flex items-center gap-1 rounded-full border py-0.5 pr-2.5 pl-1.5">
                  <span class="text-base-300 text-xs tracking-tight italic">All deployment groups</span>
                </span>
                <button
                  id="remove-devices-from-deployment-group"
                  class="bg-base-800 border-alert cursor-pointer rounded-full border p-1"
                  data-confirm="This will remove all selected devices from their deployment groups. Would you like to continue?"
                  aria-label="Remove selected devices from deployment group"
                  type="button"
                  phx-click="remove-devices-from-deployment-group"
                >
                  <svg class="size-3" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <path
                      d="M12.4999 5.83337H7.49992M12.4999 5.83337H14.9999M12.4999 5.83337C12.4999 4.45266 11.3806 3.33337 9.99992 3.33337C8.61921 3.33337 7.49992 4.45266 7.49992 5.83337M7.49992 5.83337H4.99992M3.33325 5.83337H4.99992M4.99992 5.83337V15C4.99992 15.9205 5.74611 16.6667 6.66659 16.6667H13.3333C14.2537 16.6667 14.9999 15.9205 14.9999 15V5.83337M14.9999 5.83337H16.6666M8.33325 9.16671V13.3334M11.6666 13.3334V9.16671"
                      stroke="#EF4444"
                      stroke-width="1.2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    />
                  </svg>
                </button>
              </div>
            </div>

            <form
              id="deployment-set"
              class="flex flex-col gap-2"
              phx-change="target-deployment-group"
              phx-submit="move-devices-deployment-group"
            >
              <label class="sidebar-label">Assign to deployment group</label>

              <div class="flex gap-2">
                <label for="set_deployment_group" class="hidden">Set deployment group</label>
                <%= if Enum.any?(@valid_deployment_groups_for_selected) do %>
                  <select name="deployment_group" id="set_deployment_group" class="sidebar-select">
                    <option value="">Select deployment group</option>
                    <%= for deployment_group <- @valid_deployment_groups_for_selected do %>
                      <option value={deployment_group.id} {if @target_deployment_group && @target_deployment_group.id == deployment_group.id, do: [selected: true], else: []}>
                        {deployment_group.name} - {deployment_group.current_release.firmware.architecture} - {deployment_group.current_release.firmware.platform}
                      </option>
                    <% end %>
                  </select>
                <% else %>
                  <select name="deployment_group" id="set_deployment_group" class="sidebar-select" disabled>
                    <option value="">(no valid choices)</option>
                  </select>
                <% end %>

                <.button
                  style="primary"
                  type="submit"
                  data-confirm={"This will add the selected devices to #{@target_deployment_group && @target_deployment_group.name}. Would you like to continue?"}
                  {unless @target_deployment_group, do: [disabled: true], else: []}
                >
                  Set
                </.button>
              </div>
            </form>

            <form id="bulk-tag-input" class="flex flex-col gap-2" phx-submit="tag-devices" phx-change="validate-tags">
              <label class="sidebar-label" for="input_set_tags">Set tags</label>
              <div class="flex gap-2">
                <input type="text" class="sidebar-text-input" name="tags" id="input_set_tags" value={@current_filters[:tag]} phx-debounce="500" />

                <.button style="primary" type="submit" data-confirm="This will update tags on all selected devices" {if @valid_tags && @device_tags != "", do: [], else: [disabled: true]}>
                  Set
                </.button>
              </div>
              <div class={if @valid_tags, do: "hidden"}><span class="has-error"> Tags Cannot Contain Spaces </span></div>
            </form>

            <form
              :if={Enum.any?(@available_firmwares_for_filtered_platform) and not @select_all_matching}
              id="push-firmware"
              class="flex flex-col gap-2"
              phx-change="target-firmware"
              phx-submit="push-firmware-to-devices"
            >
              <label class="sidebar-label">Send firmware update (filtered by platform):</label>

              <div class="flex gap-2">
                <label for="firmware_select" class="hidden">Firmware</label>
                <select name="firmware" id="firmware_select" class="sidebar-select" phx-update="ignore">
                  <option value="">Select firmware</option>
                  <option
                    :for={firmware <- @available_firmwares_for_filtered_platform}
                    value={firmware.uuid}
                    selected={@target_firmware && @target_firmware.uuid == firmware.uuid}
                  >
                    {firmware.version} ({String.slice(firmware.uuid, 0..7)})
                  </option>
                </select>

                <.button
                  style="primary"
                  type="submit"
                  data-confirm="This will send the selected firmware to all selected devices. Would you like to continue?"
                  {unless @target_firmware, do: [disabled: true], else: []}
                >
                  Send
                </.button>
              </div>
            </form>

            <div class="flex flex-col gap-2">
              <label>Firmware updates</label>

              <div class="flex w-full gap-2">
                <form class="grow" id="disable-updates" phx-submit="disable-updates-for-devices">
                  <button class="sidebar-button w-full" type="submit" data-confirm="This will disable updates for all selected devices">
                    <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20" fill="none">
                      <path
                        d="M10.0002 10L5.8335 5.83334M10.0002 10L14.1668 14.1667M10.0002 10L14.1668 5.83334M10.0002 10L5.8335 14.1667"
                        stroke="#A1A1AA"
                        stroke-width="1.2"
                        stroke-linecap="round"
                        stroke-linejoin="round"
                      />
                    </svg>
                    <span>Disable</span>
                  </button>
                </form>

                <form class="grow" id="enable-updates" phx-submit="enable-updates-for-devices">
                  <button class="sidebar-button w-full" type="submit" data-confirm="This will enable updates for all selected devices">
                    <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20" fill="none">
                      <path d="M4.1665 10.8333L7.49984 14.1667L16.6665 5" stroke="#A1A1AA" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round" />
                    </svg>
                    Enable
                  </button>
                </form>
              </div>

              <form id="clear-penalty-box" class="mt-2" phx-submit="clear-penalty-box-for-devices">
                <button class="sidebar-button w-full" type="submit" data-confirm="This will clear the penalty box all selected devices">
                  <span class="">Clear penalty box</span>
                </button>
              </form>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp target_selected?(%{name: name}, value) when name == value, do: [selected: true]
  defp target_selected?(_, _), do: []

  defp move_alert(nil), do: ""

  defp move_alert(%{name: product_name}) do
    """
    This will move the selected device(s) to the #{product_name} product

    Any existing signing keys the devices may use will attempt to be migrated if they do not exist on the target organization.

    Moving devices may also trigger an update if there are matching deployments on the new product. It is up to the user to ensure any required signing keys are on the device before migrating them to a new product with a new firmware or the device may fail to update.

    Do you wish to continue?
    """
  end
end
