defmodule NervesHubWebCore.Accounts.CoseKey do
  use Ecto.Type

  def type, do: :binary

  @spec cast(Wax.CoseKey.t()) :: {:ok, Wax.CoseKey.t()}
  def cast(key) when is_map(key) do
    {:ok, key}
  end

  def cast(_), do: :error

  @spec load(binary()) :: {:ok, Wax.CoseKey.t()}
  def load(data) when is_binary(data) do
    {:ok, :erlang.binary_to_term(data)}
  end

  def load(_), do: :error

  @spec dump(Wax.CoseKey.t()) :: {:ok, binary}
  def dump(key) when is_map(key) do
    {:ok, :erlang.term_to_binary(key)}
  end

  def dump(_), do: :error
end
