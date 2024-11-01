defmodule NervesHub.Archives do
  @moduledoc """
  Archives are extra fwup files that will be delivered to the device on connect
  """

  import Ecto.Query

  require Logger

  alias NervesHub.Archives.Archive
  alias NervesHub.Fwup
  alias NervesHub.Products.Product
  alias NervesHub.Repo
  alias NervesHub.Workers.DeleteArchive

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

  # TODO: check on other return signatures
  @spec create(Product.t(), String.t()) ::
          {:ok, Archive.t()}
          | {:error, :invalid_signature}
          | {:error, any()}
          | {:error, {any(), :not_found}}
  def create(product, file_path) do
    product = Repo.preload(product, org: [:org_keys])

    with {:ok, org_key} <- validate_signature(product.org, file_path),
         {:ok, metadata} <- Fwup.metadata(file_path),
         {:ok, archive} <-
           product
           |> Ecto.build_assoc(:archives)
           |> Map.put(:org_key_id, org_key.id)
           |> Map.put(:size, :filelib.file_size(file_path))
           |> Archive.create_changeset(metadata)
           |> Repo.insert() do
      NervesHub.Uploads.upload(file_path, archive_path(archive))

      {:ok, archive}
    end
  end

  @spec delete_archive(Archive.t()) :: {:ok, Archive.t()} | {:error, any()}
  def delete_archive(%Archive{} = archive) do
    Repo.transaction(fn ->
      with {:ok, archive} <- Repo.delete(archive),
           {:ok, _} <- delete_artifacts(archive) do
        {:ok, archive}
      else
        {:error, error} -> Repo.rollback(error)
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

  defp archive_path(archive) do
    "/archives/#{archive.uuid}.fw"
  end

  defp validate_signature(org, file_path) do
    signed_key =
      Enum.find(org.org_keys, fn %{key: key} ->
        case System.cmd("fwup", ["--verify", "--public-key", key, "-i", file_path]) do
          {_, 0} ->
            true

          # fwup returns a 1 for invalid signatures
          {_, 1} ->
            false

          {text, code} ->
            Logger.warning("fwup returned code #{code} with #{text}")

            false
        end
      end)

    case signed_key do
      key when is_map(key) ->
        {:ok, key}

      nil ->
        {:error, :invalid_signature}
    end
  end
end
