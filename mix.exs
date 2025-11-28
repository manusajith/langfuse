defmodule Langfuse.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/manusajith/langfuse"

  def project do
    [
      app: :langfuse,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      docs: docs(),
      name: "Langfuse",
      description:
        "Community Elixir SDK for Langfuse - LLM observability, tracing, and prompt management",
      source_url: @source_url,
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Langfuse.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},
      {:opentelemetry_api, "~> 1.4", optional: true},
      {:opentelemetry, "~> 1.5", optional: true},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.1", only: :test},
      {:bypass, "~> 2.1", only: :test}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      maintainers: ["Manu Ajith"],
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}",
      source_url: @source_url,
      groups_for_modules: [
        Tracing: [
          Langfuse,
          Langfuse.Trace,
          Langfuse.Span,
          Langfuse.Generation,
          Langfuse.Event,
          Langfuse.Instrumentation
        ],
        Evaluation: [
          Langfuse.Score,
          Langfuse.Session
        ],
        Prompts: [
          Langfuse.Prompt
        ],
        "API Client": [
          Langfuse.Client
        ],
        Integrations: [
          Langfuse.OpenTelemetry,
          Langfuse.OpenTelemetry.SpanProcessor,
          Langfuse.OpenTelemetry.AttributeMapper,
          Langfuse.OpenTelemetry.TraceContext,
          Langfuse.OpenTelemetry.Setup
        ],
        Infrastructure: [
          Langfuse.Config,
          Langfuse.Ingestion,
          Langfuse.HTTP,
          Langfuse.Telemetry,
          Langfuse.Masking,
          Langfuse.Error
        ]
      ]
    ]
  end
end
