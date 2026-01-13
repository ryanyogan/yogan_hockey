import Config

# Load environment variables from .env file (if it exists)
if config_env() in [:dev, :test] do
  Dotenvy.source!([".env", ".env.#{config_env()}", ".env.#{config_env()}.local"])
  |> Enum.each(fn {key, value} -> System.put_env(key, value) end)
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/yogan_hockey start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :yogan_hockey, YoganHockeyWeb.Endpoint, server: true
end

# Anthropic API key for AI predictions
if api_key = System.get_env("ANTHROPIC_API_KEY") do
  config :yogan_hockey, :anthropic_api_key, api_key
end

if config_env() == :prod do
  # Configure libcluster for Fly.io distributed clustering
  # Uses DNSPoll strategy to discover nodes via Fly's internal DNS
  app_name = System.get_env("FLY_APP_NAME")

  if app_name do
    config :libcluster,
      topologies: [
        fly6pn: [
          strategy: Cluster.Strategy.DNSPoll,
          config: [
            polling_interval: 5_000,
            query: "#{app_name}.internal",
            node_basename: app_name
          ]
        ]
      ]
  end

  # Configure SQLite database for production
  # Only the primary region (ord) has the SQLite volume mounted
  # Replica regions use RPC to forward database operations to primary
  primary_region = System.get_env("PRIMARY_REGION", "ord")
  current_region = System.get_env("FLY_REGION")

  if current_region == primary_region do
    # Primary region - use real SQLite database
    database_path =
      System.get_env("DATABASE_PATH") ||
        raise """
        environment variable DATABASE_PATH is missing.
        For Fly.io primary region, set this to /mnt/data/yogan_hockey.db
        """

    config :yogan_hockey, YoganHockey.Repo,
      database: database_path,
      pool_size: 5
  else
    # Replica regions - Repo won't be started (see application.ex)
    # All database operations are forwarded to primary via RPC
    # This config is just a fallback in case Repo is accessed directly
    config :yogan_hockey, YoganHockey.Repo,
      database: ":memory:",
      pool_size: 1
  end

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :yogan_hockey, YoganHockeyWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    # Use :conn to trust Fly.io's x-forwarded-host header for WebSocket origin checks
    # This is the recommended approach for Fly.io deployments
    check_origin: :conn

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :yogan_hockey, YoganHockeyWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :yogan_hockey, YoganHockeyWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :yogan_hockey, YoganHockey.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
