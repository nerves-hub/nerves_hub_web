defmodule NervesHubWeb.API.CACertificateJSON do
  @moduledoc false

  alias NervesHub.Devices.CACertificate.JITP

  def index(%{ca_certificates: ca_certificates}) do
    %{data: for(ca <- ca_certificates, do: ca_certificate(ca))}
  end

  def show(%{ca_certificate: ca}) do
    %{data: ca_certificate(ca)}
  end

  def ca_certificate(ca_certificate) do
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
