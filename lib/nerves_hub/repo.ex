defmodule NervesHub.Repo do
  use Ecto.Repo,
    otp_app: :nerves_hub,
    adapter: Ecto.Adapters.Postgres

  import Ecto.Query, only: [where: 3]

  @type transaction ::
          {:ok, any()}
          | {:error, any()}
          | {:error, Ecto.Multi.name(), any(), %{required(Ecto.Multi.name()) => any()}}

  def reload_assoc({:ok, schema}, assoc) do
    schema =
      case Map.get(schema, assoc) do
        %Ecto.Association.NotLoaded{} ->
          schema

        _ ->
          preload(schema, assoc, force: true)
      end

    {:ok, schema}
  end

  def reload_assoc({:error, changeset}, _), do: {:error, changeset}

  def maybe_preload({:ok, entity}, assocs) do
    {:ok, preload(entity, assocs)}
  end

  def maybe_preload({:error, _} = result, _assocs) do
    result
  end

  def soft_delete(struct_or_changeset) do
    struct_or_changeset
    |> soft_delete_changeset()
    |> update()
  end

  def soft_delete_changeset(struct_or_changeset) do
    deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

    Ecto.Changeset.change(struct_or_changeset, deleted_at: deleted_at)
  end

  def exclude_deleted(query) do
    where(query, [o], is_nil(o.deleted_at))
  end

  def destroy(struct_or_changeset), do: delete(struct_or_changeset)

  # verify_fun/3 is used in config/runtime.exs to verify self signed certs
  # that would normally return {:bad_cert, :selfsigned_peer}. This is used
  # in environments where the database uses a self signed cert instead of a
  # proper certificate signed by a separate CA.

  # We don't verify extensions that we don't know about, as that would give :bad_cert.
  # See https://www.erlang.org/doc/apps/ssl/ssl.html#t:common_option_cert/0 for more details.
  def verify_fun(_, {:extension, _}, state) do
    {:unknown, state}
  end

  # This function will in practical terms pin the certificate. If the configured cert in
  # runtime.exs exactly matches the provided cert, then we return {:valid, :ok}.
  # The reason for pinning is that we don't need to validate the chain, as there is
  # no chain here - we just want to validate that the certificate is exactly the same.

  # This function is only used if System.get_env("DATABASE_CERT_SELF_SIGNED") == "true",
  # so in most setups, this function is NOT invoked.

  # We do not validate the cert's date, but for self signed certs, the certificate would
  # be reconfigured in those cases. If the admin doesn't change the cert, we assume it to
  # still be valid.
  def verify_fun(cert, _, state) do
    cert_binary = :public_key.pkix_encode(:OTPCertificate, cert, :otp)

    case state do
      {:der_bin, ^cert_binary} -> {:valid, :ok}
      _ -> {:fail, :cert_no_match}
    end
  end
end
