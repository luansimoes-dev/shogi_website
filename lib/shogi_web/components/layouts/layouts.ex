defmodule ShogiWeb.Layouts do
  use ShogiWeb, :html

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <meta name="viewport" content="width=device-width, initial-scale=1" />

        <title>Shogi</title>

        <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
        <script defer phx-track-static type="text/javascript" src={~p"/assets/app.js"}>
        </script>
      </head>

      <body>
        <%= @inner_content %>
      </body>
    </html>
    """
  end

  def app(assigns) do
    ~H"""
    <main class="app-shell">
      <header class="app-header">
        <div class="app-header-inner">
          <a href={~p"/"} class="brand">
            Shogi
          </a>

          <span class="app-badge">
            MVP
          </span>
        </div>
      </header>

      <section class="page">
        <%= @inner_content %>
      </section>
    </main>
    """
  end
end
