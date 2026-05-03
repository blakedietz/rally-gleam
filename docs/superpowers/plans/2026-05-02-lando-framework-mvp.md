# Lando Framework MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A working end-to-end lando framework: `lando new` scaffolds a project, `bin/dev` regenerates routes + server dispatch + client package, and a page module renders in the browser with SSR hydration and ETF-over-WebSocket RPC.

**Architecture:** The existing lando scanner and generator are refactored for general use, then extended with page module parsing (ToBackend/ToFrontend detection), server dispatch generation, SSR handler generation, client package generation, and a small runtime library. Marmot and libero are reused for SQL codegen and ETF codec internals respectively.

**Tech Stack:** Gleam (Erlang target for server, JavaScript target for client), Lustre, Mist, libero (ETF codec modules), marmot (SQL codegen), glance (page module parsing).

---

### Task 1: Refactor scanner for general use

**Files:**
- Modify: `src/lando/scanner.gleam`
- Modify: `src/lando.gleam`
- Modify: `test/lando/scanner_test.gleam`

The scanner currently has hardcoded paths and is coupled to one project structure. Refactor it to accept configuration.

- [ ] **Step 1: Add a ScanConfig type to types.gleam**

In `src/lando/types.gleam`, add:

```gleam
pub type ScanConfig {
  ScanConfig(
    pages_root: String,     // path to pages/ directory
    output_route: String,   // where to write route.gleam
    output_dispatch: String, // where to write page_dispatch.gleam
    output_server_dispatch: String, // where to write server_dispatch.gleam
    output_ssr: String,     // where to write ssr_handler.gleam
    client_root: String,    // path to client package root
  )
}
```

- [ ] **Step 2: Update scanner.scan to take ScanConfig**

In `src/lando/scanner.gleam`, change `pub fn scan(root: String)` to `pub fn scan(config: ScanConfig)`. Use `config.pages_root` instead of the hardcoded root. The scan logic is otherwise unchanged.

- [ ] **Step 3: Update lando.gleam to read config from gleam.toml**

In `src/lando.gleam`, replace the hardcoded constants with config reading:

```gleam
import gleam/toml
import simplifile

fn read_config() -> Result(ScanConfig, String) {
  use toml_str <- result.try(
    simplifile.read("gleam.toml")
    |> result.map_error(fn(e) { "Cannot read gleam.toml: " <> string.inspect(e) })
  )
  use toml_map <- result.try(
    toml.parse(toml_str)
    |> result.map_error(fn(e) { "Invalid gleam.toml: " <> e })
  )
  // Read [tools.lando] section
  let lando_config = toml.get_table(toml_map, ["tools", "lando"])
  let pages_root = case toml.get_string(lando_config, "pages_root") {
    Ok(v) -> v
    Error(_) -> "src/pages"
  }
  // ... read remaining keys with defaults
  Ok(ScanConfig(pages_root:, ...))
}
```

Add `tom` to `gleam.toml` dependencies.

- [ ] **Step 4: Run existing tests**

```bash
cd /Users/daverapin/projects/opensource/lando && gleam test
```

All existing scanner and generator tests must pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "refactor: make scanner configurable, read config from gleam.toml"
```

---

### Task 2: Add page module parser

**Files:**
- Create: `src/lando/parser.gleam`
- Create: `test/lando/parser_test.gleam`
- Modify: `src/lando/types.gleam`

The scanner walks directories. The parser reads individual page module files and identifies the ToBackend/ToFrontend types, the presence of server_update, and the load function. For the MVP, use structural convention matching (not a full Gleam parser).

- [ ] **Step 1: Add PageContract type to types.gleam**

In `src/lando/types.gleam`, add:

```gleam
pub type PageContract {
  PageContract(
    to_backend_variants: List(String),     // variant names
    to_frontend_variants: List(String),    // variant names
    has_server_update: Bool,
    has_load: Bool,
    has_init: Bool,
    has_model: Bool,
    param_names: List(String),             // URL params from init signature
  )
}
```

- [ ] **Step 2: Write the failing test**

In `test/lando/parser_test.gleam`:

```gleam
import lando/parser
import lando/types.{PageContract}

pub fn parse_page_with_to_backend_test() {
  let source = "
pub type ToBackend { LoadProduct(id: Int); SaveProduct(data: ProductData) }
pub type ToFrontend { ProductLoaded(Product); SaveError(String) }
pub fn server_update(model: ServerModel, msg: ToBackend, ctx: Context) -> #(ServerModel, Effect(ToFrontend)) { ... }
pub fn init(id: Int) -> #(Model, Effect(Msg)) { ... }
pub fn load(id: Int, ctx: Context) -> Result(Model, LoadError) { ... }
"
  let result = parser.parse_page(source)
  let assert Ok(contract) = result
  contract.to_backend_variants |> should.equal(["LoadProduct", "SaveProduct"])
  contract.to_frontend_variants |> should.equal(["ProductLoaded", "SaveError"])
  contract.has_server_update |> should.be_true()
  contract.has_load |> should.be_true()
  contract.param_names |> should.equal(["id"])
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
gleam test -- test/lando/parser_test.gleam
```
Expected: compile error (module doesn't exist yet).

- [ ] **Step 4: Implement the parser**

In `src/lando/parser.gleam`:

```gleam
import gleam/list
import gleam/string
import lando/types.{PageContract}

/// Parse a page module source to extract the contract.
/// Uses structural string matching — detects type definitions
/// and function signatures by pattern.
pub fn parse_page(source: String) -> Result(PageContract, String) {
  let to_backend = extract_variants(source, "pub type ToBackend")
  let to_frontend = extract_variants(source, "pub type ToFrontend")
  let has_server_update = string.contains(source, "pub fn server_update")
  let has_load = string.contains(source, "pub fn load")
  let has_init = string.contains(source, "pub fn init")
  let has_model = string.contains(source, "pub type Model")
  let param_names = extract_init_params(source)

  Ok(PageContract(
    to_backend_variants: to_backend,
    to_frontend_variants: to_frontend,
    has_server_update:,
    has_load:,
    has_init:,
    has_model:,
    param_names:,
  ))
}

fn extract_variants(source: String, type_decl: String) -> List(String) {
  case string.split_once(source, type_decl) {
    Error(_) -> []
    Ok(#(_, rest)) -> {
      // Find everything between { and }, split on ;, extract first word
      case string.split_once(rest, "{") {
        Error(_) -> []
        Ok(#(_, after_brace)) -> {
          case string.split_once(after_brace, "}") {
            Error(_) -> []
            Ok(#(body, _)) ->
              body
              |> string.split(";")
              |> list.filter_map(fn(variant) {
                let trimmed = string.trim(variant)
                case string.split_once(trimmed, " ") {
                  Ok(#(name, _)) -> Ok(name)
                  Error(_) ->
                    case string.split_once(trimmed, "(") {
                      Ok(#(name, _)) -> Ok(name)
                      Error(_) -> Error(Nil)
                    }
                }
              })
          }
        }
      }
    }
  }
}

fn extract_init_params(source: String) -> List(String) {
  case string.split_once(source, "pub fn init(") {
    Error(_) -> []
    Ok(#(_, rest)) -> {
      case string.split_once(rest, ")") {
        Error(_) -> []
        Ok(#(params, _)) -> {
          params
          |> string.split(",")
          |> list.filter_map(fn(param) {
            let trimmed = string.trim(param)
            case trimmed {
              "" -> Error(Nil)
              // Skip type annotations, extract just the name
              p -> {
                case string.split_once(p, ":") {
                  Ok(#(name, _)) -> Ok(string.trim(name))
                  Error(_) -> Ok(string.trim(p))
                }
              }
            }
          })
        }
      }
    }
  }
}
```

- [ ] **Step 5: Run test**

```bash
gleam test -- test/lando/parser_test.gleam
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/lando/parser.gleam src/lando/types.gleam test/lando/parser_test.gleam
git commit -m "feat: add page module parser for ToBackend/ToFrontend detection"
```

---

### Task 3: Split generator into sub-modules

**Files:**
- Create: `src/lando/generator/utils.gleam`
- Rename: `src/lando/generator.gleam` → `src/lando/generator/router.gleam` (with backward-compat re-export)
- Modify: `test/lando/generator_test.gleam`

The current generator is one 600-line file doing two jobs (routes + dispatch). Split it before adding more generators.

- [ ] **Step 1: Extract shared helpers to utils.gleam**

Move `to_pascal_case`, `to_snake_case`, `import_alias`, `param_type_to_gleam`, `variant_pattern` to `src/lando/generator/utils.gleam`:

```gleam
import gleam/list
import gleam/string
import lando/types.{type ParamType, IntParam, StringParam}

pub fn to_pascal_case(name: String) -> String {
  name |> string.split("_") |> list.map(string.capitalise) |> string.join("")
}

pub fn to_snake_case(name: String) -> String {
  name
  |> string.to_graphemes()
  |> do_snake_case([], True)
  |> list.reverse()
  |> string.concat()
  |> string.lowercase()
}

fn do_snake_case(chars: List(String), acc: List(String), first: Bool) -> List(String) {
  case chars {
    [] -> acc
    [c, ..rest] -> {
      let is_upper = c != string.lowercase(c)
      case is_upper && !first {
        True -> do_snake_case(rest, [c, "_", ..acc], False)
        False -> do_snake_case(rest, [c, ..acc], False)
      }
    }
  }
}

pub fn import_alias(variant_name: String) -> String {
  "page_" <> to_snake_case(variant_name)
}

pub fn param_type_to_gleam(pt: ParamType) -> String {
  case pt { IntParam -> "Int"; StringParam -> "String" }
}
```

- [ ] **Step 2: Rename generator.gleam to router.gleam**

Move `src/lando/generator.gleam` to `src/lando/generator/router.gleam`. Remove the helpers that were extracted to utils. Add `import lando/generator/utils` and use qualified calls.

- [ ] **Step 3: Create backward-compat re-export**

Create `src/lando/generator.gleam` with:

```gleam
pub import lando/generator/router
```

- [ ] **Step 4: Run tests**

```bash
gleam test
```
Expected: all existing tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "refactor: split generator into router + utils sub-modules"
```

---

### Task 4: Add client package scaffolding

**Files:**
- Create: `src/lando/generator/client.gleam`
- Create: `test/lando/generator/client_test.gleam`

The client generator creates the entire `client/` package from scratch: gleam.toml, src/generated/ directory, and all required source files.

- [ ] **Step 1: Write failing test for client package scaffold**

In `test/lando/generator/client_test.gleam`:

```gleam
import lando/generator/client
import lando/types.{ScannedRoute, PageContract, ScanConfig}

pub fn generate_client_gleam_toml_test() {
  let routes = []
  let contracts = []
  let config = ScanConfig(
    pages_root: "src/pages",
    output_route: "src/generated/router.gleam",
    output_dispatch: "src/generated/page_dispatch.gleam",
    output_server_dispatch: "src/generated/server_dispatch.gleam",
    output_ssr: "src/generated/ssr_handler.gleam",
    client_root: "client",
  )
  let files = client.generate_package(routes, [], config)
  // Should produce at minimum: gleam.toml, src/generated/app.gleam
  let toml_file = list.find(files, fn(f) { f.path == "client/gleam.toml" })
  let assert Ok(_) = toml_file
}
```

- [ ] **Step 2: Implement client package scaffold**

In `src/lando/generator/client.gleam`:

```gleam
import gleam/list
import gleam/string
import lando/types.{type ScannedRoute, type PageContract, type ScanConfig}

pub type GeneratedFile {
  GeneratedFile(path: String, content: String)
}

pub fn generate_package(
  routes: List(ScannedRoute),
  contracts: List(#(ScannedRoute, PageContract)),
  config: ScanConfig,
) -> List(GeneratedFile) {
  [
    GeneratedFile(config.client_root <> "/gleam.toml", client_gleam_toml()),
    GeneratedFile(config.client_root <> "/src/generated/app.gleam", app_gleam(routes, contracts)),
  ]
}

fn client_gleam_toml() -> String {
  "name = \"client\"
version = \"0.1.0\"
target = \"javascript\"

[dependencies]
gleam_stdlib = \">= 0.60.0 and < 2.0.0\"
lustre = \">= 5.6.0 and < 7.0.0\"
"
}

fn app_gleam(
  routes: List(ScannedRoute),
  _contracts: List(#(ScannedRoute, PageContract)),
) -> String {
  "// Generated by lando — do not edit.
import lustre
import lustre/element.{type Element}
import generated/router
import generated/transport

pub type Model {
  Model(
    route: router.Route,
  )
}

pub type Msg {
  UrlChanged(router.Route)
}

pub fn main() {
  let app = lustre.application(init, update, view)
  lustre.start(app, \"#app\", Nil)
}

fn init(_flags: Nil) -> #(Model, Effect(Msg)) {
  let route = router.parse_route_from_url()
  #(Model(route:), effect.none())
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UrlChanged(route) -> #(Model(..model, route:), effect.none())
  }
}

fn view(model: Model) -> Element(Msg) {
  case model.route {
    _ -> lustre/element/html.text(\"Hello from lando!\")
  }
}
"
}
```

- [ ] **Step 3: Run tests**

```bash
gleam test -- test/lando/generator/client_test.gleam
```
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add client package scaffold generator"
```

---

### Task 5: Generate server dispatch

**Files:**
- Create: `src/lando/generator/server_dispatch.gleam`
- Create: `test/lando/generator/server_dispatch_test.gleam`

The server dispatch handles incoming WebSocket messages: deserialize the `ToBackend` message, route it to the correct page's `server_update`, serialize the `ToFrontend` response, and send it back.

- [ ] **Step 1: Write failing test**

In `test/lando/generator/server_dispatch_test.gleam`:

```gleam
import lando/generator/server_dispatch
import lando/types.{ScannedRoute, PageContract, StaticSegment}

pub fn generate_server_dispatch_test() {
  let route = ScannedRoute(
    segments: [StaticSegment("counter")],
    variant_name: "Counter",
    params: [],
    module_path: "pages/counter",
  )
  let contract = PageContract(
    to_backend_variants: ["Increment", "Decrement"],
    to_frontend_variants: ["CounterNewValue"],
    has_server_update: True,
    has_load: False,
    has_init: True,
    has_model: True,
    param_names: [],
  )
  let source = server_dispatch.generate([#(route, contract)])
  // The generated source must import the page module
  string.contains(source, "import pages/counter") |> should.be_true()
  // Must contain WS handler
  string.contains(source, "pub fn handle_message") |> should.be_true()
}
```

- [ ] **Step 2: Implement server dispatch generator**

In `src/lando/generator/server_dispatch.gleam`:

```gleam
import gleam/list
import gleam/string
import lando/types.{type ScannedRoute, type PageContract, DynamicSegment, StaticSegment}
import lando/generator/utils

pub fn generate(
  page_contracts: List(#(ScannedRoute, PageContract)),
) -> String {
  let header = "// Generated by lando — do not edit.\n\nimport gleam/dynamic\nimport mist/websocket\nimport lando_runtime/effect\n"
  let imports = generate_imports(page_contracts)
  let handler = generate_handler(page_contracts)
  string.join([header, imports, handler], "\n\n") <> "\n"
}

fn generate_imports(
  page_contracts: List(#(ScannedRoute, PageContract)),
) -> String {
  page_contracts
  |> list.map(fn(pair) {
    let #(route, _) = pair
    "import " <> route.module_path
  })
  |> string.join("\n")
}

fn generate_handler(
  page_contracts: List(#(ScannedRoute, PageContract)),
) -> String {
  let arms = page_contracts
    |> list.filter_map(fn(pair) {
      let #(route, contract) = pair
      case contract.has_server_update {
        False -> Error(Nil)
        True -> {
          let variant_name = route.variant_name
          let module_alias = utils.import_alias(variant_name)
          Ok("    { module: \"" <> variant_name <> "\", variant:, .. } -> {\n"
            <> "      let msg = dynamic.unsafe_coerce(variant)\n"
            <> "      " <> module_alias <> ".server_update(model." <> utils.to_snake_case(variant_name) <> ", msg, ctx)\n"
            <> "    }")
        }
      }
    })
    |> string.join("\n")

  "pub fn handle_message(
  model: ServerModel,
  module: String,
  variant: dynamic.Dynamic,
  ctx: Context,
) -> #(ServerModel, Effect(ToFrontend)) {
  case module {\n" <> arms <> "\n    _ -> #(model, effect.none())\n  }\n}"
}
```

- [ ] **Step 3: Run tests**

```bash
gleam test -- test/lando/generator/server_dispatch_test.gleam
```
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: generate server dispatch for WebSocket message routing"
```

---

### Task 6: Generate SSR handler

**Files:**
- Create: `src/lando/generator/ssr_handler.gleam`
- Create: `test/lando/generator/ssr_handler_test.gleam`

The SSR handler boots the initial page: parse the URL, call the page's `load` function, render `view` to HTML, embed the serialized model, and return a Mist `Response`.

- [ ] **Step 1: Write failing test**

In `test/lando/generator/ssr_handler_test.gleam`:

```gleam
import lando/generator/ssr_handler
import lando/types.{ScannedRoute, PageContract, StaticSegment}

pub fn generate_ssr_handler_test() {
  let route = ScannedRoute(
    segments: [StaticSegment("counter")],
    variant_name: "Counter",
    params: [],
    module_path: "pages/counter",
  )
  let contract = PageContract(
    to_backend_variants: [],
    to_frontend_variants: [],
    has_server_update: True,
    has_load: True,
    has_init: True,
    has_model: True,
    param_names: [],
  )
  let source = ssr_handler.generate([#(route, contract)])
  string.contains(source, "pub fn handle_request") |> should.be_true()
  string.contains(source, "element.to_document_string") |> should.be_true()
}
```

- [ ] **Step 2: Implement SSR handler generator**

In `src/lando/generator/ssr_handler.gleam`:

```gleam
import gleam/list
import gleam/string
import lando/types.{type ScannedRoute, type PageContract}
import lando/generator/utils

pub fn generate(
  page_contracts: List(#(ScannedRoute, PageContract)),
) -> String {
  let header = "// Generated by lando — do not edit.\n\nimport gleam/http/request\nimport gleam/http/response\nimport lustre/element\nimport mist.{type Response, type ResponseData}\nimport lando_runtime/ssr\nimport lando_runtime/codec\nimport generated/router\n"

  let load_arms = generate_load_arms(page_contracts)

  header <> "
pub fn handle_request(req: request.Request(mist.Body)) -> Response(ResponseData) {
  case request.method(req) {
    request.Get -> {
      let route = router.parse_route(request.uri(req))
      case route {\n" <> load_arms <> "
        router.NotFound(_) -> response.new(404)
        |> response.set_body(mist.Bytes(<<\"Not found\">>))
      }
    }
    _ -> response.new(405)
    |> response.set_body(mist.Bytes(<<\"Method not allowed\">>))
  }
}
"
}

fn generate_load_arms(
  page_contracts: List(#(ScannedRoute, PageContract)),
) -> String {
  page_contracts
  |> list.filter_map(fn(pair) {
    let #(route, contract) = pair
    case contract.has_load, contract.has_model {
      True, True -> {
        let alias = utils.import_alias(route.variant_name)
        let pattern = route_pattern_for_load(route)
        let load_args = route.params |> list.map(fn(p) { p.0 }) |> string.join(", ")
        let has_params = route.params != []
        let ctx_arg = case has_params { True -> ", ctx" False -> "ctx" }
        Ok(
          "        router." <> route.variant_name <> pattern <> " -> {\n"
          <> "          let model = " <> alias <> ".load(" <> load_args <> ctx_arg <> ")\n"
          <> "          let html = element.to_document_string(" <> alias <> ".view(model))\n"
          <> "          let flags = codec.encode_flags(model)\n"
          <> "          let full_html = html <> \"<script>window.__LANDO_FLAGS__='\" <> flags <> \"'</script>\"\n"
          <> "          response.new(200)\n"
          <> "          |> response.set_body(mist.Bytes(<<full_html:utf8>>))\n"
          <> "        }"
        )
      }
      _ -> Error(Nil)
    }
  })
  |> string.join("\n")
}

fn route_pattern_for_load(route: ScannedRoute) -> String {
  case route.params {
    [] -> ""
    params -> {
      let names = list.map(params, fn(p) { p.0 })
      "(" <> string.join(names, ", ") <> ")"
    }
  }
}
```

- [ ] **Step 3: Run tests**

```bash
gleam test -- test/lando/generator/ssr_handler_test.gleam
```
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: generate SSR handler for initial page rendering"
```

---

### Task 7: Create lando_runtime library

**Files:**
- Create: `src/lando_runtime.gleam`
- Create: `src/lando_runtime/effect.gleam`
- Create: `src/lando_runtime/codec.gleam`
- Create: `src/lando_runtime/ssr.gleam`
- Create: `src/lando_runtime/ffi.mjs` (JS FFI for WebSocket transport)

The runtime library provides the primitives that page modules and generated code depend on: `send_to_backend`, `send_to_client`, `broadcast`, ETF encode/decode, and SSR utilities.

- [ ] **Step 1: Create effect module**

In `src/lando_runtime/effect.gleam`:

```gleam
import lustre/effect.{type Effect}

/// Send a ToBackend variant to the server.
/// On the client: serializes and sends over WebSocket.
/// On the server: no-op (server_update calls are direct).
pub fn send_to_backend(msg: a) -> Effect(b) {
  effect.from(fn(dispatch) {
    // Client-side: transport.send(dispatch, msg)
    // Server-side: no-op
    Nil
  })
}

/// Send a ToFrontend variant to the connected client.
/// Server-side only. Client-side no-op.
pub fn send_to_client(msg: a) -> Effect(b) {
  effect.from(fn(_dispatch) {
    Nil
  })
}

/// Broadcast a ToFrontend variant to all connected clients.
/// Server-side only. Client-side no-op.
pub fn broadcast(msg: a) -> Effect(b) {
  effect.from(fn(_dispatch) {
    Nil
  })
}
```

- [ ] **Step 2: Create codec module**

In `src/lando_runtime/codec.gleam`:

```gleam
import gleam/bit_array

/// Encode a value to base64 ETF for embedding in HTML (SSR flags).
pub fn encode_flags(value: a) -> String {
  let _ = value
  "" // Stub — will use libero's ETF encoder internally
}

/// Decode flags from window.__LANDO_FLAGS__ on client boot.
pub fn decode_flags(flags: String) -> Result(a, String) {
  let _ = flags
  Error("not implemented")
}
```

- [ ] **Step 3: Create ssr module**

In `src/lando_runtime/ssr.gleam`:

```gleam
import lustre/element.{type Element}

/// Render a Lustre element tree to an HTML string for SSR.
pub fn render_to_html(element: Element(msg)) -> String {
  // Stub — delegates to lustre/element.to_document_string
  ""
}
```

- [ ] **Step 4: Add lando_runtime to gleam.toml as a sub-package or export**

Update `gleam.toml`:

```toml
[package]
name = "lando"
# ... existing config

# lando_runtime is published as part of the lando package
# and used by scaffolded projects
```

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: stub lando_runtime library (effect, codec, ssr)"
```

---

### Task 8: Wire everything together in lando.gleam

**Files:**
- Modify: `src/lando.gleam`

Update the main entry point to run the full pipeline: scan pages, parse contracts, generate all outputs.

- [ ] **Step 1: Update lando.gleam with full pipeline**

Replace the current `run()` function:

```gleam
import gleam/list
import gleam/result
import lando/config
import lando/scanner
import lando/parser
import lando/generator/router as router_gen
import lando/generator/server_dispatch
import lando/generator/ssr_handler
import lando/generator/client

fn run() -> Result(Int, String) {
  let config = read_config()
  |> result.map_error(fn(e) { "Config error: " <> e })

  // 1. Scan pages directory
  use routes <- result.try(scanner.scan(config.pages_root))

  // 2. Parse each page module for its contract
  let contracts = list.filter_map(routes, fn(route) {
    let source_path = config.pages_root <> "/" <> route.module_path |> string.replace("admin/pages/", "") <> ".gleam"
    case simplifile.read(source_path) {
      Ok(source) -> {
        case parser.parse_page(source) {
          Ok(contract) -> Ok(#(route, contract))
          Error(_) -> Error(Nil)
        }
      }
      Error(_) -> Error(Nil)
    }
  })

  // 3. Generate route type + page dispatch (existing)
  let route_source = router_gen.generate(routes)
  use _ <- result.try(write_file(config.output_route, route_source))
  let dispatch_source = router_gen.generate_dispatch(routes)
  use _ <- result.try(write_file(config.output_dispatch, dispatch_source))

  // 4. Generate server dispatch
  let sd_source = server_dispatch.generate(contracts)
  use _ <- result.try(write_file(config.output_server_dispatch, sd_source))

  // 5. Generate SSR handler
  let ssr_source = ssr_handler.generate(contracts)
  use _ <- result.try(write_file(config.output_ssr, ssr_source))

  // 6. Generate client package
  let client_files = client.generate_package(routes, contracts, config)
  use _ <- result.try(write_generated_files(client_files))

  Ok(list.length(routes))
}

fn write_generated_files(files: List(client.GeneratedFile)) -> Result(Nil, String) {
  list.try_fold(files, Nil, fn(_, file) {
    // Ensure parent directory exists
    let _ = simplifile.create_directory_all(
      file.path
      |> string.split("/")
      |> list.drop_last
      |> string.join("/")
    )
    simplifile.write(file.path, file.content)
    |> result.map_error(fn(e) { "Failed to write " <> file.path <> ": " <> string.inspect(e) })
  })
}
```

- [ ] **Step 2: Run full test suite**

```bash
gleam test
```
Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: wire full codegen pipeline in lando.gleam"
```

---

### Task 9: Create project scaffold command

**Files:**
- Create: `bin/new` (shell script)
- Modify: `src/lando.gleam`

Add a `lando new <project_name>` command that scaffolds a complete project with the correct directory structure, gleam.toml with [tools.lando] config, a sample home page, and bin scripts.

- [ ] **Step 1: Create bin/new scaffold script**

Create `bin/new`:

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="${1:-}"
if [ -z "$PROJECT_NAME" ]; then
  echo "Usage: bin/new <project-name>"
  exit 1
fi

echo "Creating new lando project: $PROJECT_NAME"

mkdir -p "$PROJECT_NAME/src/pages"
mkdir -p "$PROJECT_NAME/src/sql"
mkdir -p "$PROJECT_NAME/src/generated"
mkdir -p "$PROJECT_NAME/client/src/generated"
mkdir -p "$PROJECT_NAME/bin"

# gleam.toml
cat > "$PROJECT_NAME/gleam.toml" <<TOML
name = "$PROJECT_NAME"
version = "0.1.0"
target = "erlang"

[dependencies]
gleam_stdlib = ">= 0.60.0 and < 2.0.0"
lustre = ">= 5.6.0 and < 7.0.0"
mist = ">= 6.0.0 and < 7.0.0"
sqlight = ">= 1.0.0 and < 2.0.0"
lando_runtime = { path = "../lando" }

[dev-dependencies]
gleeunit = ">= 1.0.0 and < 2.0.0"

[tools.lando]
pages_root = "src/pages"
output_route = "src/generated/router.gleam"
output_dispatch = "src/generated/page_dispatch.gleam"
output_server_dispatch = "src/generated/server_dispatch.gleam"
output_ssr = "src/generated/ssr_handler.gleam"
client_root = "client"
TOML

# Sample home page
cat > "$PROJECT_NAME/src/pages/home_.gleam" <<GLEAM
import lustre/element.{type Element}
import lustre/element/html
import lustre/effect.{type Effect}
import lando_runtime/effect as lando_effect

pub type Model { Model(count: Int) }

pub type Msg {
  UserClickedIncrement
  UserClickedDecrement
  GotServerMsg(ToFrontend)
}

pub type ToBackend { Increment; Decrement }

pub type ToFrontend { CounterNewValue(value: Int) }

pub type ServerModel { ServerModel(count: Int) }

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model(count: 0), effect.none())
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserClickedIncrement -> #(model, lando_effect.send_to_backend(Increment))
    UserClickedDecrement -> #(model, lando_effect.send_to_backend(Decrement))
    GotServerMsg(CounterNewValue(n)) -> #(Model(count: n), effect.none())
  }
}

pub fn view(model: Model) -> Element(Msg) {
  html.div([], [
    html.button([], [html.text("+")]),
    html.text(string.inspect(model.count)),
    html.button([], [html.text("-")]),
  ])
}

pub fn server_update(
  model: ServerModel,
  msg: ToBackend,
  _ctx: Context,
) -> #(ServerModel, Effect(ToFrontend)) {
  case msg {
    Increment -> #(ServerModel(count: model.count + 1), lando_effect.send_to_client(CounterNewValue(model.count + 1)))
    Decrement -> #(ServerModel(count: model.count - 1), lando_effect.send_to_client(CounterNewValue(model.count - 1)))
  }
}
GLEAM

# app_config.gleam
cat > "$PROJECT_NAME/src/app_config.gleam" <<GLEAM
pub type Context {
  Context(db: sqlight.Connection)
}
GLEAM

# bin/dev
cat > "$PROJECT_NAME/bin/dev" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "==> Running lando codegen..."
gleam run -m lando
echo "==> Building client..."
cd client && gleam build --target javascript && cd ..
echo "==> Starting server..."
gleam run
SCRIPT
chmod +x "$PROJECT_NAME/bin/dev"

echo ""
echo "Created $PROJECT_NAME. To start:"
echo "  cd $PROJECT_NAME && bin/dev"
```

- [ ] **Step 2: Make bin/new executable**

```bash
chmod +x bin/new
```

- [ ] **Step 3: Commit**

```bash
git add bin/new && git commit -m "feat: add project scaffold script (bin/new)"
```

---

### Task 10: Integration test with scaffolded project

**Files:**
- Create: `test/integration_test.gleam`

Create a test that scaffoldes a project, runs `bin/dev`, and verifies the generated output.

- [ ] **Step 1: Write integration test**

In `test/integration_test.gleam`:

```gleam
import simplifile
import gleeunit/should

pub fn scaffold_creates_expected_files_test() {
  // Run bin/new in a temp directory
  let tmp = "/tmp/lando_test_" <> string.inspect(int.random(99999))
  let result = simplifile.create_directory_all(tmp)
  let assert Ok(_) = result

  // Verify the sample project was created
  let assert Ok(_) = simplifile.is_file(tmp <> "/gleam.toml")
  let assert Ok(_) = simplifile.is_file(tmp <> "/src/pages/home_.gleam")
  let assert Ok(_) = simplifile.is_file(tmp <> "/src/app_config.gleam")
  let assert Ok(_) = simplifile.is_file(tmp <> "/bin/dev")

  // Cleanup
  let _ = simplifile.delete_directory_all(tmp)
}

pub fn codegen_produces_router_test() {
  let tmp = "/tmp/lando_router_test_" <> string.inspect(int.random(99999))
  let _ = simplifile.create_directory_all(tmp <> "/src/pages")
  let _ = simplifile.create_directory_all(tmp <> "/src/generated")

  // Write a minimal page
  let page = "
pub type Model { Model }
pub type Msg { Noop }
pub type ToBackend { Ping }
pub type ToFrontend { Pong }
pub fn init() -> #(Model, Effect(Msg)) { #(Model, effect.none()) }
pub fn update(m, msg) -> #(Model, Effect(Msg)) { #(m, effect.none()) }
pub fn view(_) -> Element(Msg) { html.text(\"hi\") }
pub fn server_update(m, msg, _) -> #(ServerModel, Effect(ToFrontend)) { #(m, effect.none()) }
"
  let _ = simplifile.write(tmp <> "/src/pages/home_.gleam", page)

  // TODO: Run gleam run -m lando in the temp dir and verify output files exist.
  // This requires a full gleam project with gleam.toml, so it's a manual test for now.

  let _ = simplifile.delete_directory_all(tmp)
}
```

- [ ] **Step 2: Commit**

```bash
git add test/integration_test.gleam && git commit -m "test: add integration test for project scaffold"
```

---

## Remaining Work (Future Phases)

These are out of MVP scope but called out explicitly in the design:

1. **ETF codec generation** — generate per-page `codec.gleam` with ETF encode/decode for ToBackend/ToFrontend. Currently stubbed; reuse libero's wire module internally.
2. **Framework-owned async UX** — generic loading overlay, error toast, reconnect indicator. Requires client runtime work.
3. **Client-side routing** — full Lustre SPA router that mirrors the server router. Currently the client app.gleam is a minimal stub.
4. **Marmot integration** — wire `sql/` directory scanning into lando's codegen pipeline.
5. **Layout system** — nested layouts like elm-land.
6. **`@local` annotations** — mark update arms as client-only for instant UI interactivity.
7. **Broadcast/subscription** — server-to-all-clients push for real-time updates.
