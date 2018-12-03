defmodule NervesHubWWW.Application do
  use Application

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec

    # Start the hackney pool for connections to NervesHubCA
    NervesHubWebCore.CertificateAuthority.start_pool()

    # Define workers and child supervisors to be supervised
    children = [
      # Start the endpoint when the application starts
      supervisor(NervesHubWWWWeb.Endpoint, [])
      # Start your own worker by calling: NervesHubWWW.Worker.start_link(arg1, arg2, arg3)
      # worker(NervesHubWWW.Worker, [arg1, arg2, arg3]),
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: NervesHubWWW.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    NervesHubWWWWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
