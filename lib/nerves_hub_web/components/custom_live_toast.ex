defmodule NervesHubWeb.Components.CustomLiveToast do
  use NervesHubWeb, :component

  attr(:flash, :map, required: true, doc: "the map of flash messages")
  attr(:id, :string, default: "toast-group", doc: "the optional id of flash container")
  attr(:connected, :boolean, required: true, doc: "whether we're in a liveview or not")
  attr(:kinds, :list, default: [:info, :error], doc: "the valid severity level kinds")

  attr(:corner, :atom,
    values: [:top_left, :top_center, :top_right, :bottom_left, :bottom_center, :bottom_right],
    default: :bottom_right,
    doc: "the corner to display the toasts"
  )

  attr(:group_class_fn, :any,
    default: &LiveToast.group_class_fn/1,
    doc: "function to override the container classes"
  )

  attr(:toast_class_fn, :any,
    default: &LiveToast.toast_class_fn/1,
    doc: "function to override the toast classes"
  )

  attr(:toasts_sync, :list,
    required: true,
    doc: "toasts that get synchronized when calling `put_toast`"
  )

  def render(assigns) do
    ~H"""
    <.live_component
      :if={@connected}
      id={@id}
      module={NervesHubWeb.Components.LiveToast.LiveComponent}
      toasts_sync={@toasts_sync}
      corner={@corner}
      toast_class_fn={@toast_class_fn}
      group_class_fn={@group_class_fn}
      f={@flash}
      kinds={@kinds}
    />
    """
  end

  def toast_class_fn(assigns) do
    [
      # base classes
      "group/toast z-100 pointer-events-auto relative w-full items-center justify-between origin-center overflow-hidden rounded p-3 shadow border col-start-1 col-end-1 row-start-1 row-end-2",
      # start hidden if javascript is enabled
      "[@media(scripting:enabled)]:opacity-0 [@media(scripting:enabled){[data-phx-main]_&}]:opacity-100",
      # used to hide the disconnected flashes
      if(assigns[:rest][:hidden] == true, do: "hidden", else: "flex"),
      # override styles per severity
      assigns[:kind] == :info && "bg-white text-black",
      assigns[:kind] == :error && "!text-red-700 !bg-red-100 border-red-200"
    ]
  end
end

defmodule NervesHubWeb.Components.LiveToast.LiveComponent do
  @moduledoc false

  use Phoenix.LiveComponent

  alias LiveToast.Components
  alias LiveToast.Utility

  @impl Phoenix.LiveComponent
  def mount(socket) do
    socket =
      socket
      |> stream_configure(:toasts,
        dom_id: fn %LiveToast{uuid: id} ->
          "toast-#{id}"
        end
      )
      |> stream(:toasts, [])
      |> assign(:toast_count, 0)

    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    # todo: make sure this works when doing multiple toasts at once. even tho thats unlikely.
    # handling of synchronous toasts when calling put_toast
    # basically, we need to read assigns["toasts_sync"], to see if there was a new toast popped on from put_toast.
    # If there was, we need to look for a corresponding flash message (with the same kind and message) and remove it.
    sync_toasts = Map.get(assigns, :toasts_sync, [])

    sync_toast =
      if sync_toasts && sync_toasts != [] do
        List.first(sync_toasts)
      else
        %{}
      end

    flash_map = assigns[:f]

    sync_toast_kind = Map.get(sync_toast, :kind, nil)

    sync_toast_kind =
      if is_atom(sync_toast_kind) do
        Atom.to_string(sync_toast_kind)
      end

    f =
      flash_map[sync_toast_kind]

    socket =
      if f && f == Map.get(sync_toast, :msg) do
        {toasts, assigns} = Map.pop(assigns, :toasts)
        toasts = toasts || []
        toasts = [sync_toast | toasts]

        new_f = put_in(assigns[:f][sync_toast_kind], nil)
        assigns = Map.put(assigns, :f, new_f)

        socket
        |> assign(assigns)
        |> stream(:toasts, toasts)
        |> assign(:toast_count, socket.assigns.toast_count + length(toasts))
        # instead of clearing flash here, we jsut send a message to the frontend to do it.
        #  The advantage is this makes it work properly even across a navigation.
        |> push_event("clear-flash", %{key: sync_toast.kind})
      else
        {toasts, assigns} = Map.pop(assigns, :toasts)
        toasts = toasts || []

        socket
        |> assign(assigns)
        |> stream(:toasts, toasts)
        |> assign(:toast_count, socket.assigns.toast_count + length(toasts))
      end

    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id={assigns[:id] || "toast-group"} class={@group_class_fn.(assigns)}>
      <div class="contents" id="toast-group-stream" phx-update="stream">
        <Components.toast
          :for={
            {dom_id,
             %LiveToast{
               kind: k,
               msg: body,
               title: title,
               icon: icon,
               action: action,
               duration: duration,
               component: component
             }} <- @streams.toasts
          }
          id={dom_id}
          data-count={@toast_count}
          duration={duration}
          kind={k}
          toast_class_fn={@toast_class_fn}
          component={component}
          icon={icon}
          action={action}
          corner={@corner}
          title={if title, do: Utility.translate(title), else: nil}
          target={@myself}
        >
          {Utility.translate(body)}
        </Components.toast>
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_event("clear", %{"id" => "toast-" <> uuid}, socket) do
    socket =
      socket
      |> stream_delete_by_dom_id(:toasts, "toast-#{uuid}")
      |> assign(:toast_count, socket.assigns.toast_count - 1)

    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("clear", _payload, socket) do
    # non matches are not unexpected, because the user may
    # have dismissed the toast before the animation ended.
    {:noreply, socket}
  end
end

defmodule NervesHubWeb.LiveToast do
  alias Phoenix.LiveView

  defp make_toast(kind, msg, options) do
    container_id = options[:container_id] || "toast-group"
    uuid = options[:uuid] || Ecto.UUID.generate()

    %LiveToast{
      kind: kind,
      msg: msg,
      title: options[:title],
      icon: options[:icon],
      action: options[:action],
      component: options[:component],
      duration: options[:duration],
      container_id: container_id,
      uuid: uuid,
      sync: options[:sync] || false
    }
  end

  @doc """
  Send a new toast message to the LiveToast component.

  Returns the UUID of the new toast message. This UUID can be passed back
  to another call to `send_toast/3` to update the properties of an existing toast.

  ## Examples

      iex> send_toast(:info, "Thank you for logging in!", title: "Welcome")
      "00c90156-56d1-4bca-a9e2-6353d49c974a"

  """
  def send_toast(kind, msg, options \\ []) do
    toast = make_toast(kind, msg, options)

    LiveView.send_update(NervesHubWeb.Components.LiveToast.LiveComponent,
      id: toast.container_id,
      toasts: [toast]
    )

    toast.uuid
  end
end
