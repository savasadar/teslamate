defmodule TeslaMate.ApiRegistry do
  @moduledoc """
  Registry for managing multiple API instances, one per user.
  """

  use Supervisor
  require Logger

  alias TeslaMate.{Api, Auth}
  alias TeslaMate.Auth.{User, Tokens}

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children =
      Auth.list_users()
      |> Enum.map(fn %User{id: user_id} ->
        %{
          id: {Api, user_id},
          start: {Api, :start_link, [[name: api_name(user_id), auth: {Auth, user_id}]]},
          restart: :permanent
        }
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Get the API process name for a given user_id
  """
  def api_name(user_id) do
    :"TeslaMate.Api.User#{user_id}"
  end

  @doc """
  Get API for a specific user
  """
  def get_api(user_id) do
    name = api_name(user_id)

    case Process.whereis(name) do
      pid when is_pid(pid) -> {:ok, name}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Start API for a new user
  """
  def start_api_for_user(user_id) do
    child_spec = %{
      id: {Api, user_id},
      start: {Api, :start_link, [[name: api_name(user_id), auth: {Auth, user_id}]]},
      restart: :permanent
    }

    case Supervisor.start_child(__MODULE__, child_spec) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      error -> error
    end
  end

  @doc """
  Stop API for a user
  """
  def stop_api_for_user(user_id) do
    Supervisor.terminate_child(__MODULE__, {Api, user_id})
    Supervisor.delete_child(__MODULE__, {Api, user_id})
  end
end
