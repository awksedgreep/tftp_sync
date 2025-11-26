defmodule TftpSync.Watcher do
  use GenServer
  require Logger

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    source_dir = Application.fetch_env!(:tftp_sync, :source_dir)
    api_url = Application.fetch_env!(:tftp_sync, :api_url)

    opts = %{
      no_delete_remote: Application.get_env(:tftp_sync, :no_delete_remote, false),
      dry_run: Application.get_env(:tftp_sync, :dry_run, false)
    }

    abs_source_dir = Path.expand(source_dir)

    {:ok, watcher_pid} = FileSystem.start_link(dirs: [abs_source_dir])
    FileSystem.subscribe(watcher_pid)

    # schedule a daily full resync as a safety net for missed events
    schedule_resync()

    {:ok,
     %{
       source_dir: abs_source_dir,
       api_url: api_url,
       watcher_pid: watcher_pid,
       opts: opts
     }}
  end

  @impl true
  def handle_info({:file_event, _watcher_pid, {path, events}}, %{source_dir: source_dir, api_url: api_url, opts: opts} = state) do
    Logger.debug("file event: #{inspect({path, events})}")

    rel_path = Path.relative_to(path, source_dir)

    cond do
      String.starts_with?(Path.basename(rel_path), ".") ->
        :ok

      Enum.any?(events, &(&1 in [:removed, :deleted])) ->
        unless Map.get(opts, :no_delete_remote, false) do
          _ = TftpSync.delete_remote(api_url, rel_path, opts)
        end

      File.regular?(path) ->
        _ = TftpSync.sync_file(source_dir, api_url, rel_path, opts)

      true ->
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:resync, %{source_dir: source_dir, api_url: api_url, opts: opts} = state) do
    Logger.info("running scheduled full resync")

    _ = TftpSync.run_once(source_dir, api_url, opts)

    schedule_resync()

    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp schedule_resync do
    # 24 hours in milliseconds
    :timer.send_after(86_400_000, :resync)
  end
end
