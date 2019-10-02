defmodule NervesHubWebCore.Types do
  defmodule Tag do
    @behaviour Ecto.Type

    def type, do: {:array, :string}

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

    def type, do: :string

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

    defp allowed_resources do
      {:ok, modules} = :application.get_key(:nerves_hub_web_core, :modules)

      for module <- modules,
          Keyword.has_key?(module.__info__(:functions), :__schema__),
          do: to_string(module)
    end
  end
end
