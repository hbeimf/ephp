-module(ephp_lib_vars).
-author('manuel@altenwald.com').
-compile([warnings_as_errors]).

-behaviour(ephp_func).

-export([
    init/0,
    php_is_array/3,
    php_is_bool/3,
    php_is_integer/3,
    php_is_float/3,
    php_is_numeric/3,
    php_is_null/3,
    php_is_object/3,
    php_is_string/3,
    print_r/3,
    print_r/4,
    var_dump/3,
    isset/3,
    empty/3,
    gettype/3,
    unset/3
]).

-include("ephp.hrl").

-define(SPACES, "    ").
-define(SPACES_VD, "  ").

-spec init() -> [
    ephp_func:php_function() |
    {ephp_func:php_function(), ephp_func:php_function_alias()}
].

init() -> [
    {php_is_array, <<"is_array">>},
    {php_is_bool, <<"is_bool">>},
    {php_is_integer, <<"is_long">>},
    {php_is_integer, <<"is_int">>},
    {php_is_integer, <<"is_integer">>},
    {php_is_float, <<"is_float">>},
    {php_is_float, <<"is_double">>},
    {php_is_numeric, <<"is_numeric">>},
    {php_is_null, <<"is_null">>},
    {php_is_object, <<"is_object">>},
    {php_is_string, <<"is_string">>},
    print_r,
    isset,
    empty,
    gettype,
    unset,
    var_dump
].

-spec php_is_array(context(), line(), var_value()) -> boolean().
php_is_array(_Context, _Line, {_,Value}) -> ?IS_DICT(Value).

-spec php_is_bool(context(), line(), var_value()) -> boolean().
php_is_bool(_Context, _Line, {_,Value}) -> erlang:is_boolean(Value).

-spec php_is_integer(context(), line(), var_value()) -> boolean().
php_is_integer(_Context, _Line, {_,Value}) -> erlang:is_integer(Value).

-spec php_is_numeric(context(), line(), var_value()) -> boolean().
php_is_numeric(_Context, _Line, {_,Value}) -> erlang:is_number(Value).

-spec php_is_float(context(), line(), var_value()) -> boolean().
php_is_float(_Context, _Line, {_,Value}) -> erlang:is_float(Value).

-spec php_is_null(context(), line(), var_value()) -> boolean().
php_is_null(_Context, _Line, {_,undefined}) -> true;
php_is_null(_Context, _Line, _Var) -> false.

-spec php_is_string(context(), line(), var_value()) -> boolean().
php_is_string(_Context, _Line, {_,Value}) -> erlang:is_binary(Value).

-spec php_is_object(context(), line(), var_value()) -> boolean().
php_is_object(_Context, _Line, {_,Value}) ->
    erlang:is_record(Value, reg_instance).

-spec print_r(context(), line(), var_value()) -> true | binary().

print_r(Context, Line, {_,#reg_instance{}}=Vars) ->
    print_r(Context, Line, Vars, {false,false});

print_r(_Context, _Line, {_,Value}) when not ?IS_DICT(Value) -> 
    ephp_util:to_bin(Value);

print_r(Context, Line, Value) ->
    print_r(Context, Line, Value, {false,false}).


-spec var_dump(context(), line(), var_value()) -> undefined.

var_dump(Context, _Line, {_,Value}) ->
    Result = case var_dump_fmt(Context, Value, <<?SPACES_VD>>) of
    Elements when is_list(Elements) ->
        Data = lists:foldl(fun(Chunk,Total) ->
            <<Total/binary, Chunk/binary>>
        end, <<>>, Elements),
        Size = case Value of
        V when is_list(V) ->
            ephp_util:to_bin(length(Value));
        #reg_instance{class=#class{attrs=Attrs}} ->
            ephp_util:to_bin(length(Attrs))
        end,
        if ?IS_DICT(Value) ->
            <<"array(", Size/binary, ") {\n", Data/binary, "}\n">>;
        is_record(Value, reg_instance) ->
            #reg_instance{id=InstanceID,class=Class} = Value,
            ID = integer_to_binary(InstanceID),
            <<"object(", (Class#class.name)/binary, ")#", ID/binary,
              " (", Size/binary, ") {\n", Data/binary, "}\n">>;
        true ->
            Data
        end;
    Element ->
        Element
    end,
    ephp_context:set_output(Context, Result), 
    undefined.

-spec print_r(context(), line(), var_value(), Output :: boolean()) ->
    true | binary().

print_r(_Context, _Line, {_,#reg_instance{class=Class, context=Ctx}},
        {_,true}) ->
    Data = lists:foldl(fun(#class_attr{name=Name}, Output) ->
        Value = ephp_context:get(Ctx, #variable{name=Name}), 
        ValDumped = print_r_fmt(Ctx, Value, <<?SPACES>>),
        <<Output/binary, ?SPACES, "[", Name/binary, "] => ", 
          ValDumped/binary, "\n">>
    end, <<>>, Class#class.attrs),
    <<(Class#class.name)/binary, " Object\n(\n", Data/binary, ")\n">>;

print_r(Context, _Line, {_,#reg_instance{class=Class, context=Ctx}}=_Val,
        {_,false}) ->
    Data = lists:foldl(fun(#class_attr{name=Name}, Output) ->
        Value = ephp_context:get(Ctx, #variable{name=Name}), 
        ValDumped = print_r_fmt(Ctx, Value, <<?SPACES>>),
        <<Output/binary, ?SPACES, "[", Name/binary, "] => ", 
          ValDumped/binary>>
    end, <<>>, Class#class.attrs),
    Out = <<(Class#class.name)/binary, " Object\n(\n", Data/binary, ")\n">>,
    ephp_context:set_output(Context, Out),
    true; 

print_r(_Context, _Line, {_,Value}, {_,true}) when not ?IS_DICT(Value) -> 
    ephp_util:to_bin(Value);

print_r(Context, _Line, {_,Value}, {_,false}) when not ?IS_DICT(Value) -> 
    ephp_context:set_output(Context, ephp_util:to_bin(Value)),
    true;

print_r(Context, _Line, {_,Value}, {_,true}) ->
    Data = lists:foldl(fun(Chunk,Total) ->
        <<Total/binary, Chunk/binary>>
    end, <<>>, print_r_fmt(Context, Value, <<?SPACES>>)),
    <<"Array\n(\n", Data/binary, ")\n">>;

print_r(Context, _Line, {_,Value}, {_,false}) ->
    Data = lists:foldl(fun(Chunk,Total) ->
        <<Total/binary, Chunk/binary>>
    end, <<>>, print_r_fmt(Context, Value, <<?SPACES>>)),
    ephp_context:set_output(Context, <<"Array\n(\n", Data/binary, ")\n">>),
    true.

-spec isset(context(), line(), var_value()) -> boolean().

isset(_Context, _Line, {_,Value}) ->
    case Value of
        undefined -> false;
        _ -> true
    end.

-spec empty(context(), line(), var_value()) -> boolean().

empty(_Context, _Line, {_,Value}) ->
    case Value of
        undefined -> true;
        <<"0">> -> true;
        <<>> -> true;
        false -> true;
        _ -> false
    end.

-spec gettype(context(), line(), var_value()) -> binary().

gettype(_Context, _Line, {_,Value}) ->
    ephp_util:gettype(Value).

-spec unset(context(), line(), var_value()) -> undefined.

unset(Context, Line, {#variable{idx=Idx}=Var,_}) ->
    case ephp_context:get(Context, Var) of
        Array when ?IS_DICT(Array) ->
            lists:foreach(fun({K,_V}) ->
                unset(Context, Line, {Var#variable{idx=Idx ++ [K]},<<>>})
            end, Array);
        #reg_instance{class=Class}=Instance ->
            case ephp_class:get_destructor(Class) of
            undefined ->
                ok;
            _ ->
                Call = #call{name = <<"__destruct">>},
                ephp_context:call_method(Context, Instance, Call),
                % FIXME: add unset for every attribute inside of the instance
                ok
            end;
        _ ->
            ok
    end,
    ephp_context:set(Context, Var, undefined),
    undefined. 

%% ----------------------------------------------------------------------------
%% Internal functions
%% ----------------------------------------------------------------------------

var_dump_fmt(Context, {var_ref,VarPID,VarRef}, Spaces) ->
    %% FIXME add recursion control
    Var = ephp_vars:get(VarPID, VarRef, Context),
    Res = var_dump_fmt(Context, Var, Spaces),
    <<"&", Res/binary>>;

var_dump_fmt(_Context, true, _Spaces) ->
    <<"bool(true)\n">>;

var_dump_fmt(_Context, false, _Spaces) ->
    <<"bool(false)\n">>;

var_dump_fmt(_Context, Value, _Spaces) when is_integer(Value) -> 
    <<"int(",(ephp_util:to_bin(Value))/binary, ")\n">>;

var_dump_fmt(_Context, Value, _Spaces) when is_float(Value) -> 
    <<"float(",(ephp_util:to_bin(Value))/binary, ")\n">>;

var_dump_fmt(_Context, Value, _Spaces) when is_binary(Value) -> 
    Size = ephp_util:to_bin(byte_size(Value)),
    <<"string(",Size/binary,") \"",(ephp_util:to_bin(Value))/binary, "\"\n">>;

var_dump_fmt(Context, #reg_instance{class=Class, context=Ctx}, Spaces) ->
    lists:foldl(fun(#class_attr{name=Name}, Output) ->
        Value = ephp_context:get(Ctx, #variable{name=Name}),
        ValDumped = var_dump_fmt(Context, Value, <<Spaces/binary, ?SPACES_VD>>),
        Output ++ [<<
          Spaces/binary, "[\"", Name/binary, "\"]=>\n",
          Spaces/binary, ValDumped/binary>>]
    end, [], Class#class.attrs);

var_dump_fmt(_Context, undefined, _Spaces) ->
    <<"NULL\n">>;

var_dump_fmt(Context, Value, Spaces) when is_list(Value) ->
    ?DICT:fold(fun(Key, Val, Res) ->
        KeyBin = if
            not is_binary(Key) -> ephp_util:to_bin(Key);
            true -> <<"\"", Key/binary, "\"">>
        end,
        Res ++ case var_dump_fmt(Context, Val, <<Spaces/binary, ?SPACES_VD>>) of
            V when is_binary(V) -> 
                [
                    <<Spaces/binary, "[", KeyBin/binary, "]=>\n",
                        Spaces/binary, V/binary>>
                ];
            V when is_list(V) ->
                Elements = ephp_util:to_bin(length(Val)),
                [
                    <<Spaces/binary, "[", KeyBin/binary, "]=>\n">>,
                    <<Spaces/binary,"array(", Elements/binary, ") {\n">>
                ] ++ V ++ [
                    <<Spaces/binary, "}\n">>
                ]
        end
    end, [], Value).

print_r_fmt(Context, {var_ref,VarPID,VarRef}, Spaces) ->
    %% FIXME add recursion control
    Var = ephp_vars:get(VarPID, VarRef, Context),
    print_r_fmt(Context, Var, Spaces);

print_r_fmt(_Context, Value, _Spaces) when not ?IS_DICT(Value) -> 
    <<(ephp_util:to_bin(Value))/binary, "\n">>;

print_r_fmt(Context, Value, Spaces) ->
    ?DICT:fold(fun(Key, Val, Res) ->
        KeyBin = ephp_util:to_bin(Key),
        Res ++ case print_r_fmt(Context, Val, <<Spaces/binary, ?SPACES>>) of
            V when is_binary(V) -> 
                [<<Spaces/binary, "[", KeyBin/binary, "] => ", V/binary>>];
            V when is_list(V) ->
                Content = lists:map(fun(Element) ->
                    <<Spaces/binary, Element/binary>>
                end, V),
                [
                    <<Spaces/binary, "[", KeyBin/binary, "] => Array\n">>, 
                    <<Spaces/binary, "    (\n">>
                ] ++ Content ++ [
                    <<Spaces/binary, "    )\n">>
                ]
        end
    end, [], Value).