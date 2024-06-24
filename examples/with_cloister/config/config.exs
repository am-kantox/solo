import Config

config :cloister,
  otp_app: :with_cloister,
  listener: WithCloister,
  consensus: if(Mix.env() == :test, do: 1, else: 2),
  loopback?: Mix.env() == :test,
  sentry: ~w|n1@127.0.0.1 n2@127.0.0.1|a
