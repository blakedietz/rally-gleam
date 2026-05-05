-module(rpc_client_ffi).
-export([http_post/2]).

http_post(Url, Body) ->
    inets:start(),
    ssl:start(),
    UrlStr = unicode:characters_to_list(Url),
    Request = {UrlStr, [], "application/octet-stream", Body},
    case httpc:request(post, Request, [{timeout, 10000}], [{body_format, binary}]) of
        {ok, {{_, 200, _}, _, ResponseBody}} ->
            {ok, ResponseBody};
        {ok, {{_, Status, _}, _, _}} ->
            {error, <<"HTTP ", (integer_to_binary(Status))/binary>>};
        {error, Reason} ->
            {error, iolist_to_binary(io_lib:format("~p", [Reason]))}
    end.
