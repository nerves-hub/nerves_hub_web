defmodule NervesHub.Ash.Firmwares do
  use Ash.Domain,
    extensions: [AshJsonApi.Domain, AshGraphql.Domain]

  resources do
    resource NervesHub.Ash.Firmwares.Firmware
    resource NervesHub.Ash.Firmwares.FirmwareDelta
    resource NervesHub.Ash.Firmwares.FirmwareTransfer
  end
end
