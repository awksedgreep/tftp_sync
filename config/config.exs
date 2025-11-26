import Config

# Shared, environment-agnostic configuration for tftp_sync.
#
# Environment-specific values (like source_dir and api_url) live in
# config/dev.exs and config/prod.exs.

# Import environment-specific config at the end
import_config "#{config_env()}.exs"
