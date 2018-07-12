defmodule NervesHubCoreTest do
  use ExUnit.Case
  doctest NervesHubCore

  test "greets the world" do
    assert NervesHubCore.hello() == :world
  end
end
