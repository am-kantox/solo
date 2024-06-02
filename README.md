# Solo    [![Kantox ❤ OSS](https://img.shields.io/badge/❤-kantox_oss-informational.svg)](https://kantox.com/)  ![Test](https://github.com/am-kantox/solo/workflows/Test/badge.svg)  ![Dialyzer](https://github.com/am-kantox/solo/workflows/Dialyzer/badge.svg)

## Objective

This library might be handy when one needs to keep a sigleton across the cluster with zero downtime.
Consider the application needs to collect some data from the external source when the only one 
connection is allowed. If for some reason the node running a connection goes down, the takeover
from other node should have happened. In the old good days we used native _erlang_ 
[failover/takeover](https://www.erlang.org/doc/system/distributed_applications.html#failover)
mechanism for that, but nowadays in the cloud any container might go down unexpectedly due to
some internal considerations of _ECS_.

In such a case the application would need to immediately restart the connection on one of the
nodes still alive. This library transparently makes it possible to turn any number of processes
in the supervision tree into such singletons without writing much code.

Simply wrap the specs into `Solo.global/2` call and you are all set.

```elixir
children = [
Foo,
Solo.global(SoloBarBaz, [
  {Bar, [bar_arg]},
  {Baz, [baz_arg]}
],
...
]
```

## Implementation

The library uses both [`Process.monitor/1`](https://hexdocs.pm/elixir/Process.html#monitor/1)
and [`:pg.monitor/1`](https://www.erlang.org/doc/apps/kernel/pg.html#monitor/1) to get
acknowledged about disappeared processes. Each node carries the state of the monitored cluster
to restart processes on some of the still alive nodes when necessary.

`Solo` is backed by `Supervisor`, unlike e. g. [`Singleton`](https://github.com/arjan/singleton),
which uses `DynamicSupervisor`, allowing for next to zero boilerplate
and resurrection from brutal VM crashes.

## Installation

The package can be installed by adding `solo` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:solo, "~> 0.1"}
  ]
end
```

## FAQ

- **Is it of any good?** — Sure it is.
- **Would it work for me?** — Well, it works on my machine.

## [Documentation](https://hexdocs.pm/solo)

