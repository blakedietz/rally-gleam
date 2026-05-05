-module(lando_runtime_wire_ffi).
-export([tuple_element/2]).

%% Extract the Nth element (0-based) from a tuple or list.
%% Used by generated server_dispatch to unpack route params.
tuple_element(Tuple, Index) when is_tuple(Tuple) ->
    element(Index + 1, Tuple);
tuple_element(List, Index) when is_list(List) ->
    lists:nth(Index + 1, List).
