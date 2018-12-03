defmodule NervesHubWebCoreTest do
  use ExUnit.Case
  doctest NervesHubWebCore

  test "greets the world" do
    assert NervesHubWebCore.hello() == :world
  end
end
