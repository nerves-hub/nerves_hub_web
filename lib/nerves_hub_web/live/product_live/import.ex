defmodule NervesHubWeb.ProductLive.Import do
  use NervesHubWeb, :live_view

  require Logger

  alias NervesHub.{Accounts, Devices, Devices.Device, Products}
  alias NimbleCSV.RFC4180, as: CSV

  @import_limit 1000

  def render(assigns) do
    NervesHubWeb.ProductView.render("import.html", assigns)
  end

  def mount(
        _params,
        %{
          "auth_user_id" => user_id,
          "org_id" => org_id,
          "product_id" => product_id
        },
        socket
      ) do
    socket =
      socket
      |> assign_new(:user, fn -> Accounts.get_user!(user_id) end)
      |> assign_new(:org, fn -> Accounts.get_org!(org_id) end)
      |> assign_new(:product, fn -> Products.get_product!(product_id) end)
      |> assign(:active_tab, :upload)
      |> assign(:results, [])
      |> allow_upload(:csv,
        accept: [".csv"],
        auto_upload: true,
        max_entries: 1,
        progress: &handle_progress/3
      )

    {:ok, socket}
  rescue
    exception ->
      Logger.error(Exception.format(:error, exception, __STACKTRACE__))
      socket_error(socket, live_view_error(exception))
  end

  # Catch-all to handle when LV sessions change.
  # Typically this is after a deploy when the
  # session structure in the module has changed
  # for mount/3
  def mount(_, _, socket) do
    socket_error(socket, live_view_error(:update))
  end

  def handle_event("validate", _params, socket) do
    case uploaded_entries(socket, :csv) do
      {_, [%{valid?: false, client_name: name}]} ->
        {:noreply,
         put_flash(socket, :error, "File must be .csv extension. Got #{Path.extname(name)}")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("tab-change", %{"tab" => tab_str}, socket) do
    tab = String.to_existing_atom(tab_str)
    {:noreply, assign(socket, :active_tab, tab)}
  end

  def handle_event("restart", _, socket) do
    {:noreply, assign(socket, active_tab: :upload, results: [])}
  end

  def handle_event("delete", %{"line" => line_str}, socket) do
    line_num = String.to_integer(line_str)
    results = Enum.reject(socket.assigns.results, &match?({^line_num, _, _, _}, &1))
    {:noreply, assign(socket, results: results)}
  end

  def handle_event("import-one", %{"line" => line_str}, socket) do
    line_num = String.to_integer(line_str)

    results =
      Enum.find(socket.assigns.results, &match?({^line_num, _, _, _}, &1))
      |> do_import()
      |> handle_import_result(line_num, socket.assigns.results)

    {:noreply, assign(socket, results: results)}
  end

  def handle_event("import-all", _, socket) do
    for line = {ln, level, _, _} <- socket.assigns.results, level in [:new, :updating] do
      GenServer.cast(socket.root_pid, {:import_result, ln, do_import(line)})
    end

    {:noreply, socket}
  end

  def handle_cast({:parse_line, line_num, line}, socket) do
    {:noreply, format_csv_line(socket, line_num, Products.parse_csv_line(line))}
  end

  def handle_cast({:import_result, line_num, result}, socket) do
    {:noreply, update(socket, :results, &handle_import_result(result, line_num, &1))}
  end

  defp maybe_update_changeset({line_num, _, _, c}, line_num, changeset) do
    {line_num, :warning, changeset, c}
  end

  defp maybe_update_changeset(line, _, _), do: line

  defp maybe_update_certs({line_num, _, c, certs_attrs}, line_num, cert_serial) do
    updated_attrs =
      for attrs <- certs_attrs do
        if attrs[:serial] == cert_serial, do: :failed_cert_import, else: attrs
      end

    {line_num, :warning, c, updated_attrs}
  end

  defp maybe_update_certs(result, _, _), do: result

  defp handle_progress(:csv, entry, socket) do
    socket =
      if entry.done? do
        consume_uploaded_entry(socket, entry, &parse_csv(socket, &1.path))
      else
        socket
      end

    {:noreply, socket}
  end

  defp parse_csv(socket, path) do
    expected_headers = Products.__csv_header__()

    File.read!(path)
    |> CSV.parse_string(skip_headers: false)
    |> case do
      [^expected_headers | rest] when length(rest) <= @import_limit ->
        for {line, line_num} <- Enum.with_index(rest, 2) do
          GenServer.cast(socket.root_pid, {:parse_line, line_num, line})
        end

        assign(socket, :active_tab, :all)

      [^expected_headers | rest] ->
        put_flash(socket, :error, "CSV exceeds 1000 line import limit - Got: #{length(rest)}")

      _bad ->
        put_flash(socket, :error, "Malformed CSV headers")
    end
  end

  defp format_csv_line(socket, line_num, {:malformed, _line, parse_attempt}) do
    labeled = {line_num, :malformed, device_changeset(socket, parse_attempt), []}
    update(socket, :results, &sort_results([labeled | &1]))
  end

  defp format_csv_line(socket, line_num, attrs) do
    product = socket.assigns.product
    org = socket.assigns.org
    attrs = Map.merge(attrs, %{product_id: product.id, org_id: org.id})

    changeset =
      device_changeset(socket, attrs)
      |> maybe_org_invalid(attrs.org, org.name)
      |> maybe_product_invalid(attrs.product, product.name)

    result = {line_num, label_line(changeset, attrs.certificates), changeset, attrs.certificates}

    update(socket, :results, &sort_results([result | &1]))
  end

  def label_line(changeset, certs_attrs) do
    state = changeset.data.__meta__.state

    cond do
      not changeset.valid? or not Enum.all?(certs_attrs, &is_map/1) ->
        :warning

      state == :built ->
        :new

      state == :loaded ->
        :updating
    end
  end

  defp device_changeset(%{assigns: assigns}, attrs) do
    device =
      case Devices.get_device_by(
             identifier: attrs.identifier,
             org_id: assigns.org.id,
             product_id: assigns.product.id
           ) do
        {:ok, device} ->
          device

        _ ->
          %Device{}
      end

    Device.changeset(device, attrs)
  end

  defp maybe_org_invalid(changeset, expected, current) do
    if expected == current do
      changeset
    else
      Ecto.Changeset.add_error(changeset, :org, "does not match current expected org",
        expected: expected
      )
    end
  end

  defp maybe_product_invalid(changeset, expected, current) do
    if expected == current do
      changeset
    else
      Ecto.Changeset.add_error(changeset, :product, "does not match current expected product",
        expected: expected
      )
    end
  end

  defp sort_results(results) do
    # Line number is first element of tuple
    Enum.sort_by(results, &elem(&1, 0))
  end

  defp do_import({_, _, changeset, certs_attrs}) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert_or_update(:device, changeset)
    |> add_certs_multi(certs_attrs)
    |> NervesHub.Repo.transaction()
  end

  defp handle_import_result(result, line_num, results) do
    case result do
      {:ok, _} ->
        Enum.reject(results, &match?({^line_num, _, _, _}, &1))

      {:error, :device, changeset, _} ->
        Enum.map(results, &maybe_update_changeset(&1, line_num, changeset))

      {:error, cert_serial, _, _} ->
        Enum.map(results, &maybe_update_certs(&1, line_num, cert_serial))
    end
  end

  defp add_certs_multi(multi, certs_attrs) do
    for attrs <- certs_attrs, reduce: multi do
      acc ->
        Ecto.Multi.run(acc, attrs.serial, &create_or_update_device_certificate(&1, &2, attrs))
    end
  end

  defp create_or_update_device_certificate(_repo, %{device: device}, attrs) do
    case Devices.get_device_certificate_by_device_and_serial(device, attrs.serial) do
      {:ok, db_cert} ->
        Devices.update_device_certificate(db_cert, attrs)

      _ ->
        Devices.create_device_certificate(device, attrs)
    end
  end
end
