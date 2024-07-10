defmodule NervesHubWeb.Live.SupportScripts.Edit do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Scripts
  alias NervesHub.Scripts.Script

  @impl Phoenix.LiveView
  def mount(
        %{"script_id" => script_id},
        _session,
        %{assigns: %{product: product}} = socket
      ) do
    {:ok, script} = Scripts.get(product, script_id)

    socket
    |> page_title("Edit Support Script - #{socket.assigns.org.name}")
    |> assign(:form, to_form(Script.changeset(script, %{})))
    |> assign(:script, script)
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_event("update_script", %{"script" => script_params}, socket) do
    authorized!(:"support_script:update", socket.assigns.org_user)

    %{org: org, product: product} = socket.assigns

    case Scripts.update(socket.assigns.script, script_params) do
      {:ok, _command} ->
        socket
        |> put_flash(:info, "Support Script updated")
        |> push_navigate(to: ~p"/org/#{org.name}/#{product.name}/scripts")
        |> noreply()

      {:error, changeset} ->
        socket
        |> assign(:form, to_form(changeset))
        |> noreply()
    end
  end
end
