defmodule SoloTest do
  use ExUnit.Case
  doctest Solo

  setup do
    # {:ok, pid} = Solo.start_link(name: SingletonTest.Supervisor)
    # {:ok, pid: pid}
    :ok
  end

  test "`Solo` singleton itself" do
    assert {:ok, sup} = Solo.start_link([{Counter, [initial: 0, name: Counter]}])

    assert {:error, {:already_started, ^sup}} =
             Solo.start_link([{Counter, [initial: 0, name: Counter]}])

    assert counter_sup_pid = :global.whereis_name(Counter.Sup)
    assert is_pid(counter_sup_pid)
    assert [{Counter, counter_pid, :worker, _}] = Supervisor.which_children(counter_sup_pid)

    assert ^counter_pid = Solo.whereis(Counter)
    assert %{workers: workers} = Solo.state(Solo)
    assert Map.values(workers) == [Counter.Sup]

    assert Process.exit(counter_sup_pid, :kill)
    Process.sleep(500)

    assert counter_pid_2 = Solo.whereis(Counter)
    refute counter_pid == counter_pid_2
    assert %{workers: workers} = Solo.state(Solo)
    assert Map.values(workers) == [Counter.Sup]
  end
end
