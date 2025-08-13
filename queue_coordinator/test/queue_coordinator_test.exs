defmodule QueueCoordinatorTest do
  use ExUnit.Case
  doctest QueueCoordinator

  test "greets the world" do
    assert QueueCoordinator.hello() == :world
  end
end
