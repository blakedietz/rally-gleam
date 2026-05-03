# Why Server Components Over RPC + SPA

We built a typed RPC layer (libero) to communicate between a Lustre SPA and a Gleam server. The hypothesis was that the code volume would be similar to server components, with the added benefit of less data over the wire (especially with ETF) and no need for persistent WebSocket connections.

That hypothesis was wrong. The SPA approach required dramatically more hand-written code.

## The Numbers

After a full code review of our admin (47K lines across 195 files in the client package), we found that roughly 35-40% of the code existed solely to manage the client-server boundary. Moving to a single Lustre server component eliminated all of it.

## Where the Extra Code Comes From

### 1. Async Loading State (~15,000 lines across all pages)

Every page that loads data must handle three states: Loading, Success, Failure. With the SPA, data arrives asynchronously via RPC, so every page module needs:

```gleam
// SPA: 4 things per data load
pub type Model { Model(data: RpcData(MyData, MyError), ...) }
pub type Msg { DataLoaded(RpcData(MyData, MyError)) }
fn init(...) { #(Model(data: Loading), rpc.load_my_data(on_response: DataLoaded), ...) }
fn update(DataLoaded(Success(d))) -> ...
fn update(DataLoaded(Failure(e))) -> ...
```

With server components, the DB is in-process. Data loads synchronously in `init`:

```gleam
// Server component: just the data
pub type Model { Model(items: List(Item), ...) }
fn init(ctx) { #(Model(items: items.list_all(conn: ctx.db, org_id: ctx.org.id)), effect.none(), None) }
```

No `RpcData` wrapper. No `Loading` state. No `DataLoaded` message. No failure rendering. The data is just there.

### 2. Save/Delete Result Handling (~5,000 lines)

Same pattern for mutations. The SPA fires an RPC, awaits a result message, then handles success/failure:

```gleam
// SPA: fire and await
Save(form_data) -> #(Model(..model, saving: True), rpc.save(form_data, on_response: SaveResult), ...)
SaveResult(Success(_)) -> #(Model(..model, saving: False), ..., Some(#(FlashSuccess, "Saved")), ...)
SaveResult(Failure(e)) -> #(Model(..model, saving: False), ..., Some(#(Danger, format_error(e))), ...)
```

Server component just calls the DB:

```gleam
// Server component: call and respond
Save(form_data) -> {
  case items.update(conn: ctx.db, ...) {
    Ok(_) -> #(model, effect.none(), Some(ShowFlash(Success, "Saved")))
    Error(e) -> #(model, effect.none(), Some(ShowFlash(Danger, format_error(e))))
  }
}
```

One message instead of two. No intermediate `saving: True` state needed (the server processes messages sequentially, so the UI won't accept another click until this one finishes).

### 3. Generated RPC Glue (~3,000 lines generated + type definitions)

libero generates dispatch, decoder, and encoder modules for every RPC endpoint. Each admin page needs at least two RPC definitions (load + save), some need five or six. This generated code exists to serialize typed data across the wire. With server components, there's no wire for application data. The view function has direct access to the model.

### 4. Wrapper Pages (~4,100 lines in 103 files)

The elm-land routing used "wrapper pages" that delegated to inner modules, adding breadcrumbs and re-exporting init/update/view. With server-side codegen, breadcrumbs are computed from the route hierarchy in the generated dispatch, eliminating the wrapper layer entirely.

### 5. Client-Side Routing and Bootstrap (~2,000 lines)

The SPA needs: client-side URL parsing, route matching, modem integration, session bootstrap from a base64-encoded cookie payload, initial RPC to load context. The server component just... starts with context already available (the WebSocket handler authenticated and resolved everything before starting the Lustre process).

## What Doesn't Change

The view code (HTML rendering with Lustre elements, Basecoat components, Tailwind classes) transfers nearly unchanged. It's ~25,000 lines that are the same regardless of where the TEA loop runs.

## The Real Insight

libero solves a serialization problem. Server components eliminate the serialization problem. When the UI process has direct access to the database, there's nothing to serialize, nothing to deserialize, no loading states to manage, no failure recovery for network errors, and no generated glue code to maintain.

The only scenario where the RPC approach wins is when you genuinely need the client to operate independently of the server (offline support, latency-sensitive interactions, many concurrent anonymous users where WebSocket-per-user doesn't scale). An admin panel with ~192 active organizations has none of these constraints.

## Cost of the Wrong Bet

We built the SPA and then realized the overhead. The rewrite to server components:
- Deletes ~47,000 lines of client code
- Produces ~25,000-28,000 lines of server-side admin code
- Eliminates the entire client JavaScript bundle (replaced by 10KB generic Lustre runtime + 89 lines of navigation JS)
- Removes one full build target from the CI pipeline

The lesson: if your UI's job is to display server data and submit forms back to the server, putting an RPC layer between them creates work proportional to the number of pages, not proportional to the complexity of the UI.
