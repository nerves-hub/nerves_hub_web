defmodule NervesHub.FuseStats do
  def init(name) do
    :telemetry.execute([:nerves_hub, :fuse, :init], %{count: 1}, %{fuse: name})
  end

  def increment(name, counter) do
    :telemetry.execute([:nerves_hub, :fuse, :increment], %{count: 1}, %{
      counter: counter,
      fuse: name
    })
  end
end
