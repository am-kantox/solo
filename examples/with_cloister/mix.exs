defmodule WithCloister.MixProject do
  use Mix.Project

  def project do
    [
      app: :with_cloister,
      version: "0.1.0",
      elixir: "~> 1.17",
      prune_code_paths: Mix.env() != :dev,
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {WithCloister, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:cloister, "~> 0.10"},
      {:broadway, "~> 1.0"},
      {:solo, path: "../../../solo"}
    ]
  end
end
