defmodule MemoetWeb.NoteController do
  use MemoetWeb, :controller

  alias Memoet.Notes
  alias Memoet.Notes.{Note, Option, Types}
  alias Memoet.Decks

  @options_limit 5

  @spec create(Plug.Conn.t(), map) :: Plug.Conn.t()
  def create(conn, %{"deck_id" => deck_id, "note" => note_params} = _params) do
    user = Pow.Plug.current_user(conn)

    params =
      note_params
      |> Map.merge(%{
        "deck_id" => deck_id,
        "user_id" => user.id
      })

    Notes.create_note_with_card_transaction(params)
    |> Memoet.Repo.transaction()
    |> case do
      {:ok, %{note: note}} ->
        deck = Decks.get_deck!(deck_id, user.id)
        # Reset new cards count
        Decks.update_new(deck, %{"new_today" => deck.new_per_day, "day_today" => 0})

        conn
        |> put_flash(:info, "Create note success!")
        |> redirect(to: "/decks/" <> deck_id <> "/notes/" <> note.id)

      {:error, _op, changeset, _changes} ->
        conn
        |> put_flash(:error, Memoet.Str.changeset_error_to_string(changeset))
        |> redirect(to: "/decks/" <> deck_id <> "/notes/new")
    end
  end

  @spec index(Plug.Conn.t(), map) :: Plug.Conn.t()
  def index(conn, %{"deck_id" => deck_id}) do
    redirect(conn, to: "/decks/" <> deck_id)
  end

  @spec show(Plug.Conn.t(), map) :: Plug.Conn.t()
  def show(conn, %{"id" => id, "deck_id" => deck_id}) do
    user = Pow.Plug.current_user(conn)
    deck = Decks.get_deck!(deck_id)
    note = Notes.get_note!(id)

    if note.user_id != user.id do
      conn
      |> put_flash(:error, "The desk does not exist, or you must copy it to your account first.")
      |> redirect(to: "/decks")
    else
      conn
      |> assign(:page_title, note.title <> " · " <> deck.name)
      |> render("show.html", note: note, deck: deck)
    end
  end

  @spec new(Plug.Conn.t(), map) :: Plug.Conn.t()
  def new(conn, %{"deck_id" => deck_id} = _params) do
    user = Pow.Plug.current_user(conn)
    deck = Decks.get_deck!(deck_id, user.id)

    embedded_changeset = [
      Option.changeset(%Option{}, %{}),
      Option.changeset(%Option{}, %{}),
      Option.changeset(%Option{}, %{}),
      Option.changeset(%Option{}, %{}),
      Option.changeset(%Option{}, %{})
    ]

    note = %Note{options: embedded_changeset, type: Types.flash_card()}
    changeset = Note.changeset(note, %{})

    render(conn, "new.html", deck: deck, changeset: changeset, note: note)
  end

  @spec delete(Plug.Conn.t(), map) :: Plug.Conn.t()
  def delete(conn, %{"deck_id" => deck_id, "id" => id}) do
    user = Pow.Plug.current_user(conn)
    Notes.delete_note!(id, user.id)

    conn
    |> put_flash(:info, "Delete success!")
    |> redirect(to: "/decks/" <> deck_id)
  end

  @spec edit(Plug.Conn.t(), map) :: Plug.Conn.t()
  def edit(conn, %{"deck_id" => deck_id, "id" => id}) do
    user = Pow.Plug.current_user(conn)
    note = Notes.get_note!(id, user.id)
    deck = Decks.get_deck!(deck_id, user.id)

    empty_options = @options_limit - length(note.options)

    options =
      if empty_options > 0 do
        note.options ++ for _ <- 1..empty_options, do: Option.changeset(%Option{}, %{})
      else
        note.options
      end

    changeset = Note.changeset(%Note{note | options: options}, %{})
    render(conn, "edit.html", note: note, deck: deck, changeset: changeset)
  end

  @spec update(Plug.Conn.t(), map) :: Plug.Conn.t()
  def update(conn, %{"deck_id" => deck_id, "id" => id, "note" => note_params} = _params) do
    user = Pow.Plug.current_user(conn)
    note = Notes.get_note!(id, user.id)

    case Notes.update_note(note, note_params) do
      {:ok, %Note{} = note} ->
        conn
        |> put_flash(:info, "Update note success!")
        |> redirect(to: "/decks/" <> deck_id <> "/notes/" <> note.id)

      {:error, changeset} ->
        deck = Decks.get_deck!(deck_id, user.id)

        conn
        |> put_status(:bad_request)
        |> render("edit.html", changeset: changeset, deck: deck, note: note)
    end
  end
end
