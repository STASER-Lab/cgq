-module(cgq_ffi).
-export([stderr_is_terminal/0]).

stderr_is_terminal() ->
    has_columns(standard_error) orelse has_columns(user).

has_columns(Device) ->
    try io:columns(Device) of
        {ok, _} -> true;
        _ -> false
    catch
        _:_ -> false
    end.
