defmodule SeethroughPythonxTest do
  use ExUnit.Case
  doctest SeethroughPythonx

  test "greets the world" do
    assert SeethroughPythonx.hello() == :world
  end
end
