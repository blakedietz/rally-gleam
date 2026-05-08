%% Rally runtime FFI: WebSocket process state management.
%%
%% These functions manage per-connection state in the process dictionary
%% of the WebSocket handler process. The effect module reads this state
%% to push frames during server_update dispatch.

-module(rally_runtime_ffi).
-export([put_ws_state/3, get_ws_conn/0, get_ws_page/0, get_stored_server_context/0,
         push_outgoing_frame/1, drain_outgoing_frames/0,
         put_ws_session/1, get_ws_session/0, decode_rally_push/1,
         store_system_conn/1, get_system_conn/0]).

put_ws_state(Conn, Ctx, Page) ->
    put(rally_ws_conn, Conn),
    put(rally_ws_ctx, Ctx),
    put(rally_ws_page, Page),
    nil.

get_ws_conn() ->
    case get(rally_ws_conn) of
        undefined -> {error, nil};
        Val -> {ok, Val}
    end.
get_ws_page() ->
    case get(rally_ws_page) of
        undefined -> <<>>;
        Val -> Val
    end.
get_stored_server_context() ->
    case get(rally_ws_ctx) of
        undefined -> {error, nil};
        Val -> {ok, Val}
    end.

push_outgoing_frame(Frame) ->
    case get(rally_outgoing_frames) of
        undefined -> put(rally_outgoing_frames, [Frame]);
        Frames -> put(rally_outgoing_frames, [Frame | Frames])
    end,
    nil.

%% Frames are prepended (O(1)) during dispatch, reversed here to preserve send order.
drain_outgoing_frames() ->
    case get(rally_outgoing_frames) of
        undefined -> [];
        Frames -> put(rally_outgoing_frames, []), lists:reverse(Frames)
    end.

put_ws_session(SessionId) ->
    put(rally_ws_session, SessionId),
    nil.

get_ws_session() ->
    case get(rally_ws_session) of
        undefined -> <<>>;
        Val -> Val
    end.

decode_rally_push(Msg) ->
    case Msg of
        {rally_push, Frame} -> {ok, Frame};
        _ -> {error, nil}
    end.

store_system_conn(Conn) ->
    persistent_term:put({rally, system_conn}, Conn),
    nil.

get_system_conn() ->
    case persistent_term:get({rally, system_conn}, undefined) of
        undefined -> {error, nil};
        Conn -> {ok, Conn}
    end.
