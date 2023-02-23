defmodule NervesHubWeb.API.DeviceCertificateView do
  use NervesHubWeb, :api_view

  alias NervesHubWeb.API.DeviceCertificateView

  def render("index.json", %{device_certificates: device_certificates}) do
    %{data: render_many(device_certificates, DeviceCertificateView, "device_certificate.json")}
  end

  def render("show.json", %{device_certificate: device_certificate}) do
    %{data: render_one(device_certificate, DeviceCertificateView, "device_certificate.json")}
  end

  def render("device_certificate.json", %{device_certificate: device_certificate}) do
    %{
      serial: device_certificate.serial,
      not_before: device_certificate.not_before,
      not_after: device_certificate.not_after
    }
  end

  def render("cert.json", %{cert: cert}) do
    %{data: %{cert: cert}}
  end
end
