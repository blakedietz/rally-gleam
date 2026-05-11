# Libero Codegen Substrate Spec and Plan

Status: draft
Date: 2026-05-11

## Summary

Rally already depends on Libero for handler scanning, type walking, dispatch
generation, wire modules, and typed decoders. Rally also imports
`libero/field_type` directly, then repeats some Glance parsing and type
resolution code that Libero already owns in nearby form.

The next good cleanup is to move shared Gleam source-analysis and generated-file
support into Libero, then let Rally consume it. This should happen after the
current JSON protocol work lands, because JSON may change which Libero-owned
surfaces Rally should call.

The goal is modest: make Libero the owner of reusable codegen plumbing that
already serves both projects. Rally should still own routes, pages, generated
client app shape, SSR policy, WebSocket lifecycle, and Rally runtime semantics.

## Current State

### Already Shared

Rally uses Libero for:

- `libero/field_type`: shared type IR for generated protocol values.
- Libero scanner and walker entry points from `src/rally.gleam`.
- Libero dispatch generation for server RPC.
- Libero atoms, wire module generation, and typed decoder generation.

This is a hard dependency, so moving nearby reusable helpers into Libero does
not add a new coupling. It makes the existing coupling more honest.

### Duplicated Or Near-Duplicated

Rally has its own `glance.Type -> FieldType` conversion in
`src/rally/parser.gleam`. Libero has similar conversion paths in
`src/libero/scanner.gleam` and `src/libero/walker.gleam`.

Both projects build these Glance import maps:

- unqualified type name to module path
- module alias to module path
- imported type alias to original type name

Both projects run `gleam format` on generated source through a temp file:

- `libero/src/libero/format.gleam`
- `rally/src/rally/format.gleam`

Rally has a small generated-file model:

- `rally/generator/client.gleam`: `GeneratedFile(path, content)`
- `rally.gleam`: format `.gleam` files, write only when content changes

That model is useful beyond Rally, but it should move only after Libero has a
second local use for it.

### Important Difference

Rally and Libero do not handle unsupported Glance types the same way today.

Rally rejects function and hole types while parsing page contracts. Libero maps
them to `TypeVar("_fn")` and `TypeVar("_")` in some paths so later decoder code
can fail with a clearer runtime message.

This is the main reason the extraction should introduce a small policy argument
rather than moving one function wholesale.

### Type Identity Must Stay Canonical

Libero's ETF type identity depends on canonical module paths. `FieldType.UserType`
stores `module_path`, `type_name`, and type arguments. That value feeds
`field_type.to_canonical_token`, then `wire_identity.canonical_signature`, then
the wire hash baked into generated encode/decode functions.

User namespacing is intent. If a user wants one shared type, they put it in a
shared module and import it. If they define two same-shaped types in two module
paths, those are two types. The tooling must not infer sharing.

This resolver must be an identity resolver, not a display-name resolver.
Unqualified source syntax is only source syntax. The resolved `FieldType` must
still carry the canonical module path.

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
  are different types. The resolver must preserve that distinction instead of
  deduplicating by shape or short name.
- The resolver must never silently choose one of two ambiguous user types. If
  Glance can surface ambiguous imports, preserve that failure. If the ambiguity
  is represented in the import list, return an error rather than guessing.

This is non-negotiable. Losing module-path identity here would reopen the same
class of ETF bugs Libero's wire identity work was built to close.

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

- Builtin type handling delegates to `field_type.builtin_field_type`.
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
  unqualified type name to different modules or original type names. Gleam may
  also reject this, but codegen should fail closed when parsing source directly.

Do not add a public `type_refs` function in the first pass. Libero's walker has
type-reference discovery needs, but the public shape is not clear enough yet.
If the Phase 1 implementation needs a shared helper for the walker, keep it
private first and promote it only after a second caller appears.

### Formatting and Generated Files

Do not move this first.

Libero and Rally both format generated Gleam, but their temp-dir behavior and
warning behavior differ. Rally also writes only changed files, while Libero does
some direct writes. Moving this too early could make the JSON work noisier.

After JSON lands, revisit a small `libero/generated_file.gleam`:

```gleam
pub type GeneratedFile {
  GeneratedFile(path: String, content: String)
}
```

The write-if-changed function may stay in Rally if Libero does not need it.

## Non-Goals

- Do not move Rally route scanning into Libero.
- Do not move Rally page contract types into Libero.
- Do not move Rally client package generation into Libero.
- Do not make Marmot depend on Libero.
- Do not create a fourth package for this pass.

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

Steps:

- Add tests that cover unqualified imports, module aliases, imported type
  aliases, local user types, builtin types, tuple types, generic user types,
  function types, and hole types.
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
- Replace scanner import-map helpers with calls to `glance_type_resolver`.
- Replace walker resolver construction and field-type conversion with calls to
  `glance_type_resolver` where the behavior matches.
- Run `cd ../libero && gleam test`.

Acceptance:

- Libero tests pass.
- Existing Libero public behavior for function and hole types stays the same.
- Scanner and walker no longer each own separate import-map construction.
- Resolved `UserType` values preserve canonical `module_path` and `type_name`
  identity for imported, local, aliased, and qualified types.
- Structurally identical user types at different module paths remain distinct.
- Ambiguous unqualified imports fail during resolver construction instead of
  silently choosing one binding.
- No public `type_refs` function exists unless Phase 1 finds a second real
  caller.

### Phase 2: Switch Rally Parser To Libero Resolver

Files:

- Modify: `src/rally/parser.gleam`
- Test: `test/rally/parser_test.gleam`
- Test: `test/rally/client_context_parser_test.gleam`

Steps:

- Replace Rally's local import-map helpers with
  `libero/glance_type_resolver.resolver_from_imports`.
- Replace Rally's local `glance_type_to_field_type` with
  `libero/glance_type_resolver.type_to_field_type`.
- Pass `RejectUnsupported(path)` so Rally keeps rejecting function and hole
  types in page contracts.
- Keep Rally-specific extraction of page contracts, function presence, source
  spans, auth markers, and client context contracts in Rally.
- Add or keep parser assertions that exact unsupported type errors are
  preserved:

```gleam
parser.parse_page(source_with_function_field, module_path: "test/page")
|> should.equal(Error("Unsupported function type in test/page.Model.handler"))

parser.parse_page(source_with_hole_field, module_path: "test/page")
|> should.equal(Error("Unsupported hole type in test/page.Model.value"))
```

- Run `cd /Users/daverapin/projects/opensource/rally && gleam test`.

Acceptance:

- Rally parser tests still pass.
- Rally no longer has `build_type_import_map`,
  `build_alias_resolution_map`, or `build_type_alias_originals`.
- Rally's unsupported function and hole type errors keep the same messages.

## Future Considerations

### Source Helpers

This is a parking lot, not part of the first implementation pass.

Possible future Libero module:

```gleam
libero/source.gleam
```

- Move `walk_directory` only if Libero can keep its current error type without
  forcing that type onto Rally.
- Move module path derivation if both projects can use the same rule.
- Move `public_function_source` only after another Libero-owned caller needs
  source-span extraction. Rally alone is not enough reason.

Proceed only if at least two callers need the same helper and the function name
stays about source handling, not Rally concepts.

### Generated File Support

Possible files:

- Possible create: `../libero/src/libero/generated_file.gleam`
- Possible modify: `src/rally/generator/client.gleam`
- Possible modify: `src/rally.gleam`
- Possible modify: `../libero/src/libero.gleam`

Steps:

- Wait until JSON protocol work settles.
- Check whether Libero has multiple generated outputs that would benefit from a
  `GeneratedFile` list.
- If yes, move only the data type first.
- Move write-if-changed only if Libero also wants the same write semantics.
- Keep formatting separate unless the temp-dir and warning behavior can match.

Acceptance:

- Generated outputs remain stable.
- Rally and Libero do not get a shared writer with project-specific flags baked
  into it.
- Formatting warnings remain understandable in both projects.

## Risks

- A shared resolver can accidentally blur strict Rally parser errors and Libero
  decoder-runtime errors. The policy argument exists to prevent that.
- Moving writer or formatter code too early can create churn during JSON work.
- If `libero/glance_type_resolver` becomes a dumping ground for Rally page
  parsing, the boundary is wrong. Keep it about Glance type resolution only:
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
- Add Libero resolver tests that pin ambiguous unqualified imports as errors.
- Keep Libero scanner and walker tests as regression coverage for preserved
  unsupported-type behavior.

## Acceptance Criteria

- Rally uses Libero for Glance-to-FieldType conversion.
- Rally keeps owning page and client context contract extraction.
- Libero scanner and walker use one resolver path.
- Libero wire identity remains based on canonical module paths, never generated
  import aliases or short names.
- No new package exists.
- Formatting and generated-file abstractions remain deferred unless JSON work
  proves they are worth sharing.
