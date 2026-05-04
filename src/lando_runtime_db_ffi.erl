-module(lando_runtime_db_ffi).
-export([add_db_timing/1, get_db_timing/0, init_db_timing/0]).

init_db_timing() ->
    erlang:put(lando_db_time_ms, 0),
    erlang:put(lando_db_query_count, 0),
    nil.

add_db_timing(ElapsedMs) ->
    Prev = case erlang:get(lando_db_time_ms) of
        undefined -> 0;
        V -> V
    end,
    Count = case erlang:get(lando_db_query_count) of
        undefined -> 0;
        C -> C
    end,
    erlang:put(lando_db_time_ms, Prev + ElapsedMs),
    erlang:put(lando_db_query_count, Count + 1),
    nil.

get_db_timing() ->
    DbTime = case erlang:get(lando_db_time_ms) of
        undefined -> 0;
        T -> T
    end,
    Count = case erlang:get(lando_db_query_count) of
        undefined -> 0;
        C -> C
    end,
    {DbTime, Count}.
