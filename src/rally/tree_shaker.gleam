import glance
import gleam/list
import gleam/option.{None, Some}
import gleam/set.{type Set}
import gleam/string

/// Extract client-safe source code from a page module.
/// Removes server_* functions, load, and anything only reachable from server code.
/// server_symbols: known server-only type names (e.g. "ServerContext", handler message types)
pub fn shake(
  source: String,
  server_symbols server_symbols: List(String),
) -> String {
  let server_set = set.from_list(server_symbols)

  case glance.module(source) {
    Error(_) -> source
    Ok(ast) -> {
      // Pass 1: identify server-only functions
      let server_fns =
        ast.functions
        |> list.filter_map(fn(def) {
          let function = def.definition
          case is_server_function(function, server_set) {
            True -> Ok(function.name)
            False -> Error(Nil)
          }
        })
        |> set.from_list

      // Pass 2: walk from client roots, collect reachable private functions
      let client_pub_fns =
        ast.functions
        |> list.filter(fn(def) {
          let function = def.definition
          function.publicity == glance.Public
          && !set.contains(server_fns, function.name)
        })

      let reachable_private =
        collect_reachable_private_fns(ast, client_pub_fns, server_fns)

      let all_client_fn_names =
        list.map(client_pub_fns, fn(def) { def.definition.name })
        |> set.from_list
        |> set.union(reachable_private)

      // Collect all symbols referenced by client code (for import filtering)
      let client_refs =
        collect_all_client_refs(ast, all_client_fn_names, server_set)

      // Reconstruct source with only client-safe parts
      let client_imports = filter_imports(ast.imports, server_set, client_refs)
      let client_types = filter_types(ast.custom_types, server_set, client_refs)
      let client_type_aliases =
        filter_type_aliases(ast.type_aliases, server_set, client_refs)
      let client_constants = filter_constants(ast.constants, client_refs)
      let client_functions =
        extract_client_functions(ast, all_client_fn_names, source)

      let import_lines = list.map(client_imports, render_import)
      let type_lines =
        list.map(client_types, fn(ct) {
          extract_span_source(source, ct.definition.location)
        })
      let type_alias_lines =
        list.map(client_type_aliases, fn(ta) {
          extract_span_source(source, ta.definition.location)
        })
      let const_lines =
        list.map(client_constants, fn(c) {
          extract_span_source(source, c.definition.location)
        })

      string.join(
        list.flatten([
          import_lines,
          type_lines,
          type_alias_lines,
          const_lines,
          client_functions,
        ]),
        "\n\n",
      )
      <> "\n"
    }
  }
}

/// A function is server-only if:
/// - its name starts with "server_"
/// - its name is "load"
/// - any parameter type references a server symbol
fn is_server_function(f: glance.Function, server_symbols: Set(String)) -> Bool {
  string.starts_with(f.name, "server_")
  || f.name == "load"
  || list.any(f.parameters, fn(param) {
    case param.type_ {
      Some(t) -> type_references_server_symbol(t, server_symbols)
      None -> False
    }
  })
}

fn type_references_server_symbol(
  t: glance.Type,
  server_symbols: Set(String),
) -> Bool {
  case t {
    glance.NamedType(name:, parameters:, ..) ->
      set.contains(server_symbols, name)
      || list.any(parameters, fn(p) {
        type_references_server_symbol(p, server_symbols)
      })
    glance.TupleType(elements:, ..) ->
      list.any(elements, fn(e) {
        type_references_server_symbol(e, server_symbols)
      })
    glance.FunctionType(parameters:, return:, ..) ->
      list.any(parameters, fn(p) {
        type_references_server_symbol(p, server_symbols)
      })
      || type_references_server_symbol(return, server_symbols)
    glance.VariableType(..) -> False
    glance.HoleType(..) -> False
  }
}

// -- Pass 2: reachability from client roots --

fn collect_reachable_private_fns(
  ast: glance.Module,
  client_fns: List(glance.Definition(glance.Function)),
  server_fns: Set(String),
) -> Set(String) {
  let private_fns =
    ast.functions
    |> list.filter(fn(def) {
      let function = def.definition
      function.publicity != glance.Public
      && !set.contains(server_fns, function.name)
    })

  let private_fn_names =
    list.map(private_fns, fn(def) { def.definition.name }) |> set.from_list

  let initial =
    client_fns
    |> list.flat_map(fn(def) { extract_fn_references(def.definition) })
    |> set.from_list
    |> set.intersection(private_fn_names)

  expand_reachable(initial, private_fns, private_fn_names, initial)
}

fn expand_reachable(
  frontier: Set(String),
  private_fns: List(glance.Definition(glance.Function)),
  all_private: Set(String),
  visited: Set(String),
) -> Set(String) {
  case set.is_empty(frontier) {
    True -> visited
    False -> {
      let new_refs =
        private_fns
        |> list.filter(fn(def) { set.contains(frontier, def.definition.name) })
        |> list.flat_map(fn(def) { extract_fn_references(def.definition) })
        |> set.from_list
        |> set.intersection(all_private)
        |> set.difference(visited)

      expand_reachable(
        new_refs,
        private_fns,
        all_private,
        set.union(visited, new_refs),
      )
    }
  }
}

// -- Expression walking --

fn extract_fn_references(f: glance.Function) -> List(String) {
  f.body
  |> list.flat_map(extract_statement_refs)
}

fn extract_statement_refs(stmt: glance.Statement) -> List(String) {
  case stmt {
    glance.Use(_, _, expr) -> extract_expr_refs(expr)
    glance.Assignment(value: expr, ..) -> extract_expr_refs(expr)
    glance.Assert(expression: expr, ..) -> extract_expr_refs(expr)
    glance.Expression(expr) -> extract_expr_refs(expr)
  }
}

fn extract_expr_refs(expr: glance.Expression) -> List(String) {
  case expr {
    glance.Variable(name:, ..) -> [name]
    glance.Call(function:, arguments:, ..) -> {
      list.append(
        extract_expr_refs(function),
        list.flat_map(arguments, fn(a) {
          case a {
            glance.LabelledField(item: v, ..) -> extract_expr_refs(v)
            glance.ShorthandField(..) -> []
            glance.UnlabelledField(item: v) -> extract_expr_refs(v)
          }
        }),
      )
    }
    glance.Fn(body:, ..) -> list.flat_map(body, extract_statement_refs)
    glance.Block(statements:, ..) ->
      list.flat_map(statements, extract_statement_refs)
    glance.Case(subjects:, clauses:, ..) -> {
      list.append(
        list.flat_map(subjects, extract_expr_refs),
        list.flat_map(clauses, fn(c: glance.Clause) {
          list.flatten([
            list.flat_map(c.patterns, fn(patterns) {
              list.flat_map(patterns, extract_pattern_refs)
            }),
            case c.guard {
              Some(guard) -> extract_expr_refs(guard)
              None -> []
            },
            extract_expr_refs(c.body),
          ])
        }),
      )
    }
    glance.Tuple(elements:, ..) -> list.flat_map(elements, extract_expr_refs)
    glance.List(elements:, rest:, ..) -> {
      list.append(list.flat_map(elements, extract_expr_refs), case rest {
        Some(r) -> extract_expr_refs(r)
        None -> []
      })
    }
    glance.RecordUpdate(record:, fields:, ..) -> {
      list.append(
        extract_expr_refs(record),
        list.flat_map(fields, fn(f) {
          case f.item {
            Some(v) -> extract_expr_refs(v)
            None -> []
          }
        }),
      )
    }
    glance.FieldAccess(container:, ..) -> extract_expr_refs(container)
    glance.BinaryOperator(left:, right:, ..) ->
      list.append(extract_expr_refs(left), extract_expr_refs(right))
    glance.NegateInt(value:, ..) -> extract_expr_refs(value)
    glance.NegateBool(value:, ..) -> extract_expr_refs(value)
    glance.Panic(message:, ..) ->
      case message {
        Some(v) -> extract_expr_refs(v)
        None -> []
      }
    glance.Todo(message:, ..) ->
      case message {
        Some(v) -> extract_expr_refs(v)
        None -> []
      }
    glance.TupleIndex(tuple:, ..) -> extract_expr_refs(tuple)
    glance.FnCapture(function:, arguments_before:, arguments_after:, ..) -> {
      list.flatten([
        extract_expr_refs(function),
        list.flat_map(arguments_before, fn(a) {
          case a {
            glance.LabelledField(item: v, ..) -> extract_expr_refs(v)
            glance.ShorthandField(..) -> []
            glance.UnlabelledField(item: v) -> extract_expr_refs(v)
          }
        }),
        list.flat_map(arguments_after, fn(a) {
          case a {
            glance.LabelledField(item: v, ..) -> extract_expr_refs(v)
            glance.ShorthandField(..) -> []
            glance.UnlabelledField(item: v) -> extract_expr_refs(v)
          }
        }),
      ])
    }
    glance.BitString(segments:, ..) ->
      list.flat_map(segments, fn(seg) { extract_expr_refs(seg.0) })
    glance.Echo(expression:, ..) ->
      case expression {
        Some(v) -> extract_expr_refs(v)
        None -> []
      }
    // Literals
    glance.Int(..) -> []
    glance.Float(..) -> []
    glance.String(..) -> []
  }
}

fn extract_pattern_refs(pattern: glance.Pattern) -> List(String) {
  case pattern {
    glance.PatternVariant(module:, constructor:, arguments:, ..) -> {
      let module_refs = case module {
        Some(module) -> [module]
        None -> []
      }
      list.flatten([
        [constructor],
        module_refs,
        list.flat_map(arguments, fn(arg) {
          case arg {
            glance.LabelledField(item: p, ..) -> extract_pattern_refs(p)
            glance.ShorthandField(..) -> []
            glance.UnlabelledField(item: p) -> extract_pattern_refs(p)
          }
        }),
      ])
    }
    glance.PatternTuple(elements:, ..) ->
      list.flat_map(elements, extract_pattern_refs)
    glance.PatternList(elements:, tail:, ..) ->
      list.append(list.flat_map(elements, extract_pattern_refs), case tail {
        Some(tail) -> extract_pattern_refs(tail)
        None -> []
      })
    glance.PatternAssignment(pattern:, ..) -> extract_pattern_refs(pattern)
    glance.PatternBitString(segments:, ..) ->
      list.flat_map(segments, fn(segment) { extract_pattern_refs(segment.0) })
    glance.PatternInt(..) -> []
    glance.PatternFloat(..) -> []
    glance.PatternString(..) -> []
    glance.PatternDiscard(..) -> []
    glance.PatternVariable(..) -> []
    glance.PatternConcatenate(..) -> []
  }
}

// -- Filtering --

/// Collect all referenced names from client function bodies, signatures, and types.
fn collect_all_client_refs(
  ast: glance.Module,
  client_fn_names: Set(String),
  server_symbols: Set(String),
) -> Set(String) {
  let client_fns =
    ast.functions
    |> list.filter(fn(def) {
      set.contains(client_fn_names, def.definition.name)
    })

  let body_refs =
    list.flat_map(client_fns, fn(def) { extract_fn_references(def.definition) })

  let sig_refs =
    list.flat_map(client_fns, fn(def) {
      let function = def.definition
      let param_refs =
        list.flat_map(function.parameters, fn(p) {
          case p.type_ {
            Some(t) -> extract_type_refs(t)
            None -> []
          }
        })
      let return_refs = case function.return {
        Some(t) -> extract_type_refs(t)
        None -> []
      }
      list.append(param_refs, return_refs)
    })

  let client_types =
    ast.custom_types
    |> list.filter(fn(def) {
      !set.contains(server_symbols, def.definition.name)
    })

  let type_refs =
    list.flat_map(client_types, fn(def) {
      list.flat_map(def.definition.variants, fn(v) {
        list.flatten([
          [v.name],
          list.flat_map(v.fields, fn(f) {
            case f {
              glance.LabelledVariantField(item: t, ..) -> extract_type_refs(t)
              glance.UnlabelledVariantField(item: t) -> extract_type_refs(t)
            }
          }),
        ])
      })
    })

  let alias_refs =
    list.flat_map(ast.type_aliases, fn(def) {
      let name = def.definition.name
      case
        set.contains(server_symbols, name)
        || {
          name != "Model"
          && name != "Msg"
          && !set.contains(client_fn_names, name)
        }
      {
        True -> []
        False -> extract_type_refs(def.definition.aliased)
      }
    })

  list.flatten([body_refs, sig_refs, type_refs, alias_refs]) |> set.from_list
}

fn extract_type_refs(t: glance.Type) -> List(String) {
  case t {
    glance.NamedType(name:, module:, parameters:, ..) -> {
      let mod_ref = case module {
        Some(m) -> [m]
        None -> []
      }
      list.flatten([
        [name],
        mod_ref,
        list.flat_map(parameters, extract_type_refs),
      ])
    }
    glance.TupleType(elements:, ..) ->
      list.flat_map(elements, extract_type_refs)
    glance.FunctionType(parameters:, return:, ..) ->
      list.append(
        list.flat_map(parameters, extract_type_refs),
        extract_type_refs(return),
      )
    glance.VariableType(name:, ..) -> [name]
    glance.HoleType(..) -> []
  }
}

fn filter_imports(
  imports: List(glance.Definition(glance.Import)),
  server_symbols: Set(String),
  client_refs: Set(String),
) -> List(glance.Definition(glance.Import)) {
  list.filter(imports, fn(def) {
    let imp = def.definition
    // Always exclude imports that bring in server-only types
    let imports_server_type =
      list.any(imp.unqualified_types, fn(uq) {
        set.contains(server_symbols, uq.name)
      })
    case imports_server_type {
      True -> False
      False -> {
        // Keep if any unqualified import is referenced by client code
        let has_unqualified_ref =
          list.any(imp.unqualified_values, fn(uv) {
            set.contains(client_refs, uv.name)
          })
          || list.any(imp.unqualified_types, fn(ut) {
            set.contains(client_refs, ut.name)
          })
        // Keep if the module itself is referenced (qualified access)
        let module_alias = case imp.alias {
          Some(glance.Named(name)) -> name
          _ -> last_segment(imp.module)
        }
        let module_referenced = set.contains(client_refs, module_alias)
        has_unqualified_ref || module_referenced
      }
    }
  })
}

fn last_segment(module_path: String) -> String {
  case string.split(module_path, "/") |> list.last {
    Ok(seg) -> seg
    Error(_) -> module_path
  }
}

fn filter_types(
  types: List(glance.Definition(glance.CustomType)),
  server_symbols: Set(String),
  client_refs: Set(String),
) -> List(glance.Definition(glance.CustomType)) {
  list.filter(types, fn(def) {
    let name = def.definition.name
    let is_server = set.contains(server_symbols, name)
    case is_server {
      False -> True
      True -> {
        // Keep server types whose constructors are referenced by client code
        set.contains(client_refs, name)
        || list.any(def.definition.variants, fn(v) {
          set.contains(client_refs, v.name)
        })
      }
    }
  })
}

fn filter_type_aliases(
  aliases: List(glance.Definition(glance.TypeAlias)),
  server_symbols: Set(String),
  client_refs: Set(String),
) -> List(glance.Definition(glance.TypeAlias)) {
  list.filter(aliases, fn(def) {
    let name = def.definition.name
    !set.contains(server_symbols, name)
    && { set.contains(client_refs, name) || name == "Model" || name == "Msg" }
  })
}

fn filter_constants(
  constants: List(glance.Definition(glance.Constant)),
  client_refs: Set(String),
) -> List(glance.Definition(glance.Constant)) {
  list.filter(constants, fn(def) {
    set.contains(client_refs, def.definition.name)
  })
}

fn extract_client_functions(
  ast: glance.Module,
  client_fn_names: Set(String),
  source: String,
) -> List(String) {
  ast.functions
  |> list.filter(fn(def) { set.contains(client_fn_names, def.definition.name) })
  |> list.map(fn(def) {
    let fn_source = extract_span_source(source, def.definition.location)
    let attrs =
      def.attributes
      |> list.filter_map(fn(attr) {
        case attr.name {
          "external" -> Ok(render_attribute(attr))
          _ -> Error(Nil)
        }
      })
    case attrs {
      [] -> fn_source
      _ -> string.join(attrs, "\n") <> "\n" <> fn_source
    }
  })
}

fn render_attribute(attr: glance.Attribute) -> String {
  let args =
    attr.arguments
    |> list.map(render_attr_expr)
    |> string.join(", ")
  "@" <> attr.name <> "(" <> args <> ")"
}

fn render_attr_expr(expr: glance.Expression) -> String {
  case expr {
    glance.String(value:, ..) -> "\"" <> value <> "\""
    glance.Variable(name:, ..) -> name
    _ -> "..."
  }
}

// -- Source extraction --

/// Glance reports byte offsets, but string.slice uses codepoint offsets.
/// Multi-byte characters (e.g. ç in "Français") cause a mismatch.
/// Convert to bytes, slice, then decode back to a string.
@external(erlang, "rally_tree_shaker_ffi", "byte_slice")
fn extract_span_source(source: String, span: glance.Span) -> String

// -- Import rendering --

fn render_import(def: glance.Definition(glance.Import)) -> String {
  let imp = def.definition
  let base = "import " <> imp.module

  let alias_part = case imp.alias {
    Some(glance.Named(name)) -> " as " <> name
    Some(glance.Discarded(name)) -> " as _" <> name
    None -> ""
  }

  let unqualified_types =
    list.map(imp.unqualified_types, fn(ut) {
      case ut.alias {
        Some(alias) -> "type " <> ut.name <> " as " <> alias
        None -> "type " <> ut.name
      }
    })

  let unqualified_values =
    list.map(imp.unqualified_values, fn(uv) {
      case uv.alias {
        Some(alias) -> uv.name <> " as " <> alias
        None -> uv.name
      }
    })

  let all_unqualified = list.append(unqualified_types, unqualified_values)

  let unqualified_part = case all_unqualified {
    [] -> ""
    items -> ".{" <> string.join(items, ", ") <> "}"
  }

  base <> alias_part <> unqualified_part
}
