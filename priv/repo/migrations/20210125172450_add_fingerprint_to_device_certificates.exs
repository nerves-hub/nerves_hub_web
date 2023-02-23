defmodule NervesHub.Repo.Migrations.AddFingerprintToDeviceCertificates do
  use Ecto.Migration

  alias NervesHub.{Certificate, Devices.DeviceCertificate}

  import Ecto.Query, only: [from: 2]
  import Ecto.Changeset, only: [put_change: 3]

  def change do
    alter table(:device_certificates) do
      add :fingerprint, :string
      add :public_key_fingerprint, :string
    end

    create unique_index :device_certificates, :fingerprint
    create index :device_certificates, :public_key_fingerprint

    execute(&execute_up/0, &execute_down/0)
  end

  defp execute_up() do
    from(c in DeviceCertificate, where: not is_nil(c.der))
    |> repo().all()
    |> Enum.each(&add_fingerprints/1)
  end

  defp execute_down(), do: :ok

  defp add_fingerprints(db_cert) do
    otp_cert = X509.Certificate.from_der!(db_cert.der)

    DeviceCertificate.update_changeset(db_cert, %{})
    |> put_change(:fingerprint, Certificate.fingerprint(otp_cert))
    |> put_change(:public_key_fingerprint, Certificate.public_key_fingerprint(otp_cert))
    |> repo().update()
  end
end
