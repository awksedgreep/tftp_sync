defmodule TftpSync do
  require Logger

  def run_once(source_dir, api_url, opts \\ %{}) do
    with {:ok, local_files} <- list_local_files(source_dir),
         {:ok, remote_files} <- TftpSync.Http.get_files(api_url) do
      local_set = MapSet.new(local_files)
      remote_set = MapSet.new(Enum.map(remote_files, & &1["filename"]))

      uploads = local_set
      deletes =
        case Map.get(opts, :no_delete_remote, false) do
          true -> MapSet.new()
          false -> MapSet.difference(remote_set, local_set)
        end

      Enum.each(uploads, fn rel_path ->
        _ = sync_file(source_dir, api_url, rel_path, opts)
      end)

      Enum.each(deletes, fn rel_path ->
        _ = delete_remote(api_url, rel_path, opts)
      end)

      :ok
    else
      {:error, reason} ->
        Logger.error("sync failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def sync_file(source_dir, api_url, rel_path, opts \\ %{}) do
    full_path = Path.join(source_dir, rel_path)

    if Map.get(opts, :dry_run, false) do
      Logger.info("upload #{rel_path} (dry run)")
      :ok
    else
      case upload_file(api_url, rel_path, full_path) do
        :ok ->
          Logger.info("upload #{rel_path}")
          :ok

        {:error, reason} ->
          Logger.error("upload failed for #{rel_path}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  def delete_remote(api_url, rel_path, opts \\ %{}) do
    Logger.info("delete #{rel_path}")

    if Map.get(opts, :dry_run, false) do
      :ok
    else
      case delete_file(api_url, rel_path) do
        :ok -> :ok
        {:error, {:delete_failed, ^rel_path, 404}} ->
          :ok

        {:error, reason} ->
          Logger.error("delete failed for #{rel_path}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp list_local_files(source_dir) do
    pattern = Path.join([source_dir, "**", "*"])

    files =
      pattern
      |> Path.wildcard(match_dot: false)
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(&Path.relative_to(&1, source_dir))

    {:ok, files}
  end

  defp upload_file(api_url, rel_path, full_path) do
    case TftpSync.Http.upload_file(api_url, rel_path, full_path) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status}} -> {:error, {:upload_failed, rel_path, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_file(api_url, rel_path) do
    case TftpSync.Http.delete_file(api_url, rel_path) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status}} -> {:error, {:delete_failed, rel_path, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
