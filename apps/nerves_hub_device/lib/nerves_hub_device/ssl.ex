defmodule NervesHubDevice.SSL do
  alias NervesHubWebCore.{Devices, Devices.CACertificate, Certificate, Accounts}

  @spec verify_fun(X509.Certificate.t(), any(), any()) :: {:valid, any()}
  # The certificate is a valid_peer, which means it has been
  # signed by the NervesHub CA and the signer cert is still valid.
  def verify_fun(_certificate, :valid_peer, state) do
    {:valid, state}
  end

  def verify_fun(_certificate, :valid, state) do
    {:valid, state}
  end

  # The certificate failed peer validation.
  # The next step is to check what kind of cert we are validating
  # If the authority key id and subject key id are the same, its a ca cert.
  # Otherwise, its a device cert.
  def verify_fun(certificate, {:bad_cert, :unknown_ca}, state) do
    aki = Certificate.get_aki(certificate)
    ski = Certificate.get_ski(certificate)

    if aki == ski do
      verify_ca_certificate(certificate, state)
    else
      verify_device_certificate(certificate, state)
    end
  end

  def verify_fun(_certificate, {:extension, _}, state) do
    {:valid, state}
  end

  def verify_ca_certificate(certificate, state) do
    X509.Certificate.serial(certificate)
    |> to_string()
    |> Devices.get_ca_certificate_by_serial()
    |> case do
      {:ok, %CACertificate{der: ca} = ca_cert} ->
        Devices.update_ca_certificate(ca_cert, %{last_used: DateTime.utc_now()})

        path_validation =
          X509.Certificate.to_der(certificate)
          |> :public_key.pkix_path_validation([ca], [])

        case path_validation do
          {:ok, _} -> {:valid, state}
          {:error, {_, reason}} -> {:fail, reason}
        end

      _ ->
        {:fail, :unknown_ca}
    end
  end

  def verify_device_certificate(certificate, state) do
    case Devices.get_device_certificate_by_x509(certificate) do
      {:ok, cert} ->
        # TODO: Remove once enough time has allowed existing DERs to be captured ¬
        Devices.update_device_certificate(cert, %{der: Certificate.to_der(certificate)})
        {:valid, state}

      _ ->
        {:fail, :unknown_ca}
    end
  end

  def verify_device(certificate) do
    case Devices.get_device_certificate_by_x509(certificate) do
      {:ok, cert} ->
        # TODO: Remove once enough time has allowed existing DERs to be captured ¬
        Devices.update_device_certificate(cert, %{
          last_used: DateTime.utc_now(),
          der: Certificate.to_der(certificate)
        })

      _ ->
        with aki <- Certificate.get_aki(certificate),
             {:ok, %CACertificate{org_id: org_id}} <- Devices.get_ca_certificate_by_ski(aki),
             {:ok, org} <- Accounts.get_org(org_id),
             identifier <- Certificate.get_common_name(certificate),
             {:ok, device} <- Devices.get_device_by_identifier(org, identifier) do
          attempt_registration(device, certificate)
        else
          _e -> :error
        end
    end
  end

  defp attempt_registration(device, certificate) do
    with [] <- Devices.get_device_certificates(device),
         serial <- Certificate.get_serial_number(certificate),
         aki <- Certificate.get_aki(certificate),
         ski <- Certificate.get_ski(certificate),
         der <- Certificate.to_der(certificate),
         {not_before, not_after} <- Certificate.get_validity(certificate),
         params <- %{
           serial: serial,
           aki: aki,
           ski: ski,
           not_before: not_before,
           not_after: not_after,
           der: der
         },
         {:ok, db_cert} <- Devices.create_device_certificate(device, params) do
      {:ok, db_cert}
    else
      _e -> :error
    end
  end
end
