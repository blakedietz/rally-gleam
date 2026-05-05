%% Lando runtime FFI: WebSocket process state management.
%%
%% These functions manage per-connection state in the process dictionary
%% of the WebSocket handler process. The effect module reads this state
%% to push frames during server_update dispatch.

-module(lando_runtime_ffi).
-export([put_ws_state/3, get_ws_conn/0, get_ws_page/0, get_stored_server_context/0,
         push_outgoing_frame/1, drain_outgoing_frames/0,
         put_ws_session/1, get_ws_session/0, decode_lando_push/1]).

put_ws_state(Conn, Ctx, Page) ->
    put(lando_ws_conn, Conn),
    put(lando_ws_ctx, Ctx),
    put(lando_ws_page, Page),
    nil.

get_ws_conn() -> get(lando_ws_conn).
get_ws_page() ->
    case get(lando_ws_page) of
        undefined -> <<>>;
        Val -> Val
    end.
get_stored_server_context() -> get(lando_ws_ctx).

push_outgoing_frame(Frame) ->
    case get(lando_outgoing_frames) of
        undefined -> put(lando_outgoing_frames, [Frame]);
        Frames -> put(lando_outgoing_frames, [Frame | Frames])
    end,
    nil.

%% Frames are prepended (O(1)) during dispatch, reversed here to preserve send order.
drain_outgoing_frames() ->
    case get(lando_outgoing_frames) of
        undefined -> [];
        Frames -> put(lando_outgoing_frames, []), lists:reverse(Frames)
    end.

put_ws_session(SessionId) ->
    put(lando_ws_session, SessionId),
    nil.

get_ws_session() ->
    case get(lando_ws_session) of
        undefined -> <<>>;
        Val -> Val
    end.

decode_lando_push(Msg) ->
    case Msg of
        {lando_push, Frame} -> {ok, Frame};
        _ -> {error, nil}
    end.
