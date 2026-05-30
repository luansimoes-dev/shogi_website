defmodule Shogi.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Shogi.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Shogi.DataCase
    end
  end

  setup _tags do
    :ok
  end
end
