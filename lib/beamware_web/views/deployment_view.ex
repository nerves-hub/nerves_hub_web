defmodule BeamwareWeb.DeploymentView do
  use BeamwareWeb, :view

  alias Beamware.Firmwares.Firmware

  def firmware_dropdown_options(firmwares) do
    firmwares
    |> Enum.map(&[value: &1.id, key: firmware_display_name(&1)])
  end

  def firmware_display_name(%Firmware{} = f) do
    case Firmware.version(f) do
      {:ok, version} -> "#{version} (#{f.product})"
      {:error, _} -> f.product
    end
  end
end
