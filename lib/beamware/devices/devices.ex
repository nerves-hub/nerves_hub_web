defmodule Beamware.Devices do
  import Ecto.Query

  alias Beamware.Devices.Device
  alias Beamware.Accounts.Tenant
  alias Beamware.Repo

  def get_devices(%Tenant{id: tenant_id}) do
    query = from(d in Device,
                 where: d.tenant_id == ^tenant_id)

    query
    |> Repo.all()
  end
end
