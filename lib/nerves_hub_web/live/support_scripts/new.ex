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
  def handle_event("validate", %{"script" => script_params}, socket) do
    changeset = Script.validate_changeset(script_params)

    socket
    |> assign(:form, to_form(changeset, action: :validate))
    |> noreply()
  end

  def handle_event(
        "create-script",
        %{"script" => script_params},
        %{assigns: %{org_user: org_user, org: org, product: product}} = socket
      ) do
    authorized!(:"support_script:create", org_user)

    case Scripts.create(product, org_user.user, script_params) do
      {:ok, _script} ->
        socket
        |> put_flash(:info, "Support Script created successfully.")
        |> push_navigate(to: ~p"/org/#{org}/#{product}/scripts")
        |> noreply()

      {:error, changeset} ->
        socket
        |> put_flash(:error, "There was an error saving the Support Script.")
        |> assign(:form, to_form(changeset))
        |> noreply()
    end
  end
end
