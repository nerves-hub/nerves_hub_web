defmodule NervesHubWeb.Live.ScriptRuns.New do
  @moduledoc """
  The form for starting a bulk script run.

  Shaped like the support script form, with a second section for choosing the
  devices. The code itself can be typed here or copied from a support script;
  either way what is submitted is a snapshot, so later edits to the script it
  came from do not change what this run recorded.
  """

  use NervesHubWeb, :live_view

  alias NervesHub.Devices
  alias NervesHub.ManagedDeployments
  alias NervesHub.ScriptRunners
  alias NervesHub.ScriptRunners.ScriptRunner
  alias NervesHub.Scripts
  alias NervesHub.Scripts.Script

  # How many unmatched identifiers the flash names before falling back to a count.
  @unmatched_named_limit 10

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    authorized!(:"script_runner:create", scope)

    socket
    |> page_title("Run a Script - #{scope.product.name}")
    |> sidebar_tab(:support_scripts)
    |> assign(:scripts, Scripts.all_by_product(scope.product))
    |> assign(:available_tags, Devices.distinct_tags_for_product(scope.product))
    |> assign(:deployment_groups, ManagedDeployments.get_deployment_groups_by_product(scope.product))
    |> assign(:identifier_source, :typed)
    |> assign(:csv_identifiers, [])
    |> assign(:csv_filename, nil)
    |> allow_upload(:identifiers_csv, accept: ~w(.csv), max_entries: 1, auto_upload: true, progress: &handle_progress/3)
    |> assign_form(%{})
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"script_runner" => params}, socket) do
    socket
    |> assign_form(params)
    |> noreply()
  end

  # Typing and uploading are alternatives rather than two halves of one list, so
  # switching drops whatever the other side held. Leaving it behind would mean
  # submitting identifiers that are no longer on screen.
  def handle_event("identifier-source", %{"identifier_source" => source}, socket) do
    params = put_in_filter(socket.assigns.params, "identifiers", "")

    socket
    |> assign(:identifier_source, if(source == "csv", do: :csv, else: :typed))
    |> assign(:csv_identifiers, [])
    |> assign(:csv_filename, nil)
    |> assign_form(params)
    |> noreply()
  end

  def handle_event("remove-csv", _params, socket) do
    socket
    |> assign(:csv_identifiers, [])
    |> assign(:csv_filename, nil)
    |> noreply()
  end

  # Copying a support script fills in the fields it can and leaves them editable;
  # the name is only taken when the operator has not already given the run one of
  # its own.
  #
  # `phx-change` on the picker sends that one input rather than the whole form, so
  # the fields already filled in come from the last params the form sent, which
  # `assign_form/2` keeps.
  def handle_event("copy-script", %{"script_id" => script_id}, socket) do
    case Enum.find(socket.assigns.scripts, &(to_string(&1.id) == script_id)) do
      nil ->
        socket
        |> assign(:copied_script_id, "")
        |> noreply()

      script ->
        params =
          socket.assigns.params
          |> Map.put("text", script.text)
          |> Map.put("language", to_string(script.language))
          |> Map.update("name", script.name, fn
            "" -> script.name
            name -> name
          end)

        socket
        |> assign(:copied_script_id, script_id)
        |> assign_form(params)
        |> noreply()
    end
  end

  def handle_event("create-run", %{"script_runner" => params}, %{assigns: %{current_scope: scope}} = socket) do
    authorized!(:"script_runner:create", scope)

    params = merge_csv_identifiers(params, socket.assigns)

    case ScriptRunners.create(scope, scope.user, params) do
      {:ok, runner, unmatched} ->
        socket
        |> put_flash(:info, "Running “#{runner.name}” on #{runner.device_count} #{devices(runner.device_count)}.")
        |> maybe_warn_unmatched(unmatched)
        |> push_navigate(to: ~p"/org/#{scope.org}/#{scope.product}/scripts/runs")
        |> noreply()

      # Not a changeset error -- the filter is valid, it just selected nothing --
      # so there is no field to hang it on.
      {:error, :no_devices} ->
        socket
        |> put_flash(:error, "No devices matched the filter, so there is nothing to run.")
        |> assign_form(params)
        |> noreply()

      {:error, changeset} ->
        socket
        |> put_flash(:error, "There was an error starting the Script Run.")
        |> assign(:form, to_form(changeset))
        |> noreply()
    end
  end

  @doc false
  def handle_progress(:identifiers_csv, %{done?: true} = entry, socket) do
    result =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        {:ok, Devices.parse_identifier_csv(path)}
      end)

    case result do
      {:error, :invalid_csv} ->
        socket
        |> put_flash(:error, "CSV must have a single 'identifier' column header")
        |> noreply()

      {:ok, []} ->
        socket
        |> put_flash(:error, "CSV contained no identifier values")
        |> noreply()

      {:ok, identifiers} ->
        socket
        |> assign(:csv_identifiers, identifiers)
        |> assign(:csv_filename, entry.client_name)
        |> noreply()
    end
  end

  def handle_progress(:identifiers_csv, _entry, socket), do: noreply(socket)

  # The upload cannot sit inside the main form -- nested forms are not valid HTML
  # -- so the identifiers it read are held in the socket and put into the params on
  # the way to the changeset.
  defp merge_csv_identifiers(params, %{identifier_source: :csv, csv_identifiers: identifiers}) do
    put_in_filter(params, "identifiers", identifiers)
  end

  defp merge_csv_identifiers(params, _typed), do: params

  defp put_in_filter(params, key, value) do
    Map.update(params, "filter", %{key => value}, &Map.put(&1, key, value))
  end

  defp assign_form(socket, params) do
    scope = socket.assigns.current_scope

    changeset = ScriptRunner.create_changeset(scope.product, scope.user, params)

    socket
    |> assign(:form, to_form(changeset, action: if(params != %{}, do: :validate)))
    |> assign(:filter_type, Ecto.Changeset.get_field(changeset, :filter_type))
    # Kept because `phx-change` on a single input sends only that input; the
    # script picker needs the rest of the form to merge into.
    |> assign(:params, params)
    |> assign_new(:copied_script_id, fn -> "" end)
  end

  # Which filter values are required is decided by `filter_type`, so the
  # changeset hangs those errors on the embed as a whole rather than on one of its
  # fields, and `inputs_for` has nowhere to render them. They are surfaced only
  # once a run has actually been submitted -- while the form is still being filled
  # in, "at least one tag is required" is not yet news.
  defp filter_errors(%{source: %Ecto.Changeset{action: :insert} = changeset}) do
    for {:filter, {message, _opts}} <- changeset.errors, do: message
  end

  defp filter_errors(_form), do: []

  defp maybe_warn_unmatched(socket, []), do: socket

  # `:notice` rather than `:warning`: the flash group only renders `:notice`,
  # `:info` and `:error`, and this sits alongside the success flash.
  #
  # Only the first few are named. A flash goes into the session cookie, which
  # browsers cap at 4KB, and a CSV of mostly-unknown identifiers would otherwise
  # put every one of them in there -- 8,000 of them measured 147KB. The count is
  # the part worth reading anyway; which ones they were is a question for the run's
  # own page.
  defp maybe_warn_unmatched(socket, unmatched) do
    count = length(unmatched)
    named = Enum.take(unmatched, @unmatched_named_limit)

    message =
      case count - length(named) do
        0 -> "#{count} #{identifiers(count)} matched no device: #{Enum.join(named, ", ")}"
        rest -> "#{count} #{identifiers(count)} matched no device: #{Enum.join(named, ", ")} and #{rest} more"
      end

    put_flash(socket, :notice, message)
  end

  defp devices(1), do: "device"
  defp devices(_many), do: "devices"

  defp identifiers(1), do: "identifier"
  defp identifiers(_many), do: "identifiers"

  # The form posts the language as a string while it is being edited, and as an
  # atom when it comes back from the struct.
  defp syntax_hint(language) when language in [:shell, "shell"] do
    "Make sure this is valid shell and will not crash the device"
  end

  defp syntax_hint(_elixir) do
    "Make sure this is valid Elixir and will not crash the device"
  end
end
