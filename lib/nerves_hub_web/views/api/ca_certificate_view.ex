defmodule NervesHubWeb.API.CACertificateView do
  use NervesHubWeb, :api_view

  alias NervesHub.Devices.CACertificate.JITP
  alias NervesHubWeb.API.CACertificateView

  def render("index.json", %{ca_certificates: ca_certificates}) do
    %{data: render_many(ca_certificates, CACertificateView, "ca_certificate.json")}
  end

  def render("show.json", %{ca_certificate: ca_certificate}) do
    %{data: render_one(ca_certificate, CACertificateView, "ca_certificate.json")}
  end

  def render("ca_certificate.json", %{ca_certificate: ca_certificate}) do
    %{
      serial: ca_certificate.serial,
      not_before: ca_certificate.not_before,
      not_after: ca_certificate.not_after,
      description: ca_certificate.description,
      jitp: maybe_add_jitp(ca_certificate.jitp)
    }
  end

  defp maybe_add_jitp(%JITP{} = jitp) do
    %{
      product_name: jitp.product.name,
      tags: jitp.tags,
      description: jitp.description
    }
  end

  defp maybe_add_jitp(_), do: nil
end
