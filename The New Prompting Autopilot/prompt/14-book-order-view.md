---
description: Add the administrator view for ordering books
---

## Guardrails

- Work in the application repository: the parent directory of this prompt pack
  (`..`). It is the only source of truth.
- Do exactly this task. Touch only the files named here.
- Reuse the existing arrangement controller. Do not fork it into a second
  drag-and-drop implementation.
- Match the repo's Ruby style (`rubocop-rails-omakase`). Any JavaScript you
  touch follows house style: double quotes, no semicolons, 2-space indent, no
  trailing commas, `const` by default.
- If an anchor is missing or the reuse would require a rewrite, write the reason
  to `.scratch/BLOCKED-14-book-order-view` and stop.
- Verify with `bin/rails test`, `bin/rails test:system`, and `bin/rubocop`.

## Context

The book table of contents already reorders leaves with
`app/javascript/controllers/arrangement_controller.js`. It is driven by:

- `app/helpers/arrangement_helper.rb` — `arrangement_tag` and
  `arrangement_actions`
- `app/views/books/show.html.erb` — the `arrangement_tag` block and the
  `.position-relative` wrapper
- `app/controllers/books/leaves/moves_controller.rb` — `position` plus `id[]`
- `app/views/books/_mode_buttons.html.erb` — the arrange-mode checkbox

The controller measures real rectangles, so it works on the library's CSS grid
as long as the plates are direct children of the item list and a
`.position-relative` ancestor wraps the whole thing.

## Task

### 1. Routes

Add these before `resources :books` in `config/routes.rb`:

```ruby
get "books/order", to: "books/orders#show", as: :books_order
post "books/moves", to: "books/moves#create", as: :books_moves
```

### 2. Controllers

`app/controllers/books/orders_controller.rb`:

```ruby
class Books::OrdersController < ApplicationController
  before_action :ensure_can_administer

  def show
    @books = Book.positioned
  end
end
```

`app/controllers/books/moves_controller.rb`: guard with
`before_action :ensure_can_administer`. Find the books with
`Book.find(Array(params[:id]))` so the ids keep the order the client sent, then
take the first as the moved book and the rest as `followed_by`. Call
`move_to_position(params[:position].to_i, followed_by:)` and return
`head :no_content`. Rescue `ActiveRecord::RecordNotFound` with
`head :unprocessable_entity`.

Do not copy the leaves controller's `@book.leaves.find(...)`: books are global.

### 3. Helper

Generalize `arrangement_tag` in `app/helpers/arrangement_helper.rb` so the book
is optional:

- Default `book = nil`.
- Default `url:` to `book ? book_leaves_moves_url(book) : books_moves_url`.
- When `book` is nil, use `controller: "arrangement"` and omit the
  `reading_progress_*` data attributes.
- Keep the existing positional call `arrangement_tag @book, class: ...` working.

Do not change `arrangement_actions`.

### 4. Views

`app/views/books/orders/show.html.erb`:

- A masthead: "Order the library" and a **Done** link to `root_path`.
- An arrange-mode checkbox label using `arrangement#setArrangeMode`, with the
  `rearrange.svg` icon. Do not include the delete toggle.
- A `.position-relative` wrapper.
- `<menu class="library arrangement__container" tabindex="0"
  data-arrangement-target="container" data-action="<%= arrangement_actions %>">`
  as the direct parent of the plates.
- The layer and drag-image divs, exactly as `books/show.html.erb` does.
- A short keyboard hint: select, arrows to move, Shift+arrows to extend,
  Space to move, Enter to apply, Escape to cancel.

`app/views/books/_orderable_book.html.erb`:

- `<figure class="library__book arrangement__item"
  data-arrangement-target="item" data-id="<%= book.id %>">`
- The same cover, title, and author as `books/_book`, plus a **Draft** badge
  when `!book.published?`.
- The drag handle using the existing `.btn.arrangement__handle` class.
- No bookmark turbo frame and no `cache` block: this page is admin-only and
  must not issue a request per book.

### 5. Entry point

In `app/views/books/index.html.erb`, inside the
`Current.user.can_administer?` branch, add a link to `books_order_path` with the
`rearrange.svg` icon and a screen-reader label "Reorder books". Place it beside
the Export link.

### 6. Styles

Add a small `app/assets/stylesheets/library_order.css`:

- `.order-library .arrangement__handle { display: none; }`
- `.order-library:has(#arrange-mode:checked) .arrangement__handle { display: flex; }`
- while arranging, `user-select: none` on the container and no transitions on
  the plates
- the wrapper needs `position: relative`; do not change the `.library` grid

Import it in the stylesheet manifest the app already uses.

### 7. Tests

- `test/controllers/books/orders_controller_test.rb`: administrator gets 200;
  member and anonymous get 403.
- `test/controllers/books/moves_controller_test.rb`: administrator moves a
  book; member is forbidden; an unknown id returns 422; the new order persists.
- `test/system/order_books_test.rb`: sign in as an administrator, open the
  order page, focus the list, press Space, move with the arrow keys, press
  Enter, reload, assert the new order.
- Assert the library hides the entry point from a member.

## Gotchas

- `arrangement_controller` reads `item.dataset.id`; every plate needs `data-id`.
- The keyboard actions attach to the container, which needs `tabindex="0"`.
- Do not use the CSS `order` property on grid items. DOM order is the model.
- The drag layer positions clones against the nearest `.position-relative`
  ancestor. Without that wrapper the clones land in the wrong place.
- `arrangement.css` shows the handle only under `#toc-list`. The order page
  needs its own rule, or the handle never appears.
- The helper currently hardcodes the leaves URL. Generalize it; do not add a
  second helper that copies the data attributes.

## Done when

- `bin/rails test` and `bin/rubocop` pass.
- The system test proves a keyboard reorder survives a reload.
- A member cannot see the entry point and receives 403 from both routes.
