defmodule TftpSync.IntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  defp api_url do
    System.get_env("TFTP_SYNC_TEST_API_URL", "http://127.0.0.1:4000")
  end

  defp source_dir do
    Path.expand("priv/fixtures", File.cwd!())
  end

  defp remote_filenames(api_url) do
    case TftpSync.Http.get_files(api_url) do
      {:ok, files} ->
        Enum.map(files, & &1["filename"])

      {:error, reason} ->
        flunk("get_files failed: #{inspect(reason)}")
    end
  end

  # Clean up any leftover integration_test_*.bin files from DDNet before tests
  setup do
    api = api_url()

    case TftpSync.Http.get_files(api) do
      {:ok, files} ->
        files
        |> Enum.map(& &1["filename"])
        |> Enum.filter(&String.contains?(&1, "integration_test_"))
        |> Enum.each(fn filename ->
          TftpSync.Http.delete_file(api, filename)
        end)

      _ ->
        :ok
    end

    :ok
  end

  @tag :requires_ddnet
  test "sync includes base fixtures" do
    api = api_url()
    dir = source_dir()

    assert File.dir?(dir), "fixtures source_dir does not exist: #{dir}"

    assert :ok = TftpSync.run_once(dir, api, %{})

    filenames = remote_filenames(api)

    assert "config/router.conf" in filenames
    assert "firmware/modem-x/v1.bin" in filenames
  end

  @tag :requires_ddnet
  test "sync uploads and then deletes a test file" do
    api = api_url()
    dir = source_dir()

    rel_path = "firmware/modem-x/integration_test_" <> Integer.to_string(System.unique_integer([:positive])) <> ".bin"
    full_path = Path.join(dir, rel_path)

    File.mkdir_p!(Path.dirname(full_path))
    File.write!(full_path, "integration-test")

    # First sync should upload the test file
    assert :ok = TftpSync.run_once(dir, api, %{})
    filenames_after_upload = remote_filenames(api)
    assert rel_path in filenames_after_upload

    # Remove the local file and sync again; remote should delete it
    File.rm!(full_path)
    assert :ok = TftpSync.run_once(dir, api, %{})
    filenames_after_delete = remote_filenames(api)
    refute rel_path in filenames_after_delete
  end

  @tag :requires_ddnet
  test "second sync is idempotent" do
    api = api_url()
    dir = source_dir()

    # First sync to establish baseline
    assert :ok = TftpSync.run_once(dir, api, %{})
    names1 = MapSet.new(remote_filenames(api))

    # Second sync should not change the set of filenames
    assert :ok = TftpSync.run_once(dir, api, %{})
    names2 = MapSet.new(remote_filenames(api))

    assert names1 == names2
  end
end
