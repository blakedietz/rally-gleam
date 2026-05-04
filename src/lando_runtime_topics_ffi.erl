-module(lando_runtime_topics_ffi).
-export([start/0, join/1, leave/1, members/1, broadcast/2, receive_frame/1]).

start() ->
    case pg:start_link(lando_topics) of
        {ok, _Pid} -> nil;
        {error, {already_started, _Pid}} -> nil
    end.

join(Topic) ->
    pg:join(lando_topics, Topic, self()),
    nil.

leave(Topic) ->
    pg:leave(lando_topics, Topic, self()),
    nil.

members(Topic) ->
    pg:get_members(lando_topics, Topic).

broadcast(Topic, Frame) ->
    Members = pg:get_members(lando_topics, Topic),
    Self = self(),
    lists:foreach(fun(Pid) ->
        case Pid of
            Self -> ok;
            _ -> Pid ! {lando_push, Frame}
        end
    end, Members),
    nil.

receive_frame(TimeoutMs) ->
    receive
        {lando_push, Frame} -> {ok, Frame}
    after TimeoutMs ->
        {error, nil}
    end.
