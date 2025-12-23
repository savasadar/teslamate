defmodule TeslaMate.Auth do
  @moduledoc """
  The Auth context.
  """

  import Ecto.Query, warn: false
  require Logger

  alias TeslaMate.Repo

  ### Users

  alias TeslaMate.Auth.User

  def list_users do
    Repo.all(User)
  end

  def get_user(id) do
    Repo.get(User, id)
  end

  def get_user_by(params) do
    Repo.get_by(User, params)
  end

  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  def get_or_create_default_user do
    case get_user_by(email: "default_user@teslamate.local") do
      nil ->
        {:ok, user} = create_user(%{email: "default_user@teslamate.local", name: "Default User"})
        user

      user ->
        user
    end
  end

  ### Tokens

  alias TeslaMate.Auth.Tokens

  def change_tokens(attrs \\ %{}) do
    %Tokens{} |> Tokens.changeset(attrs)
  end

  def can_decrypt_tokens? do
    case get_tokens() do
      %Tokens{} = tokens ->
        is_binary(tokens.access) and is_binary(tokens.refresh)

      nil ->
        true
    end
  end

  # Get tokens for the default user (backward compatibility)
  def get_tokens do
    user = get_or_create_default_user()
    get_tokens_for_user(user.id)
  end

  # Get tokens for a specific user
  def get_tokens_for_user(user_id) do
    case Repo.all(from t in Tokens, where: t.user_id == ^user_id, limit: 1) do
      [%Tokens{} = tokens] ->
        tokens

      [] ->
        nil
    end
  end

  # Get all tokens for all users
  def get_all_tokens do
    Repo.all(Tokens)
  end

  # Save tokens (backward compatibility - uses default user)
  def save(%{token: access, refresh_token: refresh}) do
    user = get_or_create_default_user()
    save_for_user(user.id, %{token: access, refresh_token: refresh})
  end

  # Save tokens for a specific user
  def save_for_user(user_id, %{token: access, refresh_token: refresh}) do
    attrs = %{access: access, refresh: refresh, user_id: user_id}

    maybe_created_or_updated =
      case get_tokens_for_user(user_id) do
        nil -> create_tokens(attrs)
        tokens -> update_tokens(tokens, attrs)
      end

    with {:ok, _tokens} <- maybe_created_or_updated do
      :ok
    end
  end

  defp create_tokens(attrs) do
    %Tokens{}
    |> Tokens.changeset(attrs)
    |> Repo.insert()
  end

  defp update_tokens(%Tokens{} = tokens, attrs) do
    tokens
    |> Tokens.changeset(attrs)
    |> Repo.update()
  end
end
