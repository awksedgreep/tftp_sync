defmodule TftpSync.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    base_children = [
      {Finch,
       name: TftpSync.Finch,
       pools: %{
         :default => [
           size: 10,
           count: 1,
           conn_opts: [transport_opts: [timeout: 30_000]]
         ]
       }}
    ]

    children =
      case Mix.env() do
        :test -> base_children
        _env -> base_children ++ [TftpSync.Watcher]
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TftpSync.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
