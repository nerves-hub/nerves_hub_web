defmodule NervesHub.Ash.Devices do
  use Ash.Domain,
    extensions: [AshJsonApi.Domain, AshGraphql.Domain]

  resources do
    resource NervesHub.Ash.Devices.Device
    resource NervesHub.Ash.Devices.DeviceCertificate
    resource NervesHub.Ash.Devices.CACertificate
    resource NervesHub.Ash.Devices.DeviceConnection
    resource NervesHub.Ash.Devices.DeviceHealth
    resource NervesHub.Ash.Devices.DeviceMetric
    resource NervesHub.Ash.Devices.InflightUpdate
    resource NervesHub.Ash.Devices.PinnedDevice
    resource NervesHub.Ash.Devices.JITP
    resource NervesHub.Ash.Devices.DeviceSharedSecretAuth
  end
end
