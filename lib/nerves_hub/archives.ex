defmodule NervesHub.Archives do
  @moduledoc """
  Archives are extra fwup files that will be delivered to the device on connect

  ## Where the files are stored

  An archive's file is stored at `/archives/<org id>/<product id>/<uuid>.fw`,
  and the archive keeps that path as its `storage_key`. The UUID comes from the
  uploaded file, so whoever builds an archive chooses it. Only the org and
  product in the path keep one org's archive from landing on another's.

  Archives uploaded before that have no `storage_key`. Their files stay at
  `/archives/<uuid>.fw`, where they were uploaded, and are served and deleted
  from there. Two of these with the same UUID share one file. Nothing new is
  ever written to that path.

  A file is only deleted once no archive uses its path, which also covers an
  archive deleted and uploaded again before its old file was removed.
  """

  import Ecto.Query

  alias NervesHub.Archives.Archive
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.UpdateTool
  alias NervesHub.Fwup
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias NervesHub.Workers.DeleteArchive

  @spec get_by_id(Product.t(), pos_integer()) :: Archive.t() | nil
  def get_by_id(_product, archive_id) when archive_id in [nil, ""], do: nil

  def get_by_id(%Product{} = product, archive_id) do
    Archive
    |> where([f], f.product_id == ^product.id)
    |> where([f], f.id == ^archive_id)
    |> Repo.one()
  end

  @spec filter(Product.t(), map()) :: {[Archive.t()], Flop.Meta.t()}
  def filter(product, opts \\ %{}) do
    opts = Map.reject(opts, fn {_key, val} -> is_nil(val) end)

    sort = Map.get(opts, :sort, "inserted_at")
    sort_direction = Map.get(opts, :sort_direction, "desc")

    sort_opts = {String.to_existing_atom(sort_direction), String.to_existing_atom(sort)}

    flop = %Flop{
      page: String.to_integer(Map.get(opts, :page, "1")),
      page_size: String.to_integer(Map.get(opts, :page_size, "25"))
    }

    Archive
    |> where([f], f.product_id == ^product.id)
    |> order_by(^sort_opts)
    |> Flop.run(flop)
  end

  @spec all_by_product(Product.t()) :: [Archive.t()]
  def all_by_product(product) do
    Archive
    |> where([a], a.product_id == ^product.id)
    |> Repo.all()
  end

  @spec get(Product.t(), String.t()) :: {:ok, Archive.t()} | {:error, :not_found}
  def get(product, uuid) when is_binary(uuid) do
    Archive
    |> where([a], a.uuid == ^uuid)
    |> where([a], a.product_id == ^product.id)
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      archive ->
        {:ok, Repo.preload(archive, product: [:org])}
    end
  end

  @spec get_by_product_and_uuid!(Product.t(), String.t()) :: Archive.t()
  def get_by_product_and_uuid!(product, uuid) do
    Archive
    |> where(uuid: ^uuid)
    |> where(product_id: ^product.id)
    |> join(:inner, [a], p in assoc(a, :product))
    |> join(:inner, [a, p], o in assoc(p, :org))
    |> preload([a, p, o], product: {p, org: o})
    |> Repo.one!()
  end

  @doc """
  The archive a device should have from its deployment group, if any.

  An archive belongs to the release it was added to, so only a device already
  running the current release's firmware is sent one. A device working its way
  through a required release gets it on the connection after it lands on the
  current release.
  """
  @spec archive_for_deployment_group(integer() | nil, String.t() | nil) :: Archive.t() | nil
  def archive_for_deployment_group(deployment_id, firmware_uuid)

  def archive_for_deployment_group(nil, _firmware_uuid), do: nil

  def archive_for_deployment_group(_deployment_id, nil), do: nil

  def archive_for_deployment_group(deployment_id, firmware_uuid) do
    Archive
    |> join(:inner, [a], dr in DeploymentRelease, on: dr.archive_id == a.id)
    |> join(:inner, [a, dr], dg in DeploymentGroup, on: dr.id == dg.current_deployment_release_id)
    |> join(:inner, [a, dr], f in Firmware, on: f.id == dr.firmware_id)
    |> where([a, _dr, dg], dg.id == ^deployment_id)
    |> where([a, _dr, _dg, f], f.uuid == ^firmware_uuid)
    |> Repo.one()
  end

  # TODO: check on other return signatures
  @spec create(Product.t(), String.t()) ::
          {:ok, Archive.t()}
          | {:error, :invalid_signature}
          | {:error, :no_public_keys}
          | {:error, {:fwup_too_old, required :: String.t(), installed :: String.t()}}
          | {:error, any()}
          | {:error, {any(), :not_found}}
  def create(product, file_path) do
    product = Repo.preload(product, org: [:org_keys])

    with {:ok, org_key} <- UpdateTool.Fwup.verify_signature(file_path, product.org.org_keys),
         {:ok, metadata} <- Fwup.metadata(file_path),
         {:ok, archive} <-
           product
           |> Ecto.build_assoc(:archives)
           |> Map.put(:org_key_id, org_key.id)
           |> Map.put(:size, :filelib.file_size(file_path))
           |> Archive.create_changeset(metadata)
           |> put_storage_key(product)
           |> Repo.insert() do
      NervesHub.Uploads.upload(file_path, archive_path(archive))

      {:ok, archive}
    end
  end

  @spec delete_archive(Archive.t()) :: {:ok, Archive.t()} | {:error, any()}
  def delete_archive(%Archive{} = archive) do
    Repo.transact(fn ->
      with {:ok, archive} <- Repo.delete(Archive.delete_changeset(archive)),
           {:ok, _} <- delete_artifacts(archive) do
        {:ok, archive}
      end
    end)
  end

  defp delete_artifacts(archive) do
    %{archive_path: archive_path(archive)}
    |> DeleteArchive.new()
    |> Oban.insert()
  end

  @spec url(Archive.t()) :: String.t()
  def url(archive) do
    NervesHub.Uploads.url(archive_path(archive), signed: [expires_in: 3600])
  end

  @doc """
  Whether any archive's file is stored at `path`, so deleting it would take the
  file from under that archive.

  Asked when the file is about to be deleted, rather than when its archive was,
  so an archive uploaded again in between keeps its file.
  """
  @spec file_in_use?(String.t()) :: boolean()
  def file_in_use?(path) when is_binary(path) do
    query = where(Archive, [a], a.storage_key == ^path)

    query =
      case legacy_uuid(path) do
        {:ok, uuid} -> or_where(query, [a], is_nil(a.storage_key) and a.uuid == ^uuid)
        :error -> query
      end

    Repo.exists?(query)
  end

  defp put_storage_key(changeset, product) do
    case Ecto.Changeset.get_field(changeset, :uuid) do
      nil -> changeset
      uuid -> Ecto.Changeset.put_change(changeset, :storage_key, "/archives/#{product.org_id}/#{product.id}/#{uuid}.fw")
    end
  end

  defp archive_path(%Archive{storage_key: nil, uuid: uuid}), do: legacy_path(uuid)
  defp archive_path(%Archive{storage_key: storage_key}), do: storage_key

  defp legacy_path(uuid), do: "/archives/#{uuid}.fw"

  defp legacy_uuid("/archives/" <> name) do
    if String.ends_with?(name, ".fw") do
      name |> String.trim_trailing(".fw") |> Ecto.UUID.cast()
    else
      :error
    end
  end

  defp legacy_uuid(_path), do: :error
end
