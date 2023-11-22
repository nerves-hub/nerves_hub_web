defmodule NervesHub.Config.DeviceEndpoint do
  @moduledoc """
  Configuration for NervesHub.DeviceEndpoint.

  Older versions of OTP 25 may break using using devices that support TLS
  1.3 or 1.2 negotiation. To mitigate that potential error, we enforce TLS
  1.2. If you're using OTP >= 25.1 on all devices, then it is safe to
  allow TLS 1.3 by removing the versions constraint and setting
  `certificate_authorities: false`.

  See https://github.com/erlang/otp/issues/6492#issuecomment-1323874205
  """

  use Vapor.Planner

  dotenv()

  config :endpoint,
         env([
           {:https_port, "DEVICE_ENDPOINT_HTTPS_PORT", map: &String.to_integer/1},
           {:https_keyfile, "DEVICE_ENDPOINT_HTTPS_KEYFILE"},
           {:https_certfile, "DEVICE_ENDPOINT_HTTPS_CERTFILE"},
           {:https_cacertfile, "DEVICE_ENDPOINT_HTTPS_CACERTFILE", required: false},
           {:https_verify, "DEVICE_ENDPOINT_HTTPS_VERIFY",
            default: :verify_peer, map: &String.to_atom/1},
           {:https_fail_if_no_peer_cert, "DEVICE_ENDPOINT_HTTPS_FAIL_IF_NO_PEER_CERT",
            default: true, map: &to_boolean/1},
           {:https_certificate_authorities, "DEVICE_ENDPOINT_HTTPS_CERTIFICATE_AUTHORITIES",
            default: true, map: &to_boolean/1},
           {:https_versions, "DEVICE_ENDPOINT_HTTPS_VERSIONS",
            map: fn vsns ->
              vsns
              |> String.split(",")
              |> Enum.reject(fn v -> v == "" end)
              |> Enum.map(&String.to_atom/1)
            end,
            required: false},
           {:url_host, "DEVICE_ENDPOINT_URL_HOST"},
           {:url_port, "DEVICE_ENDPOINT_URL_PORT", default: 443, map: &String.to_integer/1}
         ])

  def to_boolean("true"), do: true
  def to_boolean(_), do: false

  def load! do
    %{endpoint: vapor} = Vapor.load!(__MODULE__)

    https =
      vapor
      |> build_https_common()
      |> put_cacertfile(vapor.https_cacertfile)
      |> put_versions(vapor.https_versions)

    [
      server: true,
      http: false,
      https: https,
      url: [
        host: vapor.url_host,
        port: vapor.url_port,
        scheme: "https"
      ]
    ]
  end

  defp build_https_common(vapor) do
    [
      port: vapor.https_port,
      keyfile: vapor.https_keyfile,
      certfile: vapor.https_certfile,
      verify: vapor.https_verify,
      fail_if_no_peer_cert: vapor.https_fail_if_no_peer_cert,
      certificate_authorities: vapor.https_certificate_authorities
    ]
  end

  defp put_cacertfile(vapor, nil), do: vapor
  defp put_cacertfile(vapor, cacertfile), do: Keyword.put(vapor, :cacertfile, cacertfile)

  defp put_versions(vapor, nil), do: vapor
  defp put_versions(vapor, []), do: vapor
  defp put_versions(vapor, versions), do: Keyword.put(vapor, :versions, versions)
end
