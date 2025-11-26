import Config

# Production defaults for tftp_sync
#
# These can be adjusted at build/deploy time for your environment.

config :tftp_sync,
  source_dir: "/srv/tftp",
  api_url: "http://192.168.160.220:4000"

# Optional safety and test knobs (defaults are false in code):
#
# no_delete_remote: true  # uncomment to DISABLE remote deletions (default: false)
# dry_run: true           # uncomment to enable dry-run only (default: false)
