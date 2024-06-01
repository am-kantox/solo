defmodule SoloTest do
  use ExUnit.Case
  doctest Solo

  test "greets the world" do
    assert Solo.hello() == :world
  end
end
