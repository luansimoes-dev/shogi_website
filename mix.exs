defmodule Shogi.MixProject do
  use Mix.Project

  def project do
    [
      app: :shogi_com,
      version: "0.1.0",
      elixir: ">= 1.14.0",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Shogi.Application, []},
      extra_applications: [:logger, :runtime_tools, :crypto]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Phoenix
      {:phoenix, "~> 1.7.0"},
      {:phoenix_live_view, "~> 0.20"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:phoenix_html, "~> 4.0"},

      # PubSub e Telemetry
      {:phoenix_pubsub, "~> 2.1"},
      # Bom ter para o Dashboard
      {:telemetry_metrics, "~> 1.0"},
      # Bom ter para o Dashboard
      {:telemetry_poller, "~> 1.0"},

      # Banco de dados
      {:ecto_sql, "~> 3.10"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_ecto, "~> 4.4"},

      # JSON
      {:jason, "~> 1.4"},

      # Servidor HTTP moderno (Substituiu o plug_cowboy)
      {:bandit, "~> 1.2"},

      # Assets
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},

      # Dev/Test
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:floki, ">= 0.30.0", only: :test},
      {:ex_machina, "~> 2.7", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      # Certifique-se de usar "default" se não tiver alterado no config.exs
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind default", "esbuild default"],
      "assets.deploy": ["tailwind default --minify", "esbuild default --minify", "phx.digest"]
    ]
  end
end
