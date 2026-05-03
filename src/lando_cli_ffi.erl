-module(lando_cli_ffi).
-export([find_executable/1, run_executable/2, get_env/1, unique_id/0]).

find_executable(Name) ->
  case os:find_executable(binary_to_list(Name)) of
    false -> {error, nil};
    Path -> {ok, list_to_binary(Path)}
  end.

run_executable(Program, Args) ->
  Cmd = binary_to_list(Program),
  CmdArgs = [binary_to_list(A) || A <- Args],
  Port = open_port({spawn_executable, os:find_executable(Cmd)},
                   [{args, CmdArgs}, exit_status, stderr_to_stdout]),
  Result = loop_until_exit(Port, []),
  {Status, _Output} = Result,
  Status.

loop_until_exit(Port, Acc) ->
  receive
    {Port, {data, Data}} ->
      loop_until_exit(Port, [Data | Acc]);
    {Port, {exit_status, Status}} ->
      {Status, lists:flatten(lists:reverse(Acc))}
  end.

get_env(Name) ->
  case os:getenv(binary_to_list(Name)) of
    false -> {error, nil};
    Value -> {ok, list_to_binary(Value)}
  end.

unique_id() ->
  {ok, erlang:integer_to_binary(erlang:unique_integer())}.
