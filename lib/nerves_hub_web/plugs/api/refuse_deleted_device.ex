defmodule NervesHubWeb.API.Plugs.RefuseDeletedDevice do
  @moduledoc """
  Refuses a request that would act on a soft-deleted device.

  A deleted device can still be looked up, so that it can be shown and
  restored, but nothing should be sent to it until it is restored. The
  dashboard's device page says as much, and `NervesHub.Devices.Device.changeset/2`
  already refuses to update one. Must run after `NervesHubWeb.API.Plugs.Device`
  has assigned the device.
  """

  use NervesHubWeb, :plug

  alias NervesHubWeb.API.ErrorJSON

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%{assigns: %{device: %{deleted_at: nil}}} = conn, _opts), do: conn

  def call(conn, _opts) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: ErrorJSON)
    |> render(:"422", reason: "Device is deleted and must be restored to use.")
    |> halt()
  end
end
