-module(password_ffi).
-export([hash/1, verify/2]).

-define(ITERATIONS, 100000).
-define(KEY_LENGTH, 32).

hash(Password) ->
    Salt = crypto:strong_rand_bytes(16),
    Hash = crypto:pbkdf2_hmac(sha256, Password, Salt, ?ITERATIONS, ?KEY_LENGTH),
    SaltB64 = base64:encode(Salt),
    HashB64 = base64:encode(Hash),
    <<"pbkdf2_sha256$", (integer_to_binary(?ITERATIONS))/binary, "$",
      SaltB64/binary, "$", HashB64/binary>>.

verify(Password, Stored) ->
    case binary:split(Stored, <<"$">>, [global]) of
        [<<"pbkdf2_sha256">>, IterBin, SaltB64, HashB64] ->
            Iterations = binary_to_integer(IterBin),
            Salt = base64:decode(SaltB64),
            Expected = base64:decode(HashB64),
            Computed = crypto:pbkdf2_hmac(sha256, Password, Salt, Iterations, byte_size(Expected)),
            Computed =:= Expected;
        _ ->
            false
    end.
