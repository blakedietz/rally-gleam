// @ts-check
//
// ETF wire format for libero RPC.
//
// Wire shape: Erlang External Term Format (ETF), subset used by Gleam.
// WebSocket uses binary frames (ArrayBuffer).
//
// Gleam lists are rebuilt as linked lists so `gleam/list` operations
// work on them. Custom type decoding is handled by the typed decoder
// generated per consumer (rpc_decoders_ffi.mjs).

import { Ok, Error as ResultError, CustomType, Empty, NonEmpty, BitArray } from "../../gleam_stdlib/gleam.mjs";
import { Some, None } from "../../gleam_stdlib/gleam/option.mjs";
import {
  from_list as dictFromList,
  to_list as dictToList,
} from "../../gleam_stdlib/gleam/dict.mjs";
import { MalformedRequest, UnknownFunction, InternalError } from "./error.mjs";

// ---------- Custom type constructor registry ----------
// Generated codec_ffi.mjs registers per-type constructors here at init
// time. The ETF decoder (decodeTuple) looks up this registry when it
// encounters an atom-tagged tuple for a custom type like {sponsor, ...}
// and reconstructs the proper Gleam constructor instance.
//
// Each entry maps atom_name -> { ctor: class, fieldCount: number }

const constructorRegistry = new Map();

/**
 * Register a custom type constructor for ETF decoding.
 * Called by the generated codec_ffi.mjs at module init time.
 * @param {string} atomName snake_case constructor name (e.g. "sponsor")
 * @param {typeof import("../../gleam_stdlib/gleam.mjs").CustomType} ctor
 * @param {number} fieldCount number of positional fields
 */
export function registerConstructor(atomName, ctor, fieldCount) {
  constructorRegistry.set(atomName, { ctor, fieldCount });
}

// ---------- Error names ----------
//
// Error.name values set on exceptions thrown by the codec. Consumers
// that need to branch on failure mode can match `err.name === ERROR_X`
// instead of parsing message strings.

/** Input to ETFDecoder is not a supported buffer type. */
export const ERROR_INVALID_INPUT = "ETF_INVALID_INPUT";
/** First byte is not the ETF version tag (131). */
export const ERROR_VERSION_BYTE = "ETF_VERSION_BYTE";
/** Encountered a tag the decoder does not support. */
export const ERROR_UNKNOWN_TAG = "ETF_UNKNOWN_TAG";
/** List tail is not NIL_EXT. Gleam cannot produce improper lists. */
export const ERROR_IMPROPER_LIST = "ETF_IMPROPER_LIST";
/** Atom name exceeds the Erlang 255 codepoint limit. */
export const ERROR_ATOM_TOO_LONG = "ETF_ATOM_TOO_LONG";
/** Tuple arity or list length exceeds MAX_COLLECTION_LEN. */
export const ERROR_COLLECTION_TOO_LONG = "ETF_COLLECTION_TOO_LONG";
/** Binary or bit-binary length exceeds MAX_BINARY_BYTES. */
export const ERROR_BINARY_TOO_LARGE = "ETF_BINARY_TOO_LARGE";

// Hard caps so that a malformed (or hostile) frame cannot pre-allocate
// gigabytes of references. Real mist frame limits will normally catch
// this first; these are defense-in-depth and independent of how the
// underlying transport is configured.
const MAX_COLLECTION_LEN = 16_000_000;
const MAX_BINARY_BYTES = 64 * 1024 * 1024;

/**
 * @param {string} message
 * @param {string} name
 * @returns {Error}
 */
function makeError(message, name) {
  const e = new Error(message);
  e.name = name;
  return e;
}

// ---------- Identity helper (for Gleam FFI) ----------

/**
 * @template T
 * @param {T} x
 * @returns {T}
 */
export function identity(x) {
  return x;
}

// ---------- Field type registry ----------
//
// JS has no int/float distinction - `2.0 === 2` and
// `Number.isInteger(2.0) === true`. But ETF does distinguish them,
// and Gleam's BEAM runtime treats Int and Float as different types.
//
// The generator emits registerFieldTypes() calls. The ETF encoder checks
// this registry when encoding custom type fields, ensuring whole-number
// floats like `2.0` are encoded as NEW_FLOAT_EXT (tag 70), even when
// nested inside containers, instead of INTEGER_EXT (tags 97/98).
//
// This is ETF-specific metadata - a JSON encoder would ignore it
// since JSON has only one number type.

/** @type {Map<string, any[]>} */
const fieldTypeRegistry = new Map();

/**
 * Register field type hints for a custom-type atom. Hints are generated
 * from Gleam signatures so container elements typed as Float can still be
 * encoded as ETF floats after JavaScript erases `2.0` to `2`.
 * @param {string} atomName snake_case constructor name
 * @param {any[]} fieldTypes 0-based field type hints
 */
export function registerFieldTypes(atomName, fieldTypes) {
  fieldTypeRegistry.set(atomName, fieldTypes);
}

/**
 * Build a Gleam linked list from a plain JS array.
 * @param {any[]} arr
 * @returns {any}
 */
function arrayToGleamList(arr) {
  let list = new Empty();
  for (let i = arr.length - 1; i >= 0; i--) {
    list = new NonEmpty(arr[i], list);
  }
  return list;
}

/**
 * Flatten a Gleam linked list (or JS array) into a plain JS array.
 * @param {any} list
 * @returns {any[]}
 */
function gleamListToArray(list) {
  if (Array.isArray(list)) return list;
  const out = [];
  let cur = list;
  while (cur instanceof NonEmpty) {
    out.push(cur.head);
    cur = cur.tail;
  }
  return out;
}

// ---------- ETF Decoder ----------
//
// Design note: no wrapper classes for atoms or tuples.
//
// A general-purpose ETF decoder (e.g. arnu515/erlang-etf.js; see
// https://github.com/arnu515/erlang-etf.js, MIT) wraps atoms in `Atom`
// and tuples in `Tuple` because, in raw JS, atoms collide with
// binaries (both are strings) and tuples collide with lists (both are
// arrays). Without wrappers, the consumer can't tell `:ok` from
// `<<"ok">>` or `{1, 2}` from `[1, 2]`.
//
// Libero doesn't need wrappers because the typed decoder layer
// (rpc_decoders_ffi.mjs, generated per consumer) knows the expected
// shape from the Gleam type graph. When raw mode hands back
// `["some", 42]`, the typed decoder sees an `Option(Int)` field at that
// position and constructs `_Some(42)`. Same for atoms-vs-binaries: the
// type tells the decoder which one to expect.
//
// Adding wrapper classes here would just be one more layer the typed
// decoder unwraps. The cost is that raw mode is ambiguous on its own,
// fine for libero, but the reason a future standalone ETF library
// (split from this codec) would need wrappers.
//
// Prior art: libero's codec is independently implemented, but aligns
// with erlang-etf.js on BIT_BINARY_EXT handling and atom-length
// validation (255 codepoints). Credit to that project for the spec
// references.

const utf8Decoder = new TextDecoder();

/**
 * @typedef {ArrayBuffer | Uint8Array | { rawBuffer: Uint8Array }} DecoderInput
 */

class ETFDecoder {
  /**
   * @param {DecoderInput} input ArrayBuffer, Uint8Array, or Gleam BitArray
   * @param {boolean} [raw] if true, atoms stay as strings and tagged
   *   tuples stay as plain JS arrays. Used when the typed decoder
   *   will re-interpret the result.
   */
  constructor(input, raw = false) {
    // Accept any of: ArrayBuffer (WebSocket onmessage with binaryType
    // "arraybuffer"), Uint8Array, or a Gleam JS BitArray (which exposes
    // its bytes as `rawBuffer`, a Uint8Array). Normalising here lets the
    // public `wire.decode` primitive take a Gleam BitArray directly,
    // matching the cross-target promise of the Gleam-side function.
    /** @type {Uint8Array} */
    let bytes;
    if (input instanceof Uint8Array) {
      bytes = input;
    } else if (input instanceof ArrayBuffer) {
      bytes = new Uint8Array(input);
    } else if (input && /** @type {any} */ (input).rawBuffer instanceof Uint8Array) {
      bytes = /** @type {any} */ (input).rawBuffer;
    } else {
      throw makeError(
        "ETFDecoder: input must be ArrayBuffer, Uint8Array, or Gleam BitArray",
        ERROR_INVALID_INPUT,
      );
    }
    this.bytes = bytes;
    this.view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    this.offset = 0;
    this.raw = raw;
  }

  /** @returns {any} */
  decode() {
    const version = this.readUint8();
    if (version !== 131) {
      throw makeError(
        `ETF decode: expected version byte 131, got ${version}`,
        ERROR_VERSION_BYTE,
      );
    }
    return this.decodeTerm();
  }

  ensureAvailable(n) {
    if (this.offset + n > this.bytes.byteLength) {
      throw makeError(
        `ETF decode: need ${n} bytes at offset ${this.offset}, only ${this.bytes.byteLength - this.offset} available`,
        "ETF_TRUNCATED",
      );
    }
  }

  checkCollectionLen(n, label) {
    if (n > MAX_COLLECTION_LEN) {
      throw makeError(
        `ETF decode: ${label} ${n} exceeds limit ${MAX_COLLECTION_LEN}`,
        ERROR_COLLECTION_TOO_LONG,
      );
    }
    return n;
  }

  checkBinaryLen(n, label) {
    if (n > MAX_BINARY_BYTES) {
      throw makeError(
        `ETF decode: ${label} length ${n} exceeds limit ${MAX_BINARY_BYTES}`,
        ERROR_BINARY_TOO_LARGE,
      );
    }
    return n;
  }

  readUint8() {
    this.ensureAvailable(1);
    const v = this.view.getUint8(this.offset);
    this.offset += 1;
    return v;
  }

  readUint16() {
    this.ensureAvailable(2);
    const v = this.view.getUint16(this.offset);
    this.offset += 2;
    return v;
  }

  readUint32() {
    this.ensureAvailable(4);
    const v = this.view.getUint32(this.offset);
    this.offset += 4;
    return v;
  }

  readInt32() {
    this.ensureAvailable(4);
    const v = this.view.getInt32(this.offset);
    this.offset += 4;
    return v;
  }

  readFloat64() {
    this.ensureAvailable(8);
    const v = this.view.getFloat64(this.offset);
    this.offset += 8;
    return v;
  }

  readBytes(n) {
    this.ensureAvailable(n);
    const slice = this.bytes.slice(this.offset, this.offset + n);
    this.offset += n;
    return slice;
  }

  readString(n) {
    return utf8Decoder.decode(this.readBytes(n));
  }

  decodeTerm() {
    const tag = this.readUint8();
    switch (tag) {
      case 70: // NEW_FLOAT_EXT
        return this.readFloat64();

      case 97: // SMALL_INTEGER_EXT
        return this.readUint8();

      case 98: // INTEGER_EXT
        return this.readInt32();

      case 104: // SMALL_TUPLE_EXT
        return this.decodeTuple(this.readUint8());

      case 105: // LARGE_TUPLE_EXT
        return this.decodeTuple(this.checkCollectionLen(this.readUint32(), "tuple arity"));

      case 106: // NIL_EXT (empty list)
        if (this.raw) return [];
        return arrayToGleamList([]);

      case 108: // LIST_EXT
        return this.decodeList();

      case 107: { // STRING_EXT (list of small ints encoded as bytes)
        // Erlang optimizes lists of bytes (0-255) into this compact form.
        // Decode as a Gleam List(Int) - same semantics as LIST_EXT of SMALL_INTEGER_EXT.
        const len = this.readUint16();
        const elements = [];
        for (let i = 0; i < len; i++) {
          elements.push(this.readUint8());
        }
        if (this.raw) return elements;
        return arrayToGleamList(elements);
      }

      case 109: { // BINARY_EXT (Gleam string or byte-aligned BitArray)
        const len = this.checkBinaryLen(this.readUint32(), "binary");
        const bytes = this.readBytes(len);
        if (this.raw) return { __liberoRawBinary: true, rawBuffer: bytes };
        return utf8Decoder.decode(bytes);
      }

      case 110: // SMALL_BIG_EXT
        return this.decodeBigInt(this.readUint8());

      case 111: // LARGE_BIG_EXT
        return this.decodeBigInt(this.readUint32());

      case 116: // MAP_EXT
        return this.decodeMap();

      case 118: // ATOM_UTF8_EXT
        return this.decodeAtom(this.readUint16());

      case 119: // SMALL_ATOM_UTF8_EXT
        return this.decodeAtom(this.readUint8());

      case 77: { // BIT_BINARY_EXT (non-byte-aligned binary)
        // len bytes, then 1 byte for "bits in last byte" (1-8).
        // The last byte's high `bits` bits are meaningful; low `8 - bits`
        // bits are padding. A Gleam BitArray represents this natively
        // via bitSize, so no separate wrapper is needed.
        const len = this.checkBinaryLen(this.readUint32(), "bit_binary");
        const bitsInLastByte = this.readUint8();
        const bytes = this.readBytes(len);
        const bitSize = len === 0 ? 0 : (len - 1) * 8 + bitsInLastByte;
        return new BitArray(bytes, bitSize, 0);
      }

      default:
        throw makeError(
          `ETF decode: unknown tag ${tag} at offset ${this.offset - 1}`,
          ERROR_UNKNOWN_TAG,
        );
    }
  }

  // DESIGN NOTE: No atom count limit on the JS side (unlike Erlang's [safe]
  // flag). This is acceptable because: (1) the server is the only sender and
  // it encodes well-typed Gleam values, (2) the WebSocket server (mist) can
  // enforce frame size limits, and (3) the typed decoder layer rejects
  // unknown constructors. A standalone ETF library should add a limit.
  decodeAtom(len) {
    const name = this.readString(len);
    // Erlang's hard limit is 255 codepoints (not bytes). UTF-8 codepoints
    // are 1-4 bytes, so a byte length under 256 can still produce <= 255
    // codepoints; but ATOM_UTF8_EXT (uint16 length) can exceed this.
    let codepointCount = 0;
    for (const _ of name) {
      codepointCount++;
      if (codepointCount >= 256) {
        throw makeError(
          "ETF decode: atom name exceeds 255 codepoints",
          ERROR_ATOM_TOO_LONG,
        );
      }
    }
    // Special atoms
    if (name === "true") return true;
    if (name === "false") return false;
    if (name === "nil" || name === "undefined") return undefined;
    // Framework constructor atoms: when not in raw mode, return proper
    // instances so Gleam pattern matching works on bare atoms too.
    if (!this.raw) {
      if (name === "none") return new None();
      // Zero-arg custom types registered via constructorRegistry
      const reg = constructorRegistry.get(name);
      if (reg && reg.fieldCount === 0) return new reg.ctor();
    }
    // Return atom as string - unknown constructors are resolved
    // by the generated typed decoders in a second pass.
    return name;
  }

  decodeTuple(arity) {
    if (arity === 0) return [];

    // Peek at first element to check for atom tag
    const firstTag = this.bytes[this.offset];
    if (firstTag === 118 || firstTag === 119) {
      // First element is an atom - read the atom name directly
      this.offset += 1; // skip the tag byte
      const atomLen = firstTag === 119 ? this.readUint8() : this.readUint16();
      const atomName = this.readString(atomLen);

      // Special atoms in tuple position: treat as plain values
      if (atomName === "true" || atomName === "false" || atomName === "nil" || atomName === "undefined") {
        const firstVal = atomName === "true" ? true
          : atomName === "false" ? false
          : undefined;
        const elements = [firstVal];
        for (let i = 1; i < arity; i++) {
          elements.push(this.decodeTerm());
        }
        return elements;
      }

      // Framework constructor reconstruction: when not in raw mode,
      // rebuild Ok, Error, Some, None directly so Gleam callbacks
      // receive proper constructor instances for pattern matching.
      if (!this.raw) {
        switch (atomName) {
          case "ok": {
            const inner = arity >= 2 ? this.decodeTerm() : undefined;
            // Skip any extra elements beyond the first (malformed ETF).
            for (let i = 2; i < arity; i++) this.decodeTerm();
            return new Ok(inner);
          }
          case "error": {
            const inner = arity >= 2 ? this.decodeTerm() : undefined;
            for (let i = 2; i < arity; i++) this.decodeTerm();
            return new ResultError(inner);
          }
          case "some": {
            const inner = arity >= 2 ? this.decodeTerm() : undefined;
            for (let i = 2; i < arity; i++) this.decodeTerm();
            return new Some(inner);
          }
          case "none":
            // None is a zero-arg variant: ETF encodes as just the atom,
            // but if it appears as {none} (1-tuple), skip extra elements.
            for (let i = 1; i < arity; i++) this.decodeTerm();
            return new None();
        }
      }

      // Custom type reconstruction: check the constructor registry
      // populated by codec_ffi.mjs at init time.
      if (!this.raw) {
        const reg = constructorRegistry.get(atomName);
        if (reg) {
          const fields = [];
          for (let i = 1; i < arity; i++) {
            fields.push(this.decodeTerm());
          }
          // Pad with undefined if ETF arity < registered field count
          while (fields.length < reg.fieldCount) fields.push(undefined);
          // Truncate if ETF arity > registered field count
          fields.length = reg.fieldCount;
          return new reg.ctor(...fields);
        }
      }

      // Unknown custom type: return as raw array with atom string as
      // first element. The generated typed decoders (codec_ffi.mjs)
      // resolve these in a second pass.
      const elements = [atomName];
      for (let i = 1; i < arity; i++) {
        elements.push(this.decodeTerm());
      }
      return elements;
    }

    // Not atom-tagged - decode all elements as plain JS array (Gleam tuple)
    const elements = [];
    for (let i = 0; i < arity; i++) {
      elements.push(this.decodeTerm());
    }
    return elements;
  }

  decodeList() {
    const count = this.checkCollectionLen(this.readUint32(), "list length");
    const elements = [];
    for (let i = 0; i < count; i++) {
      elements.push(this.decodeTerm());
    }
    // Read the tail - must be NIL_EXT (106) for proper lists.
    // Gleam cannot produce improper lists, so a non-nil tail indicates
    // corrupted data or a non-Gleam sender.
    const tailTag = this.readUint8();
    if (tailTag !== 106) {
      throw makeError(
        "ETF decode: improper list (non-nil tail) - Gleam cannot produce these",
        ERROR_IMPROPER_LIST,
      );
    }
    if (this.raw) return elements;
    return arrayToGleamList(elements);
  }

  decodeBigInt(n) {
    const sign = this.readUint8();
    const digits = this.readBytes(n);
    // Reconstruct the integer from little-endian digits
    let value = 0n;
    for (let i = n - 1; i >= 0; i--) {
      value = (value << 8n) | BigInt(digits[i]);
    }
    if (sign === 1) value = -value;
    // If it fits in a regular JS number, return as Number
    if (value >= Number.MIN_SAFE_INTEGER && value <= Number.MAX_SAFE_INTEGER) {
      return Number(value);
    }
    return value;
  }

  decodeMap() {
    const arity = this.readUint32();
    this.checkCollectionLen(arity, "map arity");
    const pairs = [];
    for (let i = 0; i < arity; i++) {
      const key = this.decodeTerm();
      const val = this.decodeTerm();
      pairs.push([key, val]);
    }
    if (this.raw) return pairs;
    return dictFromList(arrayToGleamList(pairs));
  }
}

// ---------- ETF Encoder ----------

const textEncoder = new TextEncoder();

class ETFEncoder {
  constructor() {
    // Start with 1024 bytes, grow as needed.
    this.buffer = new ArrayBuffer(1024);
    this.view = new DataView(this.buffer);
    this.bytes = new Uint8Array(this.buffer);
    this.offset = 0;
  }

  /** @param {number} needed */
  ensureCapacity(needed) {
    const required = this.offset + needed;
    if (required <= this.buffer.byteLength) return;
    let newSize = this.buffer.byteLength;
    while (newSize < required) newSize *= 2;
    const newBuffer = new ArrayBuffer(newSize);
    new Uint8Array(newBuffer).set(this.bytes);
    this.buffer = newBuffer;
    this.view = new DataView(this.buffer);
    this.bytes = new Uint8Array(this.buffer);
  }

  /** @param {number} v */
  writeUint8(v) {
    this.ensureCapacity(1);
    this.view.setUint8(this.offset, v);
    this.offset += 1;
  }

  /** @param {number} v */
  writeUint16(v) {
    this.ensureCapacity(2);
    this.view.setUint16(this.offset, v);
    this.offset += 2;
  }

  /** @param {number} v */
  writeUint32(v) {
    this.ensureCapacity(4);
    this.view.setUint32(this.offset, v);
    this.offset += 4;
  }

  /** @param {number} v */
  writeInt32(v) {
    this.ensureCapacity(4);
    this.view.setInt32(this.offset, v);
    this.offset += 4;
  }

  /** @param {number} v */
  writeFloat64(v) {
    this.ensureCapacity(8);
    this.view.setFloat64(this.offset, v);
    this.offset += 8;
  }

  /** @param {Uint8Array} bytes */
  writeBytes(bytes) {
    this.ensureCapacity(bytes.length);
    this.bytes.set(bytes, this.offset);
    this.offset += bytes.length;
  }

  /** @returns {ArrayBuffer} */
  result() {
    return this.buffer.slice(0, this.offset);
  }

  /**
   * @param {any} value
   * @param {any} typeHint
   */
  encodeTerm(value, typeHint = undefined) {
    if (value === undefined || value === null) {
      // Gleam Nil → atom "nil"
      this.writeAtom("nil");
      return;
    }

    if (typeof value === "boolean") {
      this.writeAtom(value ? "true" : "false");
      return;
    }

    if (typeof value === "string") {
      this.encodeBinary(value);
      return;
    }

    if (typeof value === "number") {
      if (typeHint === "float") {
        this.encodeFloat(value);
      } else {
        this.encodeNumber(value);
      }
      return;
    }

    if (typeof value === "bigint") {
      this.encodeBigInt(value);
      return;
    }

    // JS array = Gleam tuple
    if (Array.isArray(value)) {
      const elementHints =
        typeHint?.kind === "tuple" ? typeHint.elements : undefined;
      this.encodeTuple(value, elementHints);
      return;
    }

    // Gleam linked list
    if (value instanceof Empty || value instanceof NonEmpty) {
      const arr = gleamListToArray(value);
      const elementHint = typeHint?.kind === "list" ? typeHint.element : undefined;
      this.encodeList(arr, elementHint);
      return;
    }

    // Plain JS Map, useful for tests and low-level interop.
    if (value instanceof Map) {
      this.encodeMap(
        value,
        typeHint?.kind === "dict" ? typeHint.key : undefined,
        typeHint?.kind === "dict" ? typeHint.value : undefined,
      );
      return;
    }

    // Gleam stdlib Dict (HAMT object). Detected by duck-typing on the
    // internal `root` + `size` fields of gleam_stdlib's persistent hash
    // map implementation. This is coupled to stdlib internals: if the
    // HAMT representation changes (different field names, different data
    // structure), this branch silently stops matching and falls through
    // to the unsupported-value error. Verify after gleam_stdlib upgrades.
    if (value && typeof value === "object" && "root" in value && "size" in value) {
      this.encodeMap(
        new Map(gleamListToArray(dictToList(value))),
        typeHint?.kind === "dict" ? typeHint.key : undefined,
        typeHint?.kind === "dict" ? typeHint.value : undefined,
      );
      return;
    }

    // Gleam BitArray (has rawBuffer: Uint8Array).
    // Uses BINARY_EXT (tag 109) for all BitArrays. Sub-byte-aligned
    // BitArrays (bitSize % 8 != 0) should technically use BIT_BINARY_EXT
    // (tag 77), but Gleam's stdlib BitArray is always byte-aligned in
    // practice. The decoder handles BIT_BINARY_EXT correctly for
    // interop with Erlang values that use it.
    if (value && value.rawBuffer instanceof Uint8Array) {
      if (value.bitSize !== undefined && value.bitSize % 8 !== 0) {
        // Sub-byte-aligned: use BIT_BINARY_EXT (tag 77) to preserve
        // trailing bit count. Without this, the Erlang side would
        // receive a byte-aligned binary, losing the trailing bits.
        const byteLen = value.rawBuffer.length;
        const bitsInLastByte = value.bitSize % 8;
        this.writeUint8(77); // BIT_BINARY_EXT
        this.writeUint32(byteLen);
        this.writeUint8(bitsInLastByte);
        this.writeBytes(value.rawBuffer);
      } else {
        this.writeUint8(109); // BINARY_EXT
        this.writeUint32(value.rawBuffer.length);
        this.writeBytes(value.rawBuffer);
      }
      return;
    }

    // Gleam custom type instance
    if (value instanceof CustomType) {
      const ctorName = snakeCase(value.constructor.name);
      const keys = Object.keys(value);
      if (keys.length === 0) {
        // 0-arity constructor → bare atom
        this.writeAtom(ctorName);
      } else {
        // N-arity constructor → tuple {atom, field1, field2, ...}
        const arity = keys.length + 1;
        if (arity <= 255) {
          this.writeUint8(104); // SMALL_TUPLE_EXT
          this.writeUint8(arity);
        } else {
          this.writeUint8(105); // LARGE_TUPLE_EXT
          this.writeUint32(arity);
        }
        this.writeAtom(ctorName);
        // Check field type hints so whole-number floats, including nested
        // values inside containers, retain their Gleam Float type in ETF.
        const fieldTypes = fieldTypeRegistry.get(ctorName);
        keys.forEach((k, i) => {
          const fieldValue = value[k];
          const hintedField = hintForConstructorField(ctorName, i, typeHint)
            ?? fieldTypes?.[i];
          this.encodeTerm(fieldValue, hintedField);
        });
      }
      return;
    }

    // Fallback: this indicates a bug in the calling code; all Gleam
    // types should be handled above. Throw rather than silently
    // producing "[object Object]" which would be a corrupt payload.
    throw new Error(
      "ETF encode: unsupported value type: " + typeof value +
      " (" + String(value) + ")"
    );
  }

  writeAtom(name) {
    const encoded = textEncoder.encode(name);
    if (encoded.length <= 255) {
      this.writeUint8(119); // SMALL_ATOM_UTF8_EXT
      this.writeUint8(encoded.length);
    } else {
      this.writeUint8(118); // ATOM_UTF8_EXT
      this.writeUint16(encoded.length);
    }
    this.writeBytes(encoded);
  }

  encodeBinary(str) {
    const encoded = textEncoder.encode(str);
    this.writeUint8(109); // BINARY_EXT
    this.writeUint32(encoded.length);
    this.writeBytes(encoded);
  }

  encodeNumber(n) {
    if (Number.isInteger(n)) {
      if (n >= 0 && n <= 255) {
        this.writeUint8(97); // SMALL_INTEGER_EXT
        this.writeUint8(n);
      } else if (n >= -2147483648 && n <= 2147483647) {
        this.writeUint8(98); // INTEGER_EXT
        this.writeInt32(n);
      } else {
        // Large integer - use bigint encoding
        this.encodeBigInt(BigInt(n));
      }
    } else {
      this.writeUint8(70); // NEW_FLOAT_EXT
      this.writeFloat64(n);
    }
  }

  /** @param {number} n */
  encodeFloat(n) {
    this.writeUint8(70); // NEW_FLOAT_EXT
    this.writeFloat64(n);
  }

  encodeBigInt(value) {
    const sign = value < 0n ? 1 : 0;
    let abs = value < 0n ? -value : value;
    const digits = [];
    while (abs > 0n) {
      digits.push(Number(abs & 0xFFn));
      abs >>= 8n;
    }
    if (digits.length === 0) {
      // Zero - encode as SMALL_INTEGER_EXT
      this.writeUint8(97);
      this.writeUint8(0);
      return;
    }
    if (digits.length <= 255) {
      this.writeUint8(110); // SMALL_BIG_EXT
      this.writeUint8(digits.length);
    } else {
      this.writeUint8(111); // LARGE_BIG_EXT
      this.writeUint32(digits.length);
    }
    this.writeUint8(sign);
    this.writeBytes(new Uint8Array(digits));
  }

  encodeTuple(elements, elementHints = undefined) {
    if (elements.length <= 255) {
      this.writeUint8(104); // SMALL_TUPLE_EXT
      this.writeUint8(elements.length);
    } else {
      this.writeUint8(105); // LARGE_TUPLE_EXT
      this.writeUint32(elements.length);
    }
    for (let i = 0; i < elements.length; i++) {
      this.encodeTerm(elements[i], elementHints?.[i]);
    }
  }

  encodeList(arr, elementHint = undefined) {
    if (arr.length === 0) {
      this.writeUint8(106); // NIL_EXT
      return;
    }
    this.writeUint8(108); // LIST_EXT
    this.writeUint32(arr.length);
    for (const el of arr) {
      this.encodeTerm(el, elementHint);
    }
    this.writeUint8(106); // NIL_EXT tail
  }

  encodeMap(map, keyHint = undefined, valueHint = undefined) {
    this.writeUint8(116); // MAP_EXT
    this.writeUint32(map.size);
    map.forEach((val, key) => {
      this.encodeTerm(key, keyHint);
      this.encodeTerm(val, valueHint);
    });
  }
}

function hintForConstructorField(ctorName, index, typeHint) {
  if (index !== 0 || !typeHint || typeof typeHint !== "object") return undefined;
  if (typeHint.kind === "option" && ctorName === "some") return typeHint.inner;
  if (typeHint.kind === "result" && ctorName === "ok") return typeHint.ok;
  if (typeHint.kind === "result" && ctorName === "error") return typeHint.err;
  return undefined;
}

// ---------- Helper ----------

/**
 * Convert PascalCase to snake_case. Mirrors Gleam's `to_snake_case`
 * so runtime encoding and codegen-time atom registration agree.
 * Handles consecutive uppercase: "XMLParser" → "xml_parser",
 * "HTTPSConnection" → "https_connection".
 *
 * Digits are treated as lowercase; no underscore is inserted before
 * a digit run. This matches Gleam's compiler behavior and the Erlang
 * side (walker.to_snake_case). Verified by snake_case_test.gleam.
 * @param {string} name
 * @returns {string}
 */
function snakeCase(name) {
  let result = "";
  for (let i = 0; i < name.length; i++) {
    const ch = name[i];
    const isUpper = ch !== ch.toLowerCase();
    if (i === 0) {
      result += ch.toLowerCase();
      continue;
    }
    if (isUpper) {
      const prevUpper = name[i - 1] !== name[i - 1].toLowerCase();
      const nextLower = i + 1 < name.length
        && name[i + 1] === name[i + 1].toLowerCase();
      if (prevUpper && nextLower) {
        // UPPER→UPPER→lower: start of new word after acronym
        result += "_" + ch.toLowerCase();
      } else if (prevUpper) {
        // UPPER→UPPER→(UPPER|end): still in acronym
        result += ch.toLowerCase();
      } else {
        // lower→UPPER: normal camelCase boundary
        result += "_" + ch.toLowerCase();
      }
    } else {
      result += ch;
    }
  }
  return result;
}

// ---------- Public codec API ----------

/**
 * Encode a standalone Gleam value to an ETF binary. Used by the
 * public `libero.wire.encode` function. Unlike `encode_call`, there
 * is no envelope; the result is the raw ETF encoding of a single
 * value. Intended for non-RPC paths like passing state into a
 * Lustre SPA via init flags.
 * @param {any} value
 * @returns {BitArray}
 */
export function encode_value(value) {
  const encoder = new ETFEncoder();
  encoder.writeUint8(131); // ETF version byte
  encoder.encodeTerm(value);
  return new BitArray(new Uint8Array(encoder.result()));
}

/**
 * Decode a standalone Gleam value from an ETF binary. Symmetric with
 * `encode_value`. Custom type reconstruction is handled by the typed
 * decoder (rpc_decoders_ffi.mjs).
 * @param {DecoderInput} buffer
 * @returns {any}
 */
export function decode_value(buffer) {
  const decoder = new ETFDecoder(buffer);
  return decoder.decode();
}

/**
 * Raw variant of `decode_value`: atoms stay as strings and tagged
 * tuples stay as plain JS arrays. Used internally when the typed
 * decoder (`ensure_decoders`) will re-interpret the result.
 * @param {DecoderInput} buffer
 * @returns {any}
 */
export function decode_value_raw(buffer) {
  const decoder = new ETFDecoder(buffer, true);
  return decoder.decode();
}

// Gleam's wire.DecodeError(message) custom type.
// Must extend CustomType so Gleam pattern matching works.
class WireDecodeError extends CustomType {
  /** @param {string} message */
  constructor(message) {
    super();
    this.message = message;
    this[0] = message;
  }
}

/**
 * Safe variant of `decode_value` that returns a Result instead of
 * throwing. Used by the public `libero.wire.decode_safe` function.
 * @param {DecoderInput} buffer
 * @returns {any} Ok(value) or Error(WireDecodeError)
 */
export function decode_safe(buffer) {
  try {
    const decoder = new ETFDecoder(buffer);
    const value = decoder.decode();
    return new Ok(value);
  } catch (e) {
    const msg = e && /** @type {any} */ (e).message ? /** @type {any} */ (e).message : String(e);
    return new ResultError(new WireDecodeError(msg));
  }
}

// ---------- Debug logging ----------

function debugEnabled() {
  if (typeof window === "undefined") return false;
  if (window.__RALLY_DEBUG__ !== undefined) return window.__RALLY_DEBUG__;
  const appEnv = window.__APP_ENV__;
  return appEnv === "dev" || appEnv === "development";
}

function formatRaw(value, depth = 0) {
  if (value === undefined || value === null) return "Nil";
  if (typeof value === "boolean") return value ? "True" : "False";
  if (typeof value === "string") return JSON.stringify(value);
  if (typeof value === "number" || typeof value === "bigint") return String(value);
  if (value instanceof BitArray) return `<<${value.rawBuffer.length} bytes>>`;
  if (value && value.__liberoRawBinary) return `<<${value.rawBuffer.length} bytes>>`;
  if (Array.isArray(value)) {
    if (value.length === 0) return "[]";
    if (typeof value[0] === "string" && /^[a-z_]/.test(value[0])) {
      const tag = pascalCase(value[0]);
      if (value.length === 1) return tag;
      const fields = value.slice(1).map(v => formatRaw(v, depth + 1));
      return `${tag}(${fields.join(", ")})`;
    }
    const items = value.map(v => formatRaw(v, depth + 1));
    return `#(${items.join(", ")})`;
  }
  if (value instanceof Empty) return "[]";
  if (value instanceof NonEmpty) {
    const items = gleamListToArray(value).map(v => formatRaw(v, depth + 1));
    return `[${items.join(", ")}]`;
  }
  if (value instanceof Map) {
    const pairs = [...value.entries()].map(([k, v]) => `${formatRaw(k)}: ${formatRaw(v, depth + 1)}`);
    return `dict.from_list([${pairs.join(", ")}])`;
  }
  if (value instanceof CustomType) {
    const name = value.constructor.name;
    const keys = Object.keys(value);
    if (keys.length === 0) return name;
    const fields = keys.map(k => formatRaw(value[k], depth + 1));
    return `${name}(${fields.join(", ")})`;
  }
  return String(value);
}

function pascalCase(snake) {
  return snake.split("_").map(s => s.charAt(0).toUpperCase() + s.slice(1)).join("");
}

function recordMessage(direction, label, data, extra) {
  if (typeof window === "undefined") return;
  if (!window.__RALLY_MESSAGES__) window.__RALLY_MESSAGES__ = [];
  const entry = {
    t: performance.now(),
    ts: new Date().toISOString(),
    dir: direction,
    label,
    data,
    formatted: formatRaw(data),
  };
  if (extra) entry.extra = extra;
  window.__RALLY_MESSAGES__.push(entry);
  if (window.__RALLY_MESSAGES__.length > 1000) {
    window.__RALLY_MESSAGES__ = window.__RALLY_MESSAGES__.slice(-500);
  }
}

function logRpc(direction, label, data, extra) {
  if (!debugEnabled()) return;
  recordMessage(direction, label, data, extra);
  const colors = {
    "->": "color: #e8a033; font-weight: bold",
    "<-": "color: #33bbe8; font-weight: bold",
    "<<": "color: #b833e8; font-weight: bold",
  };
  const arrow = direction;
  const style = colors[arrow] || "";
  const parts = [`%c${arrow} ${label}`, style];
  console.groupCollapsed(...parts);
  console.log(formatRaw(data));
  if (extra) {
    for (const [k, v] of Object.entries(extra)) {
      console.log(`${k}:`, v);
    }
  }
  console.groupEnd();
}

if (typeof window !== "undefined") {
  window.__RALLY_FORMAT__ = formatRaw;
}

// ---------- WebSocket ----------
//
// `send` opens the WebSocket lazily on first call and caches the
// connection. The URL is a compile-time constant from Gleam's
// rpc_config module, so it doesn't change across calls. Sends issued
// before the socket's open event are queued and flushed once it opens.
//
// Server→client frames are tagged with a 1-byte prefix:
//   0x00 = response: <<tag, request_id:32-big, etf_bytes>>
//   0x01 = push: <<tag, etf_bytes>>
//
// Responses are matched by request ID (monotonic counter assigned by
// the client). This allows safe timeout handling without closing the
// WebSocket; late responses for timed-out requests are harmlessly
// dropped since their ID has been removed from the callback Map.
//
// Reconnection is automatic. On unexpected close (network blip, server
// restart, page resume from sleep), the socket reconnects with
// exponential backoff (500ms → 30s, full jitter). Pending requests
// reject with a connection-lost error rather than wait; application
// code retries idempotently or surfaces the error. Push handlers
// remain registered across reconnects, so push frames resume once the
// socket is back. Apps that need to refetch state on reconnect should
// register an `on_connect` listener (see registerOnConnect below).

let ws = null;
let pendingSends = [];    // [{payload, requestId, callback, timer}]
let responseCallbacks = new Map(); // requestId -> {callback, timer}
let nextRequestId = 1;
const REQUEST_TIMEOUT_MS = 30_000;
const requestTimestamps = new Map();

// Push handler registry: module path → callback
const pushHandlers = new Map();

// Connection lifecycle listeners. `on_connect` fires on every socket
// open; first connect AND reconnects; so apps can use one path for
// "load initial state". `on_disconnect` fires when the socket closes
// (the reason string is human-readable and intended for UX).
const onConnectListeners = new Set();
const onDisconnectListeners = new Set();

// Reconnect state. lastUrl is captured on first ensureSocket() so
// auto-reconnect can re-create the socket without the caller passing
// the URL again.
let lastUrl = null;
let reconnectTimer = null;
let reconnectAttempts = 0;
const RECONNECT_BASE_MS = 500;
const RECONNECT_MAX_MS = 30_000;

// Build a connection-error value as a proper Gleam Result(_, RpcError)
// so the per-endpoint response decoders can extract the InternalError
// and read its .message field.
function makeConnectionError(message) {
  return new ResultError(new InternalError("", message));
}

// Detect libero dispatch-layer errors in decoded RPC responses.
// These are Result.Error variants wrapping MalformedRequest, UnknownFunction, or InternalError.
function isDispatchError(decoded) {
  if (decoded && decoded.constructor && decoded.constructor.name === "Error") {
    const inner = decoded[0];
    return inner instanceof MalformedRequest
      || inner instanceof UnknownFunction
      || inner instanceof InternalError;
  }
  return false;
}

function formatDispatchError(decoded) {
  const inner = decoded[0];
  if (inner instanceof UnknownFunction) return "UnknownFunction(\"" + inner.name + "\")";
  if (inner instanceof InternalError) return "InternalError(trace: " + inner.trace_id + ", message: \"" + inner.message + "\")";
  if (inner instanceof MalformedRequest) return "MalformedRequest";
  return String(inner);
}

function clearAllPending(reason) {
  const error = makeConnectionError(reason);
  for (const entry of pendingSends) {
    if (entry.timer) clearTimeout(entry.timer);
    entry.callback(error);
  }
  for (const [, entry] of responseCallbacks) {
    if (entry.timer) clearTimeout(entry.timer);
    entry.callback(error);
  }
  pendingSends = [];
  responseCallbacks = new Map();
  requestTimestamps.clear();
}

// Compute the next reconnect delay with full jitter: pick a value in
// [cap/2, cap] where cap doubles each attempt. The jitter avoids a
// thundering herd if many clients drop and reconnect together.
function nextReconnectDelay() {
  const cap = Math.min(
    RECONNECT_BASE_MS * Math.pow(2, reconnectAttempts),
    RECONNECT_MAX_MS,
  );
  return cap / 2 + Math.random() * (cap / 2);
}

function scheduleReconnect() {
  if (reconnectTimer !== null) return;
  if (lastUrl === null) return;
  const delay = nextReconnectDelay();
  reconnectAttempts += 1;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    if (ws === null) ensureSocket(lastUrl);
  }, delay);
}

function cancelReconnect() {
  if (reconnectTimer !== null) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
}

export function ensureSocket(url) {
  if (ws !== null) {
    return;
  }

  lastUrl = url;
  let sock;
  try {
    sock = new WebSocket(url);
    if (typeof window !== "undefined") window.__RALLY_WS__ = sock;
  } catch (e) {
    clearAllPending("WebSocket constructor failed: " + (e && e.message ? e.message : String(e)));
    scheduleReconnect();
    return;
  }
  ws = sock;
  ws.binaryType = "arraybuffer";

  ws.addEventListener("open", () => {
    if (debugEnabled()) {
      const label = reconnectAttempts > 0 ? "reconnected" : "connected";
      console.log(`%c-- ${label} --`, "color: #33e855; font-weight: bold");
    }
    reconnectAttempts = 0;
    cancelReconnect();
    // Fire onConnect listeners first (triggers page_init which establishes
    // the server-side session), then flush pending RPC calls.
    for (const listener of onConnectListeners) {
      try { listener(); } catch (_) { /* swallow listener exceptions */ }
    }
    // Small delay to let page_init reach the server before RPC calls.
    // Without this, pending sends race with the WS handler setup.
    setTimeout(() => {
      for (const entry of pendingSends) {
        ws.send(entry.payload);
        if (entry.callback) {
          responseCallbacks.set(entry.requestId, { callback: entry.callback, timer: entry.timer });
        }
      }
      pendingSends = [];
    }, 50);
  });

  ws.addEventListener("message", (event) => {
    const bytes = new Uint8Array(event.data);
    if (bytes.byteLength < 1) {
      if (debugEnabled()) console.warn("libero: dropped empty WebSocket frame");
      return;
    }
    const tag = bytes[0];
    const payload = bytes.slice(1);

    if (tag === 0x01) {
      // Push frame: payload is ETF-encoded {module, value}. Decode
      // through the typed pipeline so Gleam callbacks receive proper
      // constructor instances (Ok, Error, custom types) rather than
      // raw arrays with string atoms.
      let decoded;
      try {
        decoded = decode_value(payload);
      } catch (e) {
        if (debugEnabled()) console.warn("rally: failed to decode push frame", e);
        return;
      }
      if (Array.isArray(decoded) && typeof decoded[0] === "string"
          && decoded[1] !== undefined) {
        logRpc("<<", `push ${decoded[0]}`, decoded[1]);
        const handler = pushHandlers.get(decoded[0]);
        if (handler) handler(decoded[1]);
      }
      return;
    }

    // Response frame (tag 0x00): extract request ID and match by ID.
    // Frame format: <<0x00, request_id:32-big, etf_bytes>>
    if (bytes.byteLength < 5) {
      if (debugEnabled()) {
        console.warn(`libero: dropped malformed response frame (${bytes.byteLength} bytes, need >= 5)`);
      }
      return;
    }
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const requestId = view.getUint32(1);
    const responsePayload = bytes.slice(5);

    // Decode through the typed pipeline so Gleam callbacks receive
    // proper constructor instances (Ok, Error, custom types) rather
    // than raw arrays with string atoms. formatRaw already handles
    // CustomType instances for the inspector.
    let decoded;
    try {
      decoded = decode_value(responsePayload);
    } catch (e) {
      if (debugEnabled()) console.warn(`rally: failed to decode response #${requestId}`, e);
      const entry = responseCallbacks.get(requestId);
      if (entry) {
        responseCallbacks.delete(requestId);
        if (entry.timer) clearTimeout(entry.timer);
        requestTimestamps.delete(requestId);
        entry.callback(makeConnectionError("Failed to decode response"));
      }
      return;
    }

    const entry = responseCallbacks.get(requestId);
    if (entry) {
      responseCallbacks.delete(requestId);
      if (entry.timer) clearTimeout(entry.timer);
      const sentAt = requestTimestamps.get(requestId);
      if (sentAt !== undefined) {
        requestTimestamps.delete(requestId);
        const ms = (performance.now() - sentAt).toFixed(1);
        logRpc("<-", `rpc #${requestId} (${ms}ms)`, decoded);
      } else {
        logRpc("<-", `rpc #${requestId}`, decoded);
      }
      // Warn on framework-level errors so they're visible in dev
      if (debugEnabled() && isDispatchError(decoded)) {
        console.error("[rally] RPC #" + requestId + " failed:", formatDispatchError(decoded));
      }
      entry.callback(decoded);
    }
  });

  ws.addEventListener("close", () => {
    if (!ws) {
      scheduleReconnect();
      return;
    }
    ws = null;
    if (debugEnabled()) {
      console.log("%c-- disconnected --", "color: #e83333; font-weight: bold");
    }
    clearAllPending("WebSocket connection closed");
    for (const listener of onDisconnectListeners) {
      try { listener("connection closed"); } catch (_) { /* swallow */ }
    }
    scheduleReconnect();
  });

  ws.addEventListener("error", () => {
    if (ws) {
      const sock = ws;
      ws = null;
      // Clear pending callbacks immediately so the close handler (which
      // fires asynchronously) doesn't operate on stale state. The close
      // handler will fire scheduleReconnect; we just need clean teardown.
      clearAllPending("WebSocket error");
      for (const listener of onDisconnectListeners) {
        try { listener("connection error"); } catch (_) { /* swallow */ }
      }
      sock.close();
    }
  });
}

/**
 * Register a callback that fires whenever the WebSocket connection
 * opens; both the initial connect and every successful reconnect.
 * Use this to load (or reload) state without a separate code path
 * for the first connection.
 * @param {() => void} callback
 */
export function registerOnConnect(callback) {
  onConnectListeners.add(callback);
}

/**
 * Register a callback that fires when the WebSocket disconnects.
 * The reason is a human-readable string suitable for UX messaging.
 * @param {(reason: string) => void} callback
 */
export function registerOnDisconnect(callback) {
  onDisconnectListeners.add(callback);
}

/**
 * Send a message and queue a callback for the server's response.
 * Responses are matched by request ID. Each request has a 30-second
 * timeout; if no response arrives, the callback receives an
 * InternalError so the UI doesn't hang indefinitely.
 * @param {string} url WebSocket URL (typically from rpc_config)
 * @param {string} module wire envelope string (codegen emits "rpc")
 * @param {any} msg the typed ClientMsg value to encode and send
 * @param {(result: any) => void} callback invoked with the decoded Result
 */
export function send(url, module, msg, callback) {
  ensureSocket(url);
  const requestId = nextRequestId++;
  const payload = encode_call(module, requestId, msg);
  if (debugEnabled()) requestTimestamps.set(requestId, performance.now());
  logRpc("->", `rpc #${requestId}`, msg, { module });

  const timer = setTimeout(() => {
    // Remove from whichever state this request is in.
    const pendingIdx = pendingSends.findIndex(e => e.requestId === requestId);
    if (pendingIdx !== -1) {
      pendingSends.splice(pendingIdx, 1);
    }
    responseCallbacks.delete(requestId);
    requestTimestamps.delete(requestId);
    callback(makeConnectionError("Request timed out"));
    // No need to close the WebSocket; request IDs prevent FIFO desync.
  }, REQUEST_TIMEOUT_MS);

  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(payload);
    responseCallbacks.set(requestId, { callback, timer });
  } else {
    pendingSends.push({ payload, requestId, callback, timer });
  }
}

/**
 * Send a page init frame with route params. Uses request_id 0 as the
 * init sentinel. The server initializes the page's ServerModel with
 * these params instead of requiring a separate Load message.
 * @param {string} url WebSocket URL
 * @param {string} module page name
 * @param {any} params route params value
 */
export function send_page_init(url, module, params) {
  ensureSocket(url);
  const payload = encode_call(module, 0, params);
  logRpc("->", `page_init ${module}`, params);
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(payload);
  } else {
    pendingSends.push({ payload, requestId: null, callback: null, timer: null });
  }
}

/**
 * Register a push handler for a specific module. When the server
 * sends a push frame tagged with this module path, the callback is
 * invoked with the decoded value.
 * @param {string} module shared module path
 * @param {(value: any) => void} callback
 */
export function registerPushHandler(module, callback) {
  pushHandlers.set(module, callback);
}

/**
 * Encode a call envelope: `{module_name, request_id, msg}` as ETF binary.
 * Symmetric with the server-side `wire.decode_call`. Returns a raw
 * ArrayBuffer (not a Gleam BitArray) because this is only called
 * internally by `send()`, which passes it directly to `WebSocket.send()`.
 * Compare with `encode_value()` which returns a BitArray for Gleam callers.
 * @param {string} module
 * @param {number} requestId
 * @param {any} msg
 * @returns {ArrayBuffer}
 */
export function encode_call(module, requestId, msg) {
  const encoder = new ETFEncoder();
  encoder.writeUint8(131); // ETF version byte
  // Envelope: {<<"module_name">>, request_id, msg_value}
  encoder.writeUint8(104); // SMALL_TUPLE_EXT
  encoder.writeUint8(3);   // arity 3
  encoder.encodeBinary(module);
  encoder.encodeTerm(requestId);
  encoder.encodeTerm(msg);
  return encoder.result();
}

/**
 * Read SSR flags from window.__RALLY_FLAGS__ and clear them.
 * Returns the base64 ETF string or empty string if not present.
 */
export function read_flags() {
  const flags = window.__RALLY_FLAGS__ || "";
  delete window.__RALLY_FLAGS__;
  return flags;
}

export function read_client_context() {
  const ctx = window.__RALLY_CLIENT_CONTEXT__ || "";
  delete window.__RALLY_CLIENT_CONTEXT__;
  return ctx;
}
