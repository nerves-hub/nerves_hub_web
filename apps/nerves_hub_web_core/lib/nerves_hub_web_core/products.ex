defmodule NervesHubWebCore.Products do
  @moduledoc """
  The Products context.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias NervesHubWebCore.{Certificate, Repo}
  alias NervesHubWebCore.Products.{Product, ProductUser}
  alias NervesHubWebCore.Accounts.{User, Org, OrgUser}

  alias NimbleCSV.RFC4180, as: CSV

  @csv_certs_sep "\n\n"
  @csv_header ["identifier", "description", "tags", "product", "org", "certificates"]

  def __csv_header__, do: @csv_header

  def get_products_by_user_and_org(%User{id: user_id}, %Org{id: org_id}) do
    query =
      from(
        p in Product,
        join: pu in ProductUser,
        on: p.id == pu.product_id,
        full_join: ou in OrgUser,
        on: p.org_id == ou.org_id,
        where:
          p.org_id == ^org_id and
            ((ou.user_id == ^user_id and ou.role in ^User.role_or_higher(:read)) or
               (pu.user_id == ^user_id and pu.role in ^User.role_or_higher(:read))),
        group_by: p.id
      )

    query
    |> Repo.exclude_deleted()
    |> Repo.all()
  end

  @doc """
  Gets a single product.

  Raises `Ecto.NoResultsError` if the Product does not exist.

  ## Examples

      iex> get_product!(123)
      %Product{}

      iex> get_product!(456)
      ** (Ecto.NoResultsError)

  """
  def get_product!(id) do
    Product
    |> Repo.exclude_deleted()
    |> Repo.get!(id)
  end

  def get_product_by_org_id_and_name(org_id, name) do
    Product
    |> Repo.exclude_deleted()
    |> Repo.get_by(org_id: org_id, name: name)
    |> case do
      nil -> {:error, :not_found}
      product -> {:ok, product}
    end
  end

  @doc """
  Creates a product.

  ## Examples

      iex> create_product(user, %{field: value})
      {:ok, %Product{}}

      iex> create_product(user, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_product(user, params \\ %{}) do
    multi =
      Multi.new()
      |> Multi.insert(:product, Product.changeset(%Product{}, params))
      |> Multi.insert(:product_user, fn %{product: product} ->
        product_user = %ProductUser{
          product_id: product.id,
          user_id: user.id,
          role: :admin
        }

        Product.add_user(product_user, %{})
      end)

    case Repo.transaction(multi) do
      {:ok, result} ->
        {:ok, result.product}

      {:error, :product, changeset, _} ->
        {:error, changeset}
    end
  end

  def add_product_user(%Product{} = product, %User{} = user, params) do
    product_user = %ProductUser{product_id: product.id, user_id: user.id}

    multi =
      Multi.new()
      |> Multi.insert(:product_user, Product.add_user(product_user, params))

    case Repo.transaction(multi) do
      {:ok, result} ->
        {:ok, Repo.preload(result.product_user, :user)}

      {:error, :product_user, changeset, _} ->
        {:error, changeset}
    end
  end

  def remove_product_user(%Product{} = product, %User{} = user) do
    count = Repo.aggregate(Ecto.assoc(product, :product_users), :count, :id)

    if count == 1 do
      {:error, :last_user}
    else
      product_user = Repo.get_by(Ecto.assoc(product, :product_users), user_id: user.id)

      if product_user do
        {:ok, _result} =
          Multi.new()
          |> Multi.delete(:product_user, product_user)
          |> Repo.transaction()
      end

      :ok
    end
  end

  def change_product_user_role(%ProductUser{} = pu, role) do
    pu
    |> Product.change_user_role(%{role: role})
    |> Repo.update()
  end

  def get_product_user(product, user) do
    from(
      pu in ProductUser,
      where:
        pu.product_id == ^product.id and
          pu.user_id == ^user.id
    )
    |> ProductUser.with_user()
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      product_user -> {:ok, product_user}
    end
  end

  def get_product_users(product) do
    from(
      pu in ProductUser,
      where: pu.product_id == ^product.id,
      order_by: [desc: pu.role],
      preload: :user
    )
    |> ProductUser.with_user()
    |> Repo.all()
  end

  def has_product_role?(product, user, role) do
    from(
      pu in ProductUser,
      where: pu.product_id == ^product.id,
      where: pu.user_id == ^user.id,
      where: pu.role in ^User.role_or_higher(role),
      select: count(pu.id) >= 1
    )
    |> Repo.one()
  end

  @doc """
  Updates a product.

  ## Examples

      iex> update_product(product, %{field: new_value})
      {:ok, %Product{}}

      iex> update_product(product, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_product(%Product{} = product, attrs) do
    product
    |> Product.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a Product.

  ## Examples

      iex> delete_product(product)
      {:ok, %Product{}}

      iex> delete_product(product)
      {:error, %Ecto.Changeset{}}

  """
  def delete_product(%Product{} = product) do
    product
    |> Product.delete_changeset()
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking product changes.

  ## Examples

      iex> change_product(product)
      %Ecto.Changeset{source: %Product{}}

  """
  def change_product(%Product{} = product) do
    Product.changeset(product, %{})
  end

  def devices_csv(%Product{} = product) do
    product = Repo.preload(product, [:org, devices: :device_certificates])
    data = Enum.map(product.devices, &device_csv_line(&1, product))

    [@csv_header | data]
    |> CSV.dump_to_iodata()
    |> IO.iodata_to_binary()
  end

  def parse_csv_line(line) do
    parsed =
      for {k_str, v} <- Enum.zip(@csv_header, line),
          key = String.to_existing_atom(k_str),
          into: %{} do
        val = if key == :certificates, do: parse_csv_device_certs(v), else: v
        {key, val}
      end

    if length(line) == length(@csv_header) do
      parsed
    else
      {:malformed, line, parsed}
    end
  end

  defp parse_csv_device_certs(certs_str) do
    for str <- String.split(certs_str, ~r/#{@csv_certs_sep}|\r\n\r\n/, trim: true) do
      parse_cert_type(str)
    end
  end

  defp parse_cert_type("{" <> _ = str) do
    case Jason.decode(str) do
      {:ok, attrs} ->
        for {k, v} <- attrs, key = String.to_existing_atom(k), into: %{} do
          val = if key in [:ski, :aki], do: decode(v), else: v
          {key, val}
        end

      _ ->
        :malformed_json
    end
  end

  defp parse_cert_type(str) do
    case Certificate.from_pem(str) do
      {:ok, otp_cert} ->
        {nb, na} = Certificate.get_validity(otp_cert)

        %{
          serial: Certificate.get_serial_number(otp_cert),
          aki: Certificate.get_aki(otp_cert),
          ski: Certificate.get_ski(otp_cert),
          not_before: nb,
          not_after: na,
          der: Certificate.to_der(otp_cert)
        }

      _ ->
        :malformed_pem
    end
  end

  defp device_csv_line(device, product) do
    [
      device.identifier,
      device.description,
      "#{Enum.join(device.tags || [], ",")}",
      product.name,
      product.org.name,
      format_device_certificates(device)
    ]
  end

  defp format_device_certificates(device) do
    for db_cert <- device.device_certificates, into: "" do
      if db_cert.der do
        db_cert.der
        |> X509.Certificate.from_der!()
        |> X509.Certificate.to_pem()
      else
        %{
          serial: db_cert.serial,
          aki: Base.encode16(db_cert.aki),
          ski: if(db_cert.ski, do: Base.encode16(db_cert.ski)),
          not_before: db_cert.not_before,
          not_after: db_cert.not_after
        }
        |> Jason.encode!()
        |> Kernel.<>(@csv_certs_sep)
      end
    end
  end

  defp decode(val) when is_binary(val), do: Base.decode16!(val)
  defp decode(val), do: val
end
