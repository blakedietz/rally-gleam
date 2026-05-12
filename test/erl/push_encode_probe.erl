%% Real server push encode probe: calls the generated Erlang facade
%% through rally_runtime_ffi:encode_push_frame/2 and prints the
%% resulting JSON frame. The Gleam test runner asserts the output
%% contains the expected typed identity.
%%
%% Run via: erl -noshell -pa <fixture_ebin> -pa <rally_ebin> \
%%   -s push_encode_probe main -s init stop
%%
%% Or as escript: escript test/erl/push_encode_probe.erl <fixture_ebin>

-module(push_encode_probe).
-export([main/0]).

main() ->
    %% Load the generated atoms module and set up persistent_terms.
    %% This registers {libero, push_frame_module} and all required atoms.
    'generated@public@rpc_atoms':ensure(),

    %% Call the push frame facade through the FFI.
    Frame = rally_runtime_ffi:encode_push_frame(<<"Public">>, {updated, 1}),

    %% The frame must be a binary (JSON string) with the expected content.
    io:put_chars(Frame),
    io:nl(),

    %% Crash if the frame doesn't contain the expected type identity.
    {match, _} = re:run(Frame, <<"\"type\":\"public/pages/home_.ToClient\"">>),
    {match, _} = re:run(Frame, <<"\"variant\":\"Updated\"">>),
    {match, _} = re:run(Frame, <<"\"kind\":\"push\"">>),

    ok.
