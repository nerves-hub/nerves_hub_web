defmodule BeamwareClientTest do
  use ExUnit.Case
  doctest BeamwareClient

  test "greets the world" do
    assert BeamwareClient.hello() == :world
  end
end
