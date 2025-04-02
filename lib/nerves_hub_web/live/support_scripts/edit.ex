defmodule NervesHubWeb.Live.SupportScripts.Edit do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Scripts

  @impl Phoenix.LiveView
  def mount(
        %{"script_id" => script_id},
        _session,
        %{assigns: %{org: org, product: product}} = socket
      ) do
    script = Scripts.get_by_product_and_id!(product, script_id)

    socket
    |> page_title("Edit Support Script - #{org.name}")
    |> sidebar_tab(:support_scripts)
    |> assign(:form, to_form(Ecto.Changeset.change(script)))
    |> assign(:script, script)
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_event(
        "update-script",
        %{"script" => script_params},
        %{assigns: %{org: org, product: product, script: script, org_user: org_user}} = socket
      ) do
    authorized!(:"support_script:update", org_user)

    case Scripts.update(script, org_user.user, script_params) do
      {:ok, _script} ->
        socket
        |> put_flash(:info, "Support Script updated")
        |> send_toast(:info, "Support Script updated successfully.")
        |> push_navigate(to: ~p"/org/#{org.name}/#{product.name}/scripts")
        |> noreply()

      {:error, changeset} ->
        socket
        |> send_toast(:error, "There was an error updating the Support Script.")
        |> assign(:form, to_form(changeset))
        |> noreply()
    end
  end

  @impl Phoenix.LiveView
  def handle_event(
        "delete-script",
        %{"id" => id},
        %{assigns: %{org: org, org_user: org_user, product: product}} = socket
      ) do
    authorized!(:"support_script:delete", org_user)

    case Scripts.delete(id, product, org_user.user) do
      {:ok, _} ->
        socket
        |> put_flash(:info, "Support Script deleted")
        |> send_toast(:info, "Support Script deleted successfully.")
        |> push_navigate(to: ~p"/org/#{org.name}/#{product.name}/scripts")
        |> noreply()

      {:error, _} ->
        socket
        |> send_toast(:error, "There was an error deleting the Support Script.")
        |> noreply()
    end
  end
end
