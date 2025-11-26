import Config

# Development defaults for tftp_sync
#
# - Source directory: priv/fixtures inside the project
# - API URL: local DDNet dev instance

config :tftp_sync,
  source_dir: Path.expand("priv/fixtures", File.cwd!()),
  api_url: "http://localhost:4000"
