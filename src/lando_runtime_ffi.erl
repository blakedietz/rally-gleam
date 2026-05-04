%% Libero RPC panic-catching FFI.
%%
%% try_call(F) runs the zero-arg function F and returns {ok, Result}
%% on success, or {error, ReasonBinary} if the function panics or
%% throws. The reason is stringified so the caller can log it
%% alongside a trace_id without pattern-matching on arbitrary
%% Erlang term shapes.

-module(lando_runtime_ffi).
-export([try_call/1, encode/1, decode/1, decode_safe/1, identity/1, trap_signals/0, unique_id/0, put_ws_state/3, get_ws_conn/0, get_ws_page/0, get_stored_ctx/0, push_outgoing_frame/1, drain_outgoing_frames/0]).

identity(X) -> X.

encode(Term) ->
    erlang:term_to_binary(Term).

decode(Bin) ->
    erlang:binary_to_term(Bin, [safe]).

decode_safe(Bin) ->
    try erlang:binary_to_term(Bin, [safe]) of
        Term -> {ok, Term}
    catch
        _:Reason ->
            Msg = erlang:iolist_to_binary(
                io_lib:format("~p", [Reason])
            ),
            {error, {decode_error, Msg}}
    end.

%% Install signal handlers so libero exits cleanly when its parent
%% build script is killed (Ctrl-C, SIGTERM from sandbox, etc.).
%% Without this, a stuck or in-progress libero process can survive
%% its parent and spin at 99% CPU.
trap_signals() ->
    os:set_signal(sigterm, handle),
    os:set_signal(sighup, handle),
    spawn(fun signal_loop/0),
    nil.

signal_loop() ->
    receive
        {signal, sigterm} -> erlang:halt(1);
        {signal, sighup}  -> erlang:halt(1);
        _Other            -> signal_loop()
    end.

try_call(F) ->
    try F() of
        Result -> {ok, Result}
    catch
        Class:Reason:Stacktrace ->
            Message = io_lib:format(
                "~p: ~p~nstacktrace: ~p",
                [Class, Reason, Stacktrace]
            ),
            {error, erlang:iolist_to_binary(Message)}
    end.

%% Return a short unique hex string for trace IDs and temp file names.
%% Uses erlang:unique_integer (per-VM monotonic) plus system time so
%% IDs are unique within the VM and unlikely to collide across VMs.
unique_id() ->
    Int = erlang:unique_integer([positive, monotonic]),
    Time = erlang:system_time(millisecond),
    erlang:iolist_to_binary(io_lib:format("~.16b-~.16b", [Time, Int])).

%% WebSocket handler state stored in the process dictionary.
%% The WS handler process stores its Mist Connection and the current
%% page name before calling into server_update. The effect functions
%% (send_to_client, broadcast) read this state to push frames.

put_ws_state(Conn, Ctx, Page) ->
    put(lando_ws_conn, Conn),
    put(lando_ws_ctx, Ctx),
    put(lando_ws_page, Page),
    nil.

get_ws_conn() -> get(lando_ws_conn).
get_ws_page() -> get(lando_ws_page).
get_stored_ctx() -> get(lando_ws_ctx).

%% Accumulate outgoing push frames in the process dictionary.
%% Called by send_to_client / broadcast from within server_update.
%% The WebSocket handler drains frames after handle_message returns.
push_outgoing_frame(Frame) ->
    case get(lando_outgoing_frames) of
        undefined -> put(lando_outgoing_frames, [Frame]);
        Frames -> put(lando_outgoing_frames, [Frame | Frames])
    end,
    nil.

drain_outgoing_frames() ->
    case get(lando_outgoing_frames) of
        undefined -> [];
        Frames -> put(lando_outgoing_frames, []), lists:reverse(Frames)
    end.
