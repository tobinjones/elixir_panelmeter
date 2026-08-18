defmodule Admx3652Docs.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :admx3652_docs,
      version: @version,
      elixir: "~> 1.20",
      deps: deps(),
      docs: docs()
    ]
  end

  def application, do: []

  defp deps do
    [
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "introduction",
      title: "ADMX3652 Documentation",
      extra_section: "Manual",
      extras: [
        "pages/admx3652/introduction.md",
        "pages/admx3652/installation.md",
        "pages/admx3652/getting-started.md",
        "pages/admx3652/measurements.md",
        "pages/admx3652/triggering.md",
        "pages/admx3652/serial-interface.md",
        "pages/admx3652/command-reference.md",
        "pages/admx3652/responses-and-errors.md",
        "pages/admx3652/specifications.md",
        "pages/admx3652/startup-and-reset.md",
        "pages/admx3652/calibration.md",
        "pages/admx3652/mechanical.md"
      ],
      groups_for_extras: [
        "ADMX3652 Reference Manual": ~r"pages/admx3652/"
      ]
    ]
  end
end
