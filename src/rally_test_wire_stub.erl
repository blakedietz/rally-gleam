%% Test-only wire module stub for effect tests.
%% Registered as {libero, wire_module} so encode_push_payload
%% doesn't crash in tests that exercise the effect machinery
%% without a full generated wire module.

-module(rally_test_wire_stub).
-export([encode_push/2, encode_term/1, decode_term/1, register/0]).

encode_push(_Page, Msg) -> Msg.
encode_term(Term) -> Term.
decode_term(Term) -> Term.

register() ->
    persistent_term:put({libero, wire_module}, ?MODULE),
    nil.
