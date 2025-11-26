defmodule TftpSyncTest do
  use ExUnit.Case

  test "application starts" do
    assert {:ok, _started} = Application.ensure_all_started(:tftp_sync)
  end
end
