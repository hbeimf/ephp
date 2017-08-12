-module(ephp_vars).
-author('manuel@altenwald.com').
-compile([warnings_as_errors]).

-include("ephp.hrl").

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([
    start_link/0,
    clone/1,
    get/2,
    get/3,
    set/4,
    isset/2,
    ref/5,
    del/3,
    zip_args/7,
    destroy/2,
    destroy_data/2
]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link() ->
    Ref = make_ref(),
    erlang:put(Ref, ephp_array:new()),
    {ok, Ref}.

clone(Vars) ->
    NewVars = make_ref(),
    erlang:put(NewVars, erlang:get(Vars)),
    NewVars.

get(Vars, VarPath) ->
    get(Vars, VarPath, undefined).

get(Vars, VarPath, Context) ->
    search(VarPath, erlang:get(Vars), Context).

isset(Vars, VarPath) ->
    exists(VarPath, erlang:get(Vars)).

set(Vars, VarPath, Value, Context) ->
    erlang:put(Vars, change(VarPath, Value, erlang:get(Vars), Context)),
    ok.

ref(Vars, VarPath, VarsPID, RefVarPath, Context) ->
    case get(VarsPID, RefVarPath) of
        Value when ?IS_OBJECT(Value) orelse ?IS_MEM(Value) ->
            set(Vars, VarPath, Value, Context);
        Value when RefVarPath =/= global ->
            MemRef = ephp_mem:add(Value),
            set(VarsPID, RefVarPath, MemRef, Context),
            ephp_mem:add_link(MemRef),
            set(Vars, VarPath, MemRef, Context);
        _ ->
            ValueFormatted = #var_ref{pid = VarsPID, ref = global},
            set(Vars, VarPath, ValueFormatted, Context)
    end.

del(Vars, VarPath, Context) ->
    set(Vars, VarPath, remove, Context).

zip_args(VarsSrc, VarsDst, ValArgs, FuncArgs, FunctName, Line, Context) ->
    Zip = fun
        (#ref{var = VarRef}, [{#variable{} = VarName,_}|RestArgs]) ->
            ref(VarsDst, VarRef, VarsSrc, VarName, Context),
            RestArgs;
        (#ref{}, _) ->
            ephp_error:error({error, enorefvar, Line, ?E_ERROR, {}});
        (FuncArg, [{_, ArgVal}|RestArgs]) ->
            set(VarsDst, FuncArg, ArgVal, Context),
            RestArgs;
        (#variable{default_value = Val} = FuncArg, []) when Val =/= undefined ->
            set(VarsDst, FuncArg, Val, Context),
            [];
        (_FuncArg, []) ->
            []
    end,
    Check = fun
        (_I, _Type, _Data, true) ->
            ok;
        (I, Type, Data, false) ->
            File = ephp_context:get_active_file(Context),
            ephp_error:handle_error(Context,
                                    {error, errtype, Line, File,
                                     ?E_RECOVERABLE_ERROR,
                                     {I, Type, ephp_data:gettype(Data), FunctName}})
    end,
    lists:foldl(fun
        (#ref{var = #variable{data_type = DataType}} = Ref,
         {I, [{_, Value}|_] = Acc}) when DataType =/= undefined ->
            Check(I, DataType, Value,
                  ephp_class:instance_of(Context, Value, DataType)),
            {I+1, Zip(Ref, Acc)};
        (#variable{data_type = DataType} = Var,
         {I, [{_, Value}|_] = Acc}) when DataType =/= undefined ->
            Check(I, DataType, Value,
                  ephp_class:instance_of(Context, Value, DataType)),
            {I+1, Zip(Var, Acc)};
        (VarOrRef, {I, Acc}) ->
            {I+1, Zip(VarOrRef, Acc)}
    end, {1, ValArgs}, FuncArgs),
    ok.

-spec destroy(context(), ephp:vars_id()) -> ok.

destroy(Ctx, VarsRef) ->
    Vars = erlang:get(VarsRef),
    destroy_data(Ctx, Vars),
    erlang:erase(VarsRef),
    ok.

destroy_data(_Context, undefined) ->
    ok;

destroy_data(Context, ObjRef) when ?IS_OBJECT(ObjRef) ->
    ephp_object:remove(Context, ObjRef);

destroy_data(_Context, MemRef) when ?IS_MEM(MemRef) ->
    ephp_mem:remove(MemRef);

destroy_data(Context, Vars) when ?IS_ARRAY(Vars) ->
    ephp_array:fold(fun(_K, ObjRef, _) when ?IS_OBJECT(ObjRef) ->
                        destroy_data(Context, ObjRef);
                       (_K, V, _) when ?IS_ARRAY(V) ->
                        destroy_data(Context, V);
                       (_K, MemRef, _) when ?IS_MEM(MemRef) ->
                        destroy_data(Context, MemRef);
                       (_K, _V, _) ->
                        ok
                    end, undefined, Vars),
    ok.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

exists(#variable{} = Var, MemRef) when ?IS_MEM(MemRef) ->
    exists(Var, ephp_mem:get(MemRef));

exists(#variable{name = Root, idx=[]}, Vars) ->
    case ephp_array:find(Root, Vars) of
        error -> false;
        {ok, undefined} -> false;
        _ -> true
    end;

exists(#variable{name = Root, idx=[NewRoot|Idx]}, Vars) ->
    case ephp_array:find(Root, Vars) of
        {ok, #var_ref{ref=global}} ->
            exists(#variable{name = NewRoot, idx = Idx}, Vars);
        {ok, #var_ref{pid=RefVarsPID, ref=#variable{idx=NewIdx}=RefVar}} ->
            NewRefVar = RefVar#variable{idx = NewIdx ++ [NewRoot|Idx]},
            isset(RefVarsPID, NewRefVar);
        {ok, #obj_ref{pid=Objects, ref=ObjectId}} ->
            Ctx = ephp_object:get_context(Objects, ObjectId),
            NewObjVar = #variable{name=NewRoot, idx=Idx},
            isset(Ctx, NewObjVar);
        {ok, NewVars} ->
            exists(#variable{name=NewRoot, idx=Idx}, NewVars);
        error ->
            false
    end.

search(global, Vars, _Context) ->
    Vars;

search(#variable{idx = []}, undefined, undefined) ->
    undefined;

search(#variable{name = Root, idx = [], line = Line}, undefined, Context) ->
    File = ephp_context:get_active_file(Context),
    ephp_error:handle_error(Context,
        {error, eundefvar, Line, File, ?E_NOTICE, {Root}}),
    undefined;

search(#variable{name = Root, idx = [], line = Line}, Vars, Context) ->
    case ephp_array:find(Root, Vars) of
        error when Context =:= undefined ->
            undefined;
        error ->
            File = ephp_context:get_active_file(Context),
            ephp_error:handle_error(Context,
                {error, eundefvar, Line, File, ?E_NOTICE, {Root}}),
            undefined;
        {ok, #var_ref{ref=global}} ->
            Vars;
        {ok, #var_ref{pid=RefVarsPID, ref=RefVar}} ->
            get(RefVarsPID, RefVar);
        {ok, Value} ->
            Value
    end;

search(#variable{name = Root, idx = [NewRoot|Idx], line = Line},
       Vars, Context) ->
    case ephp_array:find(Root, Vars) of
        {ok, #var_ref{ref = global}} ->
            search(#variable{name = NewRoot, idx = Idx}, Vars, undefined);
        {ok, #var_ref{pid = RefVarsPID, ref = #variable{idx = NewIdx} = RefVar}} ->
            NewRefVar = RefVar#variable{idx = NewIdx ++ [NewRoot|Idx]},
            get(RefVarsPID, NewRefVar);
        {ok, MemRef} when ?IS_MEM(MemRef) ->
            search(#variable{name = NewRoot, idx = Idx},
                   ephp_mem:get(MemRef), Context);
        {ok, ObjRef} when ?IS_OBJECT(ObjRef) ->
            Ctx = ephp_object:get_context(ObjRef),
            NewObjVar = #variable{name = NewRoot, idx = Idx},
            get(Ctx, NewObjVar);
        {ok, NewVars} ->
            search(#variable{name = NewRoot, idx = Idx}, NewVars, undefined);
        _ when Context =:= undefined ->
            undefined;
        _ ->
            File = ephp_context:get_active_file(Context),
            ephp_error:handle_error(Context,
                {error, eundefvar, Line, File, ?E_NOTICE, {Root}}),
            undefined
    end.

-spec change(variable(), remove | mixed(), ephp:variables_id(), context()) ->
      ephp:variables_id().
%% @private
%% @doc change the value of a variable. This is used only internally.
change(#variable{name = Root, idx = []} = _Var, remove, Vars, _Context) ->
    ephp_array:erase(Root, Vars);

change(#variable{name = auto, idx = []} = _Var, Value, Vars, _Context) ->
    ephp_array:store(auto, Value, Vars);

change(#variable{name = Root, idx = []} = _Var, Value, Vars, Context) ->
    if
        ?IS_OBJECT(Value) ->
            ephp_object:add_link(Value);
        ?IS_MEM(Value) ->
            ephp_mem:add_link(Value);
        true -> ok
    end,
    case ephp_array:find(Root, Vars) of
        {ok, #var_ref{ref = global}} ->
            ephp_array:store(Root, Value, Vars);
        {ok, #var_ref{pid = RefVarsPID, ref = RefVar}} ->
            set(RefVarsPID, RefVar, Value, Context),
            Vars;
        {ok, #obj_ref{} = ObjRef} ->
            ephp_object:remove(Context, ObjRef),
            ephp_array:store(Root, Value, Vars);
        {ok, #mem_ref{} = MemRef} when ?IS_OBJECT(Value) orelse ?IS_MEM(Value) ->
            ephp_mem:remove(MemRef),
            ephp_array:store(Root, Value, Vars);
        {ok, #mem_ref{} = MemRef} ->
            ephp_mem:set(MemRef, Value),
            Vars;
        _ ->
            ephp_array:store(Root, Value, Vars)
    end;

%% TODO: check when auto is passed as idx to trigger an error
change(#variable{name=Root, idx=[{object,NewRoot,_Line}]}=_Var, Value, Vars, _Ctx) ->
    {ok, #obj_ref{ref=ObjectId, pid=Objects}} = ephp_array:find(Root, Vars),
    #ephp_object{context = Ctx} = RI = ephp_object:get(Objects, ObjectId),
    Class = ephp_class:add_if_no_exists_attrib(RI#ephp_object.class, NewRoot),
    NewRI = RI#ephp_object{class=Class},
    ephp_object:set(Objects, ObjectId, NewRI),
    ephp_context:set(Ctx, #variable{name=NewRoot}, Value),
    Vars;

change(#variable{name=Root, idx=[{object,NewRoot,_Line}|Idx]}=_Var,
       Value, Vars, _Ctx) ->
    {ok, #obj_ref{ref=ObjectId, pid=Objects}} = ephp_array:find(Root, Vars),
    #ephp_object{context = Ctx} = RI = ephp_object:get(Objects, ObjectId),
    Class = ephp_class:add_if_no_exists_attrib(RI#ephp_object.class, NewRoot),
    NewRI = RI#ephp_object{class=Class},
    ephp_object:set(RI#ephp_object.objects, RI#ephp_object.id, NewRI),
    ephp_context:set(Ctx, #variable{name=NewRoot, idx=Idx}, Value),
    Vars;

change(#variable{name=Root, idx=[NewRoot|Idx]}=_Var, Value, Vars, Ctx) ->
    case ephp_array:find(Root, Vars) of
        {ok, #var_ref{ref = global}} ->
            change(#variable{name = NewRoot, idx = Idx}, Value, Vars, Ctx);
        {ok, #var_ref{pid = RefVarsPID, ref = #variable{idx = NewIdx} = RefVar}} ->
            NewRefVar = RefVar#variable{idx = NewIdx ++ [NewRoot|Idx]},
            set(RefVarsPID, NewRefVar, Value, Ctx),
            Vars;
        {ok, #obj_ref{pid = Objects, ref = ObjectId}} ->
            Ctx = ephp_object:get_context(Objects, ObjectId),
            ephp_context:set(Ctx, #variable{name=NewRoot, idx=Idx}, Value),
            Vars;
        {ok, NewVars} when ?IS_ARRAY(NewVars) ->
            ephp_array:store(Root,
                             change(#variable{name=NewRoot, idx=Idx}, Value,
                                    NewVars, Ctx),
                             Vars);
        {ok, MemRef} when ?IS_MEM(MemRef) ->
            ephp_mem:set(MemRef, change(#variable{name=NewRoot, idx=Idx}, Value,
                                        ephp_mem:get(MemRef), Ctx)),
            Vars;
        _ ->
            ephp_array:store(Root,
                             change(#variable{name=NewRoot, idx=Idx}, Value,
                                    ephp_array:new(), Ctx),
                             Vars)
    end.
