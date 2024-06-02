defmodule SoloTestTest do
  use ExUnit.Case
  doctest SoloTest

  test "starts `Srv2` and `Srv3` under `Solo` supervision" do
    assert {:ok, _solo} = SoloTest.start_link()
    children = Supervisor.which_children(SoloTest)

    assert is_list(children) and length(children) == 3
    assert Enum.find(children, &match?({Srv1, _, _, _}, &1))
    assert Enum.find(children, &match?({Srv4, _, _, _}, &1))
    assert Enum.find(children, &match?({{Solo, SoloSrv}, _, _, _}, &1))

    assert %{name: SoloSrv, workers: workers} = Solo.state(SoloSrv)
    assert [Srv2, Srv3] == workers |> Map.values() |> Enum.sort()

    Process.exit(workers |> Map.keys() |> hd(), :kill)

    assert %{name: SoloSrv, workers: workers} = Solo.state(SoloSrv)
    assert [Srv2, Srv3] == workers |> Map.values() |> Enum.sort()
  end
end
