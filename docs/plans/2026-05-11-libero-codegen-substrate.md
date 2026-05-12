# Libero Codegen Substrate Spec and Plan

Status: current draft
Date: 2026-05-11
Updated: 2026-05-12

## Summary

Rally already depends on Libero for handler scanning, type walking, dispatch
generation, wire modules, typed decoders, JSON contracts, and JSON codec support.
Rally also imports `libero/field_type` directly, then repeats some Glance parsing
and type resolution code that Libero owns in nearby form.

The JSON protocol work has landed. That removes the old reason to wait. The
remaining useful cleanup is narrower than the original plan: move shared Glance
type resolution into Libero first, then let Rally consume it. Generated-file and
formatter sharing should stay separate.

Rally should still own routes, pages, generated client app shape, SSR policy,
WebSocket lifecycle, auth policy, and runtime semantics. Libero should own the
reusable type analysis that feeds protocol codegen.

## Current Status

- JSON protocol support is implemented in Rally and Libero.
- Rally now generates `protocol_wire.gleam` and `protocol_wire.mjs` facades.
- Libero now has JSON contract and JSON codec modules.
- Rally still has its own page-contract type conversion.
- Libero scanner and walker still have separate resolver paths.
- Libero still direct-writes generated files in several places.
- Rally still writes generated files only when content changes.

So the resolver extraction is still relevant. The generated-file extraction is
only a follow-up candidate, and it should not be mixed into the resolver work.

## Current State

### Already Shared

Rally uses Libero for:

- `libero/field_type`: shared type IR for generated protocol values.
- Libero scanner and walker entry points from `src/rally.gleam`.
- Libero dispatch generation for server RPC.
- Libero atoms, wire module generation, and typed decoder generation.
- Libero JSON contract generation and JSON codec generation paths.
- Libero wire identity hashing for message-type RPC dispatch and auth routing.

This is a hard dependency. Moving nearby reusable helpers into Libero makes the
existing coupling more honest.

### Duplicated Or Near-Duplicated

Rally has its own `glance.Type -> FieldType` conversion in
`src/rally/parser.gleam`. Libero has similar conversion paths in
`src/libero/scanner.gleam` and `src/libero/walker.gleam`.

All three paths build or consume these Glance import maps:

- unqualified type name to module path
- module alias to module path
- imported type alias to original type name

Both projects run `gleam format` on generated source through a temp file:

- `libero/src/libero/format.gleam`
- `rally/src/rally/format.gleam`

Rally has a small generated-file model:

- `src/rally/generator/client.gleam`: `GeneratedFile(path, content)`
- `src/rally.gleam`: format `.gleam` files, write only when content changes

Libero now has more generated outputs because JSON contract and codec generation
landed, but it still does direct writes. Treat generated-file sharing as a
separate design, not part of this resolver pass.

### Important Differences

Rally and Libero do not handle unsupported Glance types the same way today.

Rally rejects function and hole types while parsing page contracts. Libero maps
them to `TypeVar("_fn")` and `TypeVar("_")` in scanner and walker paths so
later codegen or decoder safety checks can fail with Libero-owned context.

Libero walker also has behavior that scanner and Rally parser do not fully
share: it treats imported user types named `Result`, `Option`, `List`, `Dict`,
and other stdlib names as user types when a user import shadows the stdlib
type. This behavior must survive extraction.

Libero walker resolves local type aliases transparently while discovering type
graphs. Do not bury that rule inside the first public resolver unless scanner
and Rally parser are ready to share the same semantics. Keep local alias
resolution walker-owned for the first pass if needed.

Recent RPC fixes made endpoint `msg_type` identity a live Rally dependency.
For handler-as-contract RPCs, Libero's generated wire module can decode incoming
client messages tagged by the message type's wire hash, then normalize them back
to the `server_*` function tag. Rally's auth-aware HTTP and WS generators now use
the same `wire_identity.wire_identity(module_path, type_name, fields)` hash to
map those RPC messages back to the owning page. That means scanner output is no
longer just dispatch input: `msg_type`, param field order, and resolved
`FieldType` identity must stay exactly aligned with Libero's wire decode path.

## Type Identity Must Stay Canonical

Libero's type identity depends on canonical module paths. `FieldType.UserType`
stores `module_path`, `type_name`, and type arguments. That value feeds
`field_type.to_canonical_token`, then `wire_identity.canonical_signature`, then
the wire hash baked into generated encode/decode functions.

User namespacing is intent. If a user wants one shared type, they put it in a
shared module and import it. If they define two same-shaped types in two module
paths, those are two types. The tooling must not infer sharing.

This resolver must be an identity resolver. Unqualified source syntax is only
source syntax. The resolved `FieldType` must still carry the canonical module
path.

Required behavior:

- An unqualified imported type resolves through the import map to the imported
  module path.
- A local unqualified type resolves to `current_module`.
- An imported type alias resolves to the imported module path and the original
  type name.
- A qualified module alias resolves through the alias map to the full module
  path.
- Codegen may choose short aliases later for generated source, but `FieldType`
  identity must never use those aliases.
- Two user types with the same name and same fields but different module paths
  are different types.
- Structurally identical user types at different module paths are still
  different types.
- The resolver must fail on ambiguous imports instead of silently choosing the
  last binding.
- Imported user types that shadow stdlib names must remain user types.

Losing module-path identity here would reopen the same class of ETF and JSON
typed-value bugs Libero's wire identity work was built to close.

For RPC handlers with `msg_type`, losing identity also breaks auth routing.
Rally computes owning-page metadata from the same module path, type name, and
field list that Libero uses to emit the client-message decode clauses. Those
hashes must remain identical across Rally and Libero after resolver extraction.

## Proposed Libero Surface

### `libero/glance_type_resolver.gleam`

New cross-target module for Glance-to-FieldType resolution.

Public types:

```gleam
pub type UnsupportedTypePolicy {
  RejectUnsupported(path: String)
  PreserveUnsupported
}

pub opaque type TypeResolver {
  TypeResolver(
    unqualified: dict.Dict(String, TypeBinding),
    aliased: dict.Dict(String, String),
  )
}

type TypeBinding {
  TypeBinding(module_path: String, type_name: String)
}
```

Public functions:

```gleam
pub fn resolver_from_imports(
  imports: List(glance.Definition(glance.Import)),
) -> Result(TypeResolver, String)

pub fn type_to_field_type(
  type_: glance.Type,
  resolver: TypeResolver,
  current_module: String,
  policy: UnsupportedTypePolicy,
) -> Result(field_type.FieldType, String)
```

Expected behavior:

- Builtin type handling delegates to `field_type.builtin_field_type` only when
  the type is truly a stdlib type.
- Unqualified user types resolve through `resolver.unqualified` to canonical
  module paths, then fall back to `current_module`.
- Qualified user types resolve through `resolver.aliased`.
- Imported type aliases resolve through the original `type_name` stored in
  `TypeBinding`.
- `RejectUnsupported(path)` returns an error for function and hole types.
- `PreserveUnsupported` maps function and hole types to the existing Libero
  `TypeVar` sentinels.
- `TypeResolver` is opaque. Callers build it with `resolver_from_imports`, but
  cannot depend on the internal dict layout.
- `resolver_from_imports` returns an error if two imports bind the same
  unqualified type name to different modules or original type names.
- User imports that shadow stdlib names must resolve as `UserType`, not builtin
  field types.

Do not add a public `type_refs` function in the first pass. Libero's walker has
type-reference discovery needs, but the public shape is not clear enough yet.
If Phase 1 needs a shared helper for the walker, keep it private first and
promote it only after a second caller appears.

Do not move local type alias transparency into this module unless the exact
behavior is shared by scanner, walker, and Rally parser. If only walker needs
it, keep it in `libero/walker.gleam`.

### Formatting and Generated Files

Do not move this in the resolver pass.

Libero and Rally both format generated Gleam, but their temp-dir behavior and
warning behavior differ. Rally writes only changed files, while Libero still
does direct writes. JSON landing gives Libero more generated outputs, but it
does not by itself prove both projects want one shared writer.

Possible later module:

```gleam
pub type GeneratedFile {
  GeneratedFile(path: String, content: String)
}
```

Move only the data type first if Libero grows a local list-based generated-file
pipeline. Move write-if-changed only if Libero also wants that write behavior.

## Non-Goals

- Do not move Rally route scanning into Libero.
- Do not move Rally page contract types into Libero.
- Do not move Rally auth markers into Libero.
- Do not move Rally client package generation into Libero.
- Do not move WebSocket lifecycle into Libero.
- Do not make Marmot depend on Libero.
- Do not create a fourth package for this pass.
- Do not move formatter or writer behavior in the resolver pass.

The fourth package idea should wait until Marmot, Libero, and Rally all need the
same public API. Right now the pressure is mostly between Rally and Libero.

## Implementation Plan

### Task 0: Baseline Current Behavior

Purpose: prove the starting point before touching resolver code. Do this first
because scanner, walker, dispatch, and Rally auth now share wire-identity inputs.

Files:

- Read: `../libero/src/libero/scanner.gleam`
- Read: `../libero/src/libero/walker.gleam`
- Read: `../libero/src/libero/codegen_wire_erl.gleam`
- Read: `../libero/src/libero/codegen_dispatch.gleam`
- Read: `src/rally/parser.gleam`
- Read: `src/rally/generator/http_handler.gleam`
- Read: `src/rally/generator/ws_handler.gleam`

Steps:

- Run `cd /Users/daverapin/projects/opensource/libero && gleam test`.
- Run `cd /Users/daverapin/projects/opensource/rally && gleam test`.
- Note any failing tests before implementation. Do not explain them away.
- Confirm these facts in the code before editing:
  - Libero scanner owns `build_type_import_map`,
    `build_alias_resolution_map`, `build_type_alias_originals`, and
    `glance_type_to_field_type`.
  - Libero walker owns its own `TypeResolver`, stdlib-shadowing checks,
    `collect_type_refs`, and `field_type_of`.
  - Rally parser owns equivalent import-map helpers and a strict
    `glance_type_to_field_type`.
  - Rally HTTP and WS auth generators compute `msg_type` wire hashes from
    `endpoint.msg_type` and `endpoint.params`.
  - Libero wire generation computes the same `msg_type` hash when emitting
    `decode_client_msg`.

Commit: none.

### Task 1: Add Libero Resolver Tests First

Purpose: define the shared resolver contract before moving production code.

Files:

- Create: `../libero/test/libero/glance_type_resolver_test.gleam`
- Read: `../libero/src/libero/field_type.gleam`
- Read: `../libero/src/libero/wire_identity.gleam`

Test helper shape:

```gleam
fn parse_type(source: String, type_name: String) -> glance.Type {
  let assert Ok(ast) = glance.module(source)
  let assert Ok(def) =
    list.find(ast.custom_types, fn(def) { def.definition.name == type_name })
  let assert [variant] = def.definition.variants
  let assert [field] = variant.fields
  case field {
    glance.LabelledVariantField(item:, ..) -> item
    glance.UnlabelledVariantField(item:) -> item
  }
}

fn resolver(source: String) -> glance_type_resolver.TypeResolver {
  let assert Ok(ast) = glance.module(source)
  let assert Ok(resolver) =
    glance_type_resolver.resolver_from_imports(ast.imports)
  resolver
}
```

Required tests:

- Unqualified imported type:
  - Source imports `shared/item.{type Item}`.
  - Field `Item` resolves to `UserType("shared/item", "Item", [])`.
- Imported type alias:
  - Source imports `shared/item.{type Item as SharedItem}`.
  - Field `SharedItem` resolves to `UserType("shared/item", "Item", [])`.
- Qualified module alias:
  - Source imports `shared/item as item_types`.
  - Field `item_types.Item` resolves to `UserType("shared/item", "Item", [])`.
- Local user type:
  - Field `LocalThing` resolves to `UserType(current_module, "LocalThing", [])`.
- Builtins:
  - `Int`, `String`, `Bool`, `Float`, `BitArray`, `Nil`, `List(String)`,
    `Option(Int)`, `Result(Int, String)`, `Dict(String, Int)`, and tuple
    fields resolve to the matching `field_type.FieldType` values.
- Generic user type:
  - `Box(Item)` resolves to `UserType(current_module, "Box", [UserType(...)])`.
- Unsupported types:
  - With `RejectUnsupported("m.Model.handler")`, `fn() -> Nil` returns
    `Error("Unsupported function type in m.Model.handler")`.
  - With `RejectUnsupported("m.Model.value")`, `_` returns
    `Error("Unsupported hole type in m.Model.value")`.
  - With `PreserveUnsupported`, function and hole types become
    `TypeVar("_fn")` and `TypeVar("_")`.
- Stdlib shadowing:
  - `import shared/custom_result.{type Result}` plus field `Result` resolves to
    `UserType("shared/custom_result", "Result", [])`, not `ResultOf`.
  - Repeat for at least one container type such as `Option` or `List`.
- Ambiguous unqualified imports:
  - Two imports bind the same local type name to different modules.
  - `resolver_from_imports` returns `Error(...)`.
  - The error string names the local type and both modules.
- Canonical identity:
  - Two `UserType("a/types", "Thing", [])` and
    `UserType("b/types", "Thing", [])` values produce different
    `field_type.to_canonical_token` strings.
- Message-type hash inputs:
  - Resolve fields for a single-variant message type.
  - Compute `wire_identity.wire_identity(module_path, type_name, fields)`.
  - Assert the hash changes if the module path changes.
  - Assert the hash changes if field order changes.

Run: `cd /Users/daverapin/projects/opensource/libero && gleam test`.

Expected before implementation: test module fails to compile because
`libero/glance_type_resolver` does not exist.

Commit: none. This is an intentional red checkpoint. Task 1 and Task 2 are
committed together in Task 2 so the branch never records an unbuildable commit.

### Task 2: Implement `libero/glance_type_resolver`

Purpose: provide one tested import resolver and `glance.Type -> FieldType`
conversion path.

Files:

- Create: `../libero/src/libero/glance_type_resolver.gleam`
- Read or modify if needed: `../libero/src/libero/field_type.gleam`

Public API:

```gleam
pub type UnsupportedTypePolicy {
  RejectUnsupported(path: String)
  PreserveUnsupported
}

pub opaque type TypeResolver {
  TypeResolver(
    unqualified: dict.Dict(String, TypeBinding),
    aliased: dict.Dict(String, String),
  )
}

type TypeBinding {
  TypeBinding(module_path: String, type_name: String)
}

pub fn resolver_from_imports(
  imports: List(glance.Definition(glance.Import)),
) -> Result(TypeResolver, String)

pub fn type_to_field_type(
  type_: glance.Type,
  resolver: TypeResolver,
  current_module: String,
  policy: UnsupportedTypePolicy,
) -> Result(field_type.FieldType, String)
```

Implementation notes:

- Store original imported type names in the unqualified binding instead of a
  separate public-facing dict. That keeps the resolver opaque and prevents
  callers from mixing module and type-name state.
- Build `aliased` from explicit module aliases and default last segments.
- For unqualified imports:
  - Local name is `uq.alias` when present, otherwise `uq.name`.
  - Original name is always `uq.name`.
  - Binding is `TypeBinding(module_path: imp.module, type_name: original_name)`.
- If an import binds an already-seen local name:
  - Accept it only if module path and original type name match.
  - Return an error if either differs.
- For qualified types:
  - Resolve `module` through `aliased`.
  - Keep `name` as the type name.
  - Recurse through parameters.
- For unqualified named types:
  - Check whether the name is imported from a non-stdlib module before treating
    it as builtin.
  - Delegate to `field_type.builtin_field_type` only when the name is not
    shadowed by a user import.
  - Fall back to `UserType(current_module, name, args)` for local user types.
- For unsupported types:
  - `RejectUnsupported(path)` returns the exact Rally-compatible messages.
  - `PreserveUnsupported` returns the current Libero sentinels.

Run: `cd /Users/daverapin/projects/opensource/libero && gleam test`.

Expected after implementation: `glance_type_resolver_test` passes. Existing
scanner and walker tests still pass because production code has not moved yet.

Commit:

```sh
git -C /Users/daverapin/projects/opensource/libero add src/libero/glance_type_resolver.gleam test/libero/glance_type_resolver_test.gleam
git -C /Users/daverapin/projects/opensource/libero commit -m "Add shared Glance type resolver"
```

### Task 3: Move Libero Scanner Onto The Resolver

Purpose: make handler scanning use the shared resolver while preserving endpoint
shape, especially `msg_type` and params used for RPC hash routing.

Files:

- Modify: `../libero/src/libero/scanner.gleam`
- Modify: `../libero/src/libero/gen_error.gleam`
- Test: `../libero/test/libero/endpoint_dispatch_test.gleam`
- Test: `../libero/test/libero/codegen_wire_erl_test.gleam`

Error type:

Add a GenError variant:

```gleam
TypeResolutionFailed(path: String, message: String)
```

Render it with a boxed error titled `Failed to resolve Gleam type`.

Scanner migration:

- In `parse_endpoints`, build the resolver once after parsing the module.
- If `resolver_from_imports(parsed.imports)` fails, return
  `TypeResolutionFailed(path: file_path, message:)`.
- Replace the local `glance_type_to_field_type` calls with
  `glance_type_resolver.type_to_field_type(..., PreserveUnsupported)`.
- Because the resolver returns `Result`, do not silently drop endpoint fields.
  If a server function was selected as an endpoint and its type conversion
  fails, return a visible `GenError`.
- Error collection decision: keep scanner's current file-level collection
  model. `scan` collects one `GenError` per failing file and continues scanning
  other files. Within a single file, stop at the first resolver/type-conversion
  failure rather than collecting every endpoint failure in that file.
- Keep endpoint filtering for non-`server_` functions as `Nil`.
- Keep or temporarily retain public compatibility wrappers:
  - `build_type_import_map`
  - `build_alias_resolution_map`
  - `build_type_alias_originals`
  Existing callers can be deleted only after walker and Rally stop using them.

Required tests:

- Add a scanner-level test with:
  - `pub type ServerSetDarkMode { ServerSetDarkMode(enabled: Bool) }`
  - `pub fn server_set_dark_mode(msg: ServerSetDarkMode, server_context: ServerContext) -> Result(Nil, Nil)`
  - Assert endpoint has `msg_type: Some(#("...", "ServerSetDarkMode"))`.
  - Assert params are `[ #("enabled", BoolField) ]`.
- Add a scanner-level test where `ServerSetDarkMode` contains imported fields.
  Assert params preserve canonical imported module paths.
- Add a dispatch or wire test that computes the message hash from the endpoint
  and finds the same hash in generated `decode_client_msg`.
- Add a scanner error test for ambiguous imported type names. Assert scan
  returns `TypeResolutionFailed`, not an empty endpoint list.

Run: `cd /Users/daverapin/projects/opensource/libero && gleam test`.

Commit:

```sh
git -C /Users/daverapin/projects/opensource/libero add src/libero/scanner.gleam src/libero/gen_error.gleam test/libero
git -C /Users/daverapin/projects/opensource/libero commit -m "Use shared resolver in scanner"
```

### Task 4: Move Libero Walker Where Semantics Match

Purpose: remove walker duplication without losing walker-only behavior.

Files:

- Modify: `../libero/src/libero/walker.gleam`
- Test: `../libero/test/libero/walker_test.gleam`
- Test: `../libero/test/libero/wire_identity_test.gleam`

Migration boundaries:

- Replace walker's import resolver construction with
  `glance_type_resolver.resolver_from_imports`.
- Replace walker's `field_type_of` conversion with
  `glance_type_resolver.type_to_field_type(..., PreserveUnsupported)` only
  where local type alias transparency is not needed.
- Keep walker-owned `collect_type_refs` private.
- Keep local alias transparency in walker unless the public resolver explicitly
  receives a local alias map. Do not add that public argument in this pass.
- If resolver construction fails while walking a module, surface a `GenError`
  instead of continuing with an empty resolver.

Required tests:

- Existing mutual-recursion and float-field tests pass unchanged.
- Existing stdlib-shadowing test still proves imported `Result` is walked.
- Add or keep a test where local type alias fields still resolve to the alias
  target for discovered variants.
- Add a test where an ambiguous import in a walked module returns a visible
  resolver error.
- Add a test that two same-named types in different modules keep separate
  `DiscoveredType.module_path` values and distinct `wire_identity` signatures.

Run: `cd /Users/daverapin/projects/opensource/libero && gleam test`.

Rollback decision: if walker migration shows the shared resolver cannot preserve
walker-only semantics without adding local alias maps or type-reference APIs to
the public module, keep Task 3's scanner migration and stop the walker migration.
Do not revert the scanner if its tests pass. Instead, narrow this issue to
scanner plus Rally parser and write a follow-up plan for walker-specific
resolution.

Commit:

```sh
git -C /Users/daverapin/projects/opensource/libero add src/libero/walker.gleam test/libero/walker_test.gleam test/libero/wire_identity_test.gleam
git -C /Users/daverapin/projects/opensource/libero commit -m "Use shared resolver in walker"
```

### Task 5: Pin RPC Hash Routing Across Repos

Purpose: guard the bug class that prompted this update. Scanner, Libero wire
decode, Rally HTTP auth, and Rally WS auth must agree on message-type hashes.

Files:

- Test: `../libero/test/libero/codegen_wire_erl_test.gleam`
- Test: `../libero/test/libero/endpoint_dispatch_test.gleam`
- Test: `test/rally/http_auth_test.gleam`
- Test: `test/rally/ws_auth_test.gleam`

Libero tests:

- Build a `HandlerEndpoint` with:
  - `msg_type: Some(#("admin/pages/settings", "ServerSetDarkMode"))`
  - params `[ #("enabled", BoolField) ]`
- Assert generated `decode_client_msg` accepts both:
  - `{'<hash>', F0}`
  - `{server_set_dark_mode, F0}`
- Assert both decode to `{server_set_dark_mode, F0}`.
- Assert `codegen_dispatch.generate(..., wire_module: Some(...))` decodes the
  wire message before calling `wire.variant_tag`.
- Expected hash policy: use one hardcoded literal in one regression test for
  `ServerSetDarkMode(enabled: Bool)` so hash algorithm drift is visible. Use
  computed hashes in the broader generated-output tests where the assertion is
  about both callers using the same inputs.

Rally tests:

- In HTTP auth generation, assert `handler_page_info` contains both:
  - `"server_set_dark_mode" -> Ok(PageAuthInfo(...))`
  - `"<hash>" -> Ok(PageAuthInfo(...))`
- In WS auth generation, assert the same two arms exist.
- Use a hardcoded expected hash in one test that mirrors the Libero regression.
  Use computed hashes in the two-page collision test so the test focuses on
  routing to the correct page variants.
- Add one test with two pages whose message types have the same constructor name
  and fields but different module paths. Assert the generated auth map contains
  two distinct hash arms that point to the correct page variants.

Run this task before deleting Rally's local parser helpers. If these tests catch
a cross-repo hash mismatch, fix the scanner/resolver contract while the Rally
parser migration is still untouched.

Run:

```sh
cd /Users/daverapin/projects/opensource/libero && gleam test
cd /Users/daverapin/projects/opensource/rally && gleam test
```

Commit:

```sh
git -C /Users/daverapin/projects/opensource/libero add test/libero/codegen_wire_erl_test.gleam test/libero/endpoint_dispatch_test.gleam
git -C /Users/daverapin/projects/opensource/libero commit -m "Pin message-type RPC wire hashes"
git add test/rally/http_auth_test.gleam test/rally/ws_auth_test.gleam
git commit -m "Pin RPC auth hash routing"
```

### Task 6: Switch Rally Parser To Libero Resolver

Purpose: remove Rally's duplicate `glance.Type -> FieldType` logic while keeping
page and client-context parsing Rally-owned.

Dependency note: Rally currently depends on Libero through a local path
dependency, so Tasks 1-4 are available to Rally without publishing a Libero
release. If that changes before execution, publish or otherwise pin the Libero
version before starting this task.

Files:

- Modify: `src/rally/parser.gleam`
- Test: `test/rally/parser_test.gleam`
- Test: `test/rally/client_context_parser_test.gleam`

Migration:

- Import `libero/glance_type_resolver`.
- In `parse_page`, call `resolver_from_imports(ast.imports)` once.
- In `parse_client_context`, call `resolver_from_imports(ast.imports)` once.
- Pass the resolver into `extract_variants`.
- Replace `glance_type_to_field_type` with
  `glance_type_resolver.type_to_field_type(..., RejectUnsupported(path))`.
- Delete Rally-local helper functions:
  - `build_type_import_map`
  - `build_alias_resolution_map`
  - `build_type_alias_originals`
  - `resolve_named_type`
  - `glance_type_to_field_type`
- Keep Rally-specific logic in place:
  - page contract extraction
  - function presence
  - source spans
  - auth markers
  - client context contracts
  - `update_returns_client_context_msg`

Required tests:

- Existing unsupported function and hole tests keep exact messages:

```gleam
"Unsupported function type in test/page.Model.handler"
"Unsupported hole type in test/page.Model.value"
```

- Add page parser test for imported aliased type:
  - `import shared/item.{type Item as SharedItem}`
  - `Model(item: SharedItem)`
  - Assert field type is `UserType("shared/item", "Item", [])`.
- Add page parser test for qualified module alias:
  - `import shared/item as item_types`
  - `Model(item: item_types.Item)`
  - Assert canonical module path is `shared/item`.
- Add page parser test for stdlib shadowing:
  - `import shared/custom_result.{type Result}`
  - `Model(result: Result)`
  - Assert `UserType("shared/custom_result", "Result", [])`.
- Add client context parser test for imported type alias to avoid only testing
  page parsing.
- Add parser test for ambiguous unqualified imports returning `Error(message)`.
- Re-run the Task 5 Rally hash-routing tests after the parser migration.

Run: `cd /Users/daverapin/projects/opensource/rally && gleam test`.

Commit:

```sh
git add src/rally/parser.gleam test/rally/parser_test.gleam test/rally/client_context_parser_test.gleam
git commit -m "Use Libero resolver in Rally parser"
```

### Task 7: Clean Up Compatibility Wrappers And Update Docs

Purpose: make the new boundary discoverable after implementation.

Files:

- Modify: `../libero/src/libero/scanner.gleam`
- Modify: `llms.txt`
- Optional modify: `docs/libero-boundary-spec.md`

Cleanup:

- Delete scanner compatibility wrappers if no callers remain:
  - `build_type_import_map`
  - `build_alias_resolution_map`
  - `build_type_alias_originals`
- If a public caller remains, keep only the wrapper it uses and add a comment
  naming that caller.

Updates:

- Say Rally consumes `libero/glance_type_resolver` for page and client-context
  type conversion.
- Say Rally consumes `libero/wire_identity` for message-type RPC auth routing.
- Keep auth policy ownership in Rally.
- Keep Libero ownership of wire identity, dispatch decode, protocol encode, and
  typed codecs.
- Mention that `HandlerEndpoint.msg_type` and params are part of the contract
  between scanner, wire decode, and Rally auth routing.

Run:

```sh
cd /Users/daverapin/projects/opensource/libero && gleam test
cd /Users/daverapin/projects/opensource/rally && gleam test
```

Commit:

```sh
git -C /Users/daverapin/projects/opensource/libero add src/libero/scanner.gleam
git -C /Users/daverapin/projects/opensource/libero commit -m "Remove obsolete scanner resolver helpers"
git add llms.txt docs/libero-boundary-spec.md
git commit -m "Update docs: Shared resolver boundary"
```

### Task 8: Final Verification

Purpose: prove both repos are ready after the split.

Commands:

```sh
cd /Users/daverapin/projects/opensource/libero && gleam test
cd /Users/daverapin/projects/opensource/rally && gleam test
cd /Users/daverapin/projects/opensource/rally && test/js/run_auth_error_test.sh
cd /Users/daverapin/projects/opensource/rally && bin/check-auth-codegen
```

Inspect generated output if any snapshot changed:

- `test/birdie_snapshots/http_handler_with_auth_required.accepted`
- `test/birdie_snapshots/http_handler_with_auth_and_authorize.accepted`
- `test/birdie_snapshots/client_transport_gleam.accepted`
- fixture generated protocol files under `fixtures/json_protocol/src/generated`.

Acceptance:

- Libero tests pass.
- Rally tests pass.
- JS auth error test passes.
- Auth codegen check passes.
- Rally parser no longer owns duplicate import-map helpers.
- Libero scanner and walker use one resolver path where semantics match.
- Message-type RPC dispatch and auth routing still agree on the same
  `wire_identity` hash inputs.
- No writer or formatter abstraction was moved in this issue.

### Follow-Up: Reassess Generated Files Separately

This phase is intentionally separate from resolver extraction.

Files to inspect:

- `src/rally/generator/client.gleam`
- `src/rally.gleam`
- `src/rally/generator/codec.gleam`
- `../libero/src/libero.gleam`
- `../libero/src/libero/format.gleam`

Decision checklist:

- Does Libero have at least two local call sites that want
  `List(GeneratedFile)` instead of direct writes?
- Does Libero want write-if-changed semantics?
- Can formatter warning behavior match in both projects?
- Would a shared writer need project-specific flags?

If the answer is mixed, do nothing. If the answer is clearly yes, write a new
small plan just for `libero/generated_file.gleam`.

## Future Considerations

### Source Helpers

This is a parking lot, not part of the resolver implementation pass.

Possible future Libero module:

```gleam
libero/source.gleam
```

- Move `walk_directory` only if Libero can keep its current error type without
  forcing that type onto Rally.
- Move module path derivation if both projects can use the same rule.
- Move public function source extraction only after another Libero-owned caller
  needs source-span extraction. Rally alone is not enough reason.

Proceed only if at least two callers need the same helper and the function name
stays about source handling, not Rally concepts.

## Risks

- A shared resolver can blur strict Rally parser errors and Libero codegen-time
  or decoder-time errors. The policy argument exists to prevent that.
- A naive builtin check can break user-defined types named `Result`, `Option`,
  `List`, or `Dict`.
- Scanner currently has infallible resolver assumptions. Adding ambiguous import
  errors requires visible error plumbing.
- Rally auth routing now depends on Libero wire identity for message-type RPCs.
  If resolver extraction changes `msg_type`, param field order, or canonical
  `FieldType` identity, HTTP and WS auth can route an RPC to the wrong page or
  reject a valid RPC.
- Moving writer or formatter code in the same pass can create unrelated churn.
- If `libero/glance_type_resolver` becomes a dumping ground for Rally page
  parsing, the boundary is wrong. Keep it about Glance type resolution:
  imports, aliases, builtin types, user type references, and unsupported type
  policy. Page contracts, route semantics, function-source extraction, auth
  markers, and client context conventions stay in Rally.
- An opaque resolver can still grow too much hidden behavior. Keep the
  constructor small and test resolution cases at the module boundary.

## Test Plan

- `cd /Users/daverapin/projects/opensource/libero && gleam test`
- `cd /Users/daverapin/projects/opensource/rally && gleam test`
- Add focused tests before each extraction step.
- Keep existing Rally parser tests as regression coverage for error text.
- Add explicit Rally assertions for unsupported function and hole type messages.
- Add Libero resolver tests that pin canonical module-path identity for
  unqualified and aliased types.
- Add Libero and Rally tests that pin message-type RPC wire hashes for
  auth/dispatch routing.
- Add Libero resolver tests that pin stdlib-shadowing behavior.
- Add Libero resolver tests that pin ambiguous unqualified imports as errors.
- Keep Libero scanner and walker tests as regression coverage for preserved
  unsupported-type behavior.

## Acceptance Criteria

- Rally uses Libero for Glance-to-FieldType conversion.
- Rally keeps owning page and client context contract extraction.
- Libero scanner and walker use one resolver path where semantics match.
- Walker keeps any resolver-adjacent behavior that is only walker-specific.
- Libero wire identity remains based on canonical module paths, never generated
  import aliases or short names.
- Message-type RPC dispatch and auth routing still agree on the same
  `wire_identity` hash inputs.
- JSON and ETF protocol tests still pass.
- No new package exists.
- `llms.txt` reflects the new state after implementation.
- Formatting and generated-file abstractions remain deferred unless a later plan
  proves they are worth sharing.
