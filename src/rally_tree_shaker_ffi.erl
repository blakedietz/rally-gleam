-module(rally_tree_shaker_ffi).
-export([byte_slice/2]).

%% Slice a UTF-8 binary using byte offsets from a glance Span record.
%% Glance spans are {span, Start, End} where Start/End are byte positions.
byte_slice(Source, {span, Start, End}) ->
    Len = End - Start,
    <<_:Start/binary, Slice:Len/binary, _/binary>> = Source,
    Slice.
