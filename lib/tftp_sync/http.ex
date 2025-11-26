defmodule TftpSync.Http do
  @stats_path "/api/tftp/stats"
  @files_path "/api/tftp/files"
  @default_max_attempts 3

  defp retry_sleep(attempt) do
    # simple backoff: 100ms, 300ms, 1000ms
    case attempt do
      1 -> 100
      2 -> 300
      _ -> 1_000
    end
  end

  def test_connection(api_url) do
    url = api_url <> @stats_path

    case request_with_retry(:get, url, [{"connection", "close"}], nil, :stats, 1) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status}} -> {:error, {:unexpected_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_files(api_url) do
    url = api_url <> @files_path

    with {:ok, %{status: 200, body: body}} <- request_with_retry(:get, url, [{"connection", "close"}], nil, :list_files, 1),
         {:ok, %{"files" => files}} <- Jason.decode(body) do
      {:ok, files}
    else
      {:ok, %{status: status}} -> {:error, {:unexpected_status, status}}
      {:error, reason} -> {:error, reason}
      {:ok, _other} -> {:error, :invalid_response}
    end
  end

  def upload_file(api_url, filename, full_path) do
    url = api_url <> @files_path

    boundary = "tftpsync-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    {:ok, file_contents} = File.read(full_path)

    body =
      [
        "--", boundary, "\r\n",
        "Content-Disposition: form-data; name=\"file\"; filename=\"", filename, "\"\r\n",
        "Content-Type: application/octet-stream\r\n\r\n",
        file_contents, "\r\n",
        "--", boundary, "\r\n",
        "Content-Disposition: form-data; name=\"filename\"\r\n\r\n",
        filename, "\r\n",
        "--", boundary, "--\r\n"
      ]
      |> IO.iodata_to_binary()

    headers = [
      {"content-type", "multipart/form-data; boundary=" <> boundary},
      {"connection", "close"}
    ]

    request_with_retry(:post, url, headers, body, {:upload, filename}, 1)
  end

  def delete_file(api_url, filename) do
    # Encode the entire filename including slashes so it becomes a single path segment
    encoded = URI.encode(filename, &URI.char_unreserved?/1)
    url = api_url <> @files_path <> "/" <> encoded
    request_with_retry(:delete, url, [{"connection", "close"}], nil, {:delete, filename}, 1)
  end

  defp request_with_retry(method, url, headers \\ [], body \\ nil, operation, attempt)

  defp request_with_retry(_method, url, _headers, _body, op, attempt)
       when attempt > @default_max_attempts do
    require Logger
    Logger.error("HTTP max retries exceeded for #{inspect(op)} to #{url}")
    {:error, {:max_retries_exceeded, op}}
  end

  defp request_with_retry(method, url, headers, body, op, attempt) do
    case request(method, url, headers, body) do
      {:ok, %{status: status}} = ok when status in 200..399 ->
        ok

      {:ok, %{status: status}} = resp when status in 400..499 ->
        # client error, do not retry
        resp

      {:ok, %{status: _status}} ->
        :timer.sleep(retry_sleep(attempt))
        request_with_retry(method, url, headers, body, op, attempt + 1)

      {:error, reason} ->
        require Logger
        Logger.error("HTTP error for #{inspect(op)} to #{url}: #{inspect(reason)} (attempt #{attempt})")
        :timer.sleep(retry_sleep(attempt))
        request_with_retry(method, url, headers, body, {:op_error, op, reason}, attempt + 1)
    end
  end

  defp request(method, url, headers, body) do
    method
    |> Finch.build(url, headers, body)
    |> Finch.request(TftpSync.Finch)
  end
end
