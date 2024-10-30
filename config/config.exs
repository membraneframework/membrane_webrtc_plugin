import Config
IO.puts("RUN CONFIG")
config :membrane_opentelemetry, enabled: true
config :membrane_opentelemetry_plugs, plugs: [:launch]
