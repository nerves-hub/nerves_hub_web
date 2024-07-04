defmodule NervesHubWeb.Live.SupportScripts.New do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Scripts
  alias NervesHub.Scripts.Script

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket
    |> page_title("New Support Script - #{socket.assigns.org.name}")
    |> assign(:form, to_form(Script.changeset(%Script{}, %{})))
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_event("create_script", %{"script" => script_params}, socket) do
    authorized!(:create_support_script, socket.assigns.org_user)

    %{org: org, product: product} = socket.assigns

    case Scripts.create(product, script_params) do
      {:ok, _command} ->
        socket
        |> put_flash(:info, "Support Script created")
        |> push_navigate(to: ~p"/org/#{org.name}/#{product.name}/scripts")
        |> noreply()

      {:error, changeset} ->
        socket
        |> assign(:form, to_form(changeset))
        |> noreply()
    end
  end
end
