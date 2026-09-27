defmodule NervesHub.Types do
  defmodule Tag do
    @behaviour Ecto.Type

    def type(), do: {:array, :string}

    def embed_as(_), do: :self

    def equal?(term1, term2), do: term1 == term2

    def cast(tags) when is_bitstring(tags) do
      tags
      |> String.split(",", trim: true)
      |> Stream.map(&String.trim/1)
      |> Enum.reject(&(byte_size(&1) == 0))
      |> cast()
    end

    def cast(tags) when is_list(tags) do
      if Enum.any?(tags, &(32 in to_charlist(&1))) do
        {:error, message: "tags cannot contain spaces"}
      else
        Ecto.Type.cast(type(), tags)
      end
    end

    def cast(_tag), do: :error

    def load(tags), do: Ecto.Type.load(type(), tags)
    def dump(tags), do: Ecto.Type.dump(type(), tags)
  end

  defmodule Resource do
    @behaviour Ecto.Type

    def type(), do: :string

    def embed_as(_), do: :self

    def equal?(term1, term2), do: term1 == term2

    def cast(resource) when is_atom(resource) do
      resource
      |> to_string()
      |> cast()
    end

    def cast(resource) when is_bitstring(resource) do
      if resource in allowed_resources() do
        {:ok, String.to_existing_atom(resource)}
      else
        :error
      end
    end

    def cast(_resource), do: :error

    def dump(resource) when is_atom(resource), do: dump(to_string(resource))

    def dump(resource) when is_bitstring(resource) do
      if resource in allowed_resources() do
        {:ok, resource}
      else
        :error
      end
    end

    def dump(_resource), do: :error

    def load(resource), do: {:ok, String.to_existing_atom(resource)}

    defp allowed_resources() do
      [
        "Elixir.NervesHub.Accounts.Org",
        "Elixir.NervesHub.Accounts.User",
        "Elixir.NervesHub.ManagedDeployments.DeploymentGroup",
        "Elixir.NervesHub.Devices.Device",
        "Elixir.NervesHub.Firmwares.Firmware",
        "Elixir.NervesHub.Products.Product"
      ]
    end
  end

  defmodule KnownAtoms do
    @moduledoc """
    A list of atoms drawn from the `:values` option, stored as strings.

    Casting is as strict as `{:array, Ecto.Enum}`: any value not in `:values`
    makes the cast fail. Loading is lenient: a stored value that is no longer
    in `:values` is skipped instead of failing the load. Removing a value
    therefore can't stop a record from loading. The stale string stays in the
    database until the field is next written.
    """
    use Ecto.ParameterizedType

    @impl Ecto.ParameterizedType
    def init(opts) do
      values = Keyword.fetch!(opts, :values)
      %{known: Map.new(values, &{Atom.to_string(&1), &1})}
    end

    @impl Ecto.ParameterizedType
    def type(_params), do: {:array, :string}

    @impl Ecto.ParameterizedType
    def cast(nil, _params), do: {:ok, nil}

    def cast(values, %{known: known}) when is_list(values) do
      atoms = Enum.map(values, &known_atom(&1, known))
      if Enum.all?(atoms), do: {:ok, atoms}, else: :error
    end

    def cast(_values, _params), do: :error

    @impl Ecto.ParameterizedType
    def load(nil, _loader, _params), do: {:ok, nil}

    def load(values, _loader, %{known: known}) when is_list(values) do
      {:ok, values |> Enum.map(&known_atom(&1, known)) |> Enum.reject(&is_nil/1)}
    end

    def load(_values, _loader, _params), do: :error

    @impl Ecto.ParameterizedType
    def dump(nil, _dumper, _params), do: {:ok, nil}

    def dump(values, _dumper, params) do
      with {:ok, atoms} <- cast(values, params), do: {:ok, Enum.map(atoms, &Atom.to_string/1)}
    end

    # `:dump` rather than `:self`, so values read from an embed go through
    # `load/3`. With `:self`, Ecto casts them instead, which fails on a stale
    # value just as `Ecto.Enum` does.
    @impl Ecto.ParameterizedType
    def embed_as(_format, _params), do: :dump

    @impl Ecto.ParameterizedType
    def equal?(term1, term2, _params), do: term1 == term2

    defp known_atom(value, known) when is_atom(value) or is_binary(value), do: known[to_string(value)]
    defp known_atom(_value, _known), do: nil
  end
end
