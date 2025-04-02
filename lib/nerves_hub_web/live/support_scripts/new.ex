defmodule NervesHubWeb.Live.SupportScripts.New do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Scripts
  alias NervesHub.Scripts.Script

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket
    |> page_title("New Support Script - #{socket.assigns.org.name}")
    |> sidebar_tab(:support_scripts)
    |> assign(:form, to_form(Ecto.Changeset.change(%Script{})))
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_event(
        "create-script",
        %{"script" => script_params},
        %{assigns: %{org_user: org_user, org: org, product: product}} = socket
      ) do
    authorized!(:"support_script:create", org_user)

    case Scripts.create(product, org_user.user, script_params) do
      {:ok, _script} ->
        socket
        |> put_flash(:info, "Support Script created")
        |> send_toast(:info, "Support Script created successfully.")
        |> push_navigate(to: ~p"/org/#{org.name}/#{product.name}/scripts")
        |> noreply()

      {:error, changeset} ->
        socket
        |> send_toast(:error, "There was an error saving the Support Script.")
        |> assign(:form, to_form(changeset))
        |> noreply()
    end
  end
end
