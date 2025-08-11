defmodule NervesHubWeb.API.DeviceCertificateJSON do
  @moduledoc false

  def index(%{device_certificates: device_certificates}) do
    %{data: for(dc <- device_certificates, do: device_certificate(dc))}
  end

  def show(%{device_certificate: device_certificate}) do
    %{data: device_certificate(device_certificate)}
  end

  def device_certificate(device_certificate) do
    %{
      serial: device_certificate.serial,
      not_before: device_certificate.not_before,
      not_after: device_certificate.not_after
    }
  end

  def cert(%{cert: cert}) do
    %{data: %{cert: cert}}
  end
end
