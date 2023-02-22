alias NervesHubWebCore.Repo
alias NervesHubWebCore.Firmwares.Firmware
alias NervesHubWebCore.Devices.DeviceCertificate
alias NervesHubWebCore.Deployments.Deployment
alias NervesHubWebCore.AuditLogs.AuditLog

import Ecto.Query
import IO.ANSI, only: [default_color: 0, green: 0, red: 0]

Logger.configure(level: :info)

{success, errors} =
  from(f in Firmware, where: is_nil(f.org_id), preload: [:org_key])
  |> Repo.all()
  |> Enum.reduce({[], []}, fn firmware, {success, errors} ->
    Firmware.update_changeset(firmware, %{org_id: firmware.org_key.org_id})
    |> Repo.update()
    |> case do
      {:ok, firmware} ->
        IO.write("#{green()}.#{default_color()}")
        {[firmware | success], errors}
      {:error, firmware} ->
        IO.write("#{red()}.#{default_color()}")
        {success, [firmware | errors]}
    end
  end)

IO.puts "\n"
IO.puts("Firmware Success: #{green()}#{length(success)}#{default_color()}")
IO.puts("Firmware Errors: #{red()}#{length(errors)}#{default_color()}")
IO.puts "\n"

{success, errors} =
  from(dc in DeviceCertificate, where: is_nil(dc.org_id), preload: [:device])
  |> Repo.all()
  |> Enum.reduce({[], []}, fn device_certificate, {success, errors} ->
    DeviceCertificate.changeset(device_certificate, %{org_id: device_certificate.device.org_id})
    |> Repo.update()
    |> case do
      {:ok, device_certificate} ->
        IO.write("#{green()}.#{default_color()}")
        {[device_certificate | success], errors}
      {:error, device_certificate} ->
        IO.write("#{red()}.#{default_color()}")
        {success, [device_certificate | errors]}
    end
  end)

IO.puts "\n"
IO.puts("DeviceCert Success: #{green()}#{length(success)}#{default_color()}")
IO.puts("DeviceCert Errors: #{red()}#{length(errors)}#{default_color()}")
IO.puts "\n"

{success, errors} =
  from(d in Deployment, where: is_nil(d.org_id), preload: [:product])
  |> Repo.all()
  |> Enum.reduce({[], []}, fn deployment, {success, errors} ->
    Deployment.creation_changeset(deployment, %{org_id: deployment.product.org_id})
    |> Repo.update()
    |> case do
      {:ok, deployment} ->
        IO.write("#{green()}.#{default_color()}")
        {[deployment | success], errors}
      {:error, deployment} ->
        IO.write("#{red()}.#{default_color()}")
        {success, [deployment | errors]}
    end
  end)

IO.puts "\n"
IO.puts("Deployment Success: #{green()}#{length(success)}#{default_color()}")
IO.puts("Deployment Errors: #{red()}#{length(errors)}#{default_color()}")
IO.puts "\n"

{success, errors} =
  from(al in AuditLog, where: is_nil(al.org_id))
  |> Repo.all()
  |> Enum.reduce({[], []}, fn audit_log, {success, errors} ->
    case Repo.get(audit_log.resource_type, audit_log.resource_id) do
      nil ->
        {[audit_log | success], errors}
      %{org_id: org_id} ->
        AuditLog.changeset(audit_log, %{org_id: org_id})
      |> Repo.update()
      |> case do
        {:ok, audit_log} ->
          IO.write("#{green()}.#{default_color()}")
          {[audit_log | success], errors}
        {:error, audit_log} ->
          IO.write("#{red()}.#{default_color()}")
          {success, [audit_log | errors]}
      end
    end
  end)

IO.puts "\n"
IO.puts("AuditLog Success: #{green()}#{length(success)}#{default_color()}")
IO.puts("AuditLog Errors: #{red()}#{length(errors)}#{default_color()}")
IO.puts "\n"
