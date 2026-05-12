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

## What Changed Since This Was Written

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
    unqualified: dict.Dict(String, String),
    aliased: dict.Dict(String, String),
    original_names: dict.Dict(String, String),
  )
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
- Imported type aliases resolve through `resolver.original_names`.
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

### Phase 1: Add Libero Type Resolver

Files:

- Create: `../libero/src/libero/glance_type_resolver.gleam`
- Test: `../libero/test/libero/glance_type_resolver_test.gleam`
- Read or modify if needed: `../libero/src/libero/field_type.gleam`
- Modify: `../libero/src/libero/scanner.gleam`
- Modify: `../libero/src/libero/walker.gleam`
- Modify if error plumbing is needed: `../libero/src/libero/gen_error.gleam`
- Test: `../libero/test/libero/walker_test.gleam`
- Test: `../libero/test/libero/wire_identity_test.gleam`

Steps:

- Add resolver tests that cover unqualified imports, module aliases, imported
  type aliases, local user types, builtin types, tuple types, generic user
  types, function types, and hole types.
- Add stdlib-shadowing tests where `import shared/custom_result.{type Result}`
  resolves bare `Result` as `UserType("shared/custom_result", "Result", [])`.
- Add identity regression tests that assert resolved `UserType` values keep full
  module paths for unqualified imports and qualified aliases.
- Add a test for two same-named types from different modules flowing through
  `field_type.to_canonical_token` or `wire_identity.canonical_signature` with
  different canonical identities.
- Add a test for two structurally identical user types at different module paths
  and assert they remain distinct identities.
- Add a test where imports bind the same unqualified type name to two different
  modules and assert `resolver_from_imports` returns an error.
- Implement `TypeResolver`, `resolver_from_imports`, and `type_to_field_type`.
- Make `TypeResolver` opaque so callers cannot depend on its internal dicts.
- Use `RejectUnsupported(path)` in tests that need strict behavior.
- Use `PreserveUnsupported` for Libero scanner and walker behavior so existing
  Libero semantics do not change during extraction.
- Update scanner to call `resolver_from_imports`. If resolver construction can
  fail, surface that as a Libero `GenError` instead of dropping the endpoint.
- Replace scanner import-map helpers with calls to `glance_type_resolver`, or
  leave compatibility wrappers that delegate to the new module if public callers
  still use them.
- Replace walker resolver construction and field-type conversion with calls to
  `glance_type_resolver` where the behavior matches.
- Keep walker-owned type-reference discovery private.
- Keep walker-owned local type alias transparency private unless scanner and
  Rally parser adopt the same rule in this pass.
- Run `cd ../libero && gleam test`.

Acceptance:

- Libero tests pass.
- Existing Libero public behavior for function and hole types stays the same.
- Scanner and walker no longer each own separate import-map construction.
- Resolved `UserType` values preserve canonical `module_path` and `type_name`
  identity for imported, local, aliased, and qualified types.
- Imported user types that shadow stdlib names remain user types.
- Structurally identical user types at different module paths remain distinct.
- Ambiguous unqualified imports fail during resolver construction instead of
  silently choosing one binding.
- Scanner resolver failures produce visible generation errors.
- No public `type_refs` function exists unless Phase 1 finds a second real
  caller.

### Phase 2: Switch Rally Parser To Libero Resolver

Files:

- Modify: `src/rally/parser.gleam`
- Test: `test/rally/parser_test.gleam`
- Test: `test/rally/client_context_parser_test.gleam`
- Modify: `llms.txt`

Steps:

- Replace Rally's local import-map helpers with
  `libero/glance_type_resolver.resolver_from_imports`.
- Replace Rally's local `glance_type_to_field_type` with
  `libero/glance_type_resolver.type_to_field_type`.
- Pass `RejectUnsupported(path)` so Rally keeps rejecting function and hole
  types in page contracts.
- Preserve Rally-specific extraction of page contracts, function presence,
  source spans, auth markers, and client context contracts in Rally.
- Keep or add parser assertions that exact unsupported type errors are
  preserved:

```gleam
parser.parse_page(source_with_function_field, module_path: "test/page")
|> should.equal(Error("Unsupported function type in test/page.Model.handler"))

parser.parse_page(source_with_hole_field, module_path: "test/page")
|> should.equal(Error("Unsupported hole type in test/page.Model.value"))
```

- Add parser coverage for imported user types that shadow stdlib names if Rally
  page contracts can contain those types.
- Add parser coverage for ambiguous imports returning an error rather than a
  silently chosen binding.
- Update `llms.txt` to say Rally consumes Libero's shared Glance type resolver.
- Run `cd /Users/daverapin/projects/opensource/rally && gleam test`.

Acceptance:

- Rally parser tests pass.
- Rally no longer owns `build_type_import_map`,
  `build_alias_resolution_map`, or `build_type_alias_originals`.
- Rally's unsupported function and hole type errors keep the same messages.
- Rally page and client context contract extraction stays Rally-owned.
- `llms.txt` reflects the new boundary.

### Phase 3: Reassess Generated Files Separately

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
- JSON and ETF protocol tests still pass.
- No new package exists.
- `llms.txt` reflects the new state after implementation.
- Formatting and generated-file abstractions remain deferred unless a later plan
  proves they are worth sharing.
