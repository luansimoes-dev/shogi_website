defmodule ShogiWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint ShogiWeb.Endpoint

      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import Plug.Conn
      import ShogiWeb.ConnCase

      use Phoenix.VerifiedRoutes,
        endpoint: ShogiWeb.Endpoint,
        router: ShogiWeb.Router,
        statics: ShogiWeb.static_paths()
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
