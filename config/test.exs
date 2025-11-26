import Config

# Test defaults for tftp_sync
#
# Tests assume a DDNet dev instance is reachable. By default we point to
# localhost; override in the test environment if needed.

config :tftp_sync,
  source_dir: Path.expand("priv/fixtures", File.cwd!()),
  api_url: System.get_env("TFTP_SYNC_TEST_API_URL", "http://127.0.0.1:4000")
