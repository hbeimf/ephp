-module(ephp_parser).
-export([parse/1, file/1]).

-include("ephp.hrl").

-compile([{inline, [
    add_pos/2,
    new_line/1,
    normal_level/1,
    code_block_level/1,
    code_value_level/1,
    code_statement_level/1,
    arg_level/1,
    add_op/2,
    add_line/2
]}]).

-define(IS_SPACE(X),
    erlang:'or'(X =:= 32,
                erlang:'or'(X =:= $\t,
                            X =:= $\r)
               )
).
-define(IS_NEWLINE(X),
    X =:= $\n
).
-define(IS_NUMBER(X),
    erlang:'and'(X >= $0, X =< $9)
).
-define(IS_ALPHA(X),
    erlang:'or'(
        erlang:'and'(X >= $A, X =< $Z),
        erlang:'and'(X >= $a, X =< $z)
    )
).
-define(OR(I,X,Y), erlang:'or'(I =:= X,I =:= Y)).
-define(IS_OP1_ARITH(X),
    X =:= <<"*">> orelse
    X =:= <<"/">> orelse
    X =:= <<"%">> orelse
    X =:= <<"+">> orelse
    X =:= <<"-">> orelse
    X =:= <<".">> orelse
    X =:= <<"&">> orelse
    X =:= <<"^">> orelse
    X =:= <<"|">>
).
-define(IS_OP1(X),
    X =:= <<126>> orelse
    X =:= <<"@">> orelse
    X =:= <<"!">> orelse
    X =:= <<"*">> orelse
    X =:= <<"/">> orelse
    X =:= <<"%">> orelse
    X =:= <<"+">> orelse
    X =:= <<"-">> orelse
    X =:= <<".">> orelse
    X =:= <<"<">> orelse
    X =:= <<">">> orelse
    X =:= <<"&">> orelse
    X =:= <<"^">> orelse
    X =:= <<"|">>
).
-define(IS_OP2(X),
    X =:= <<"**">> orelse
    X =:= <<"++">> orelse
    X =:= <<"--">> orelse
    X =:= <<"<<">> orelse
    X =:= <<">>">> orelse
    X =:= <<"<=">> orelse
    X =:= <<">=">> orelse
    X =:= <<"==">> orelse
    X =:= <<"!=">> orelse
    X =:= <<"<>">> orelse
    X =:= <<"&&">> orelse
    X =:= <<"||">> orelse
    X =:= <<"??">> orelse
    X =:= <<"+=">> orelse
    X =:= <<"-=">> orelse
    X =:= <<"*=">> orelse
    X =:= <<"/=">> orelse
    X =:= <<".=">> orelse
    X =:= <<"%=">> orelse
    X =:= <<"&=">> orelse
    X =:= <<"|=">> orelse
    X =:= <<"^=">>
).
-define(IS_OP3(X),
    X =:= <<"===">> orelse
    X =:= <<"!==">> orelse
    X =:= <<"<=>">> orelse
    X =:= <<"**=">> orelse
    X =:= <<"<<=">> orelse
    X =:= <<">>=">>
).

file(File) ->
    {ok, Content} = file:read_file(File),
    parse(Content).

parse(Document) when is_list(Document) ->
    parse(list_to_binary(Document));
parse(Document) ->
    {_, _, Parsed} = document(Document, {root,1,1}, []),
    lists:reverse(Parsed).

document(<<>>, Pos, Parsed) ->
    {<<>>, Pos, Parsed};
document(<<"<?php",Rest/binary>>, {literal,_,_}=Pos, Parsed) ->
    {Rest, add_pos(Pos,5), Parsed};
document(<<"<?php",Rest/binary>>, Pos, Parsed) ->
    {Rest0,Pos0,NParsed} = code(Rest, normal_level(add_pos(Pos,5)), []),
    RParsed = lists:reverse(NParsed),
    document(Rest0,Pos0,[add_line(#eval{statements=RParsed},Pos)|Parsed]);
document(<<"<?=",Rest/binary>>, Pos, Parsed) ->
    NewPos = code_value_level(add_pos(Pos,3)),
    {Rest0,Pos0,Text} = code(Rest, NewPos, []),
    document(Rest0, copy_level(Pos,Pos0), [get_print(Text,NewPos)|Parsed]);
document(<<"<?",Rest/binary>>, {literal,_,_}=Pos, Parsed) ->
    %% TODO: if short is not permitted, use as text
    {Rest, add_pos(Pos,2), Parsed};
document(<<"<?",Rest/binary>>, Pos, Parsed) ->
    %% TODO: if short is not permitted, use as text
    {Rest0,Pos0,NParsed} = code(Rest, normal_level(add_pos(Pos,2)), []),
    RParsed = lists:reverse(NParsed),
    document(Rest0,Pos0,[add_line(#eval{statements=RParsed},Pos)|Parsed]);
document(<<"\n",Rest/binary>>, Pos, Parsed) ->
    document(Rest, new_line(Pos), add_to_text(<<"\n">>, Pos, Parsed));
document(<<L:1/binary,Rest/binary>>, Pos, Parsed) ->
    document(Rest, add_pos(Pos,1), add_to_text(L, Pos, Parsed)).

copy_level({Level,_,_}, {_,Row,Col}) -> {Level,Row,Col}.

code(<<>>, Pos, Parsed) ->
    {<<>>, Pos, Parsed};
code(<<B:8,R:8,E:8,A:8,K:8,SP:8,Rest/binary>>, Pos, Parsed) when
        ?OR(B,$B,$b) andalso ?OR(R,$R,$r) andalso ?OR(E,$E,$e) andalso
        ?OR(A,$A,$a) andalso ?OR(K,$K,$k) andalso
        (not (?IS_SPACE(SP) orelse ?IS_NUMBER(SP))) ->
    code(<<SP:8,Rest/binary>>, add_pos(Pos,5), [break|Parsed]);
code(<<C:8,O:8,N:8,T:8,I:8,N:8,U:8,E:8,SP:8,Rest/binary>>, Pos, Parsed) when
        ?OR(C,$C,$c) andalso ?OR(O,$O,$o) andalso ?OR(N,$N,$n) andalso
        ?OR(T,$T,$t) andalso ?OR(I,$I,$i) andalso ?OR(U,$U,$u) andalso
        ?OR(E,$E,$e) andalso (not (?IS_SPACE(SP) orelse ?IS_NUMBER(SP))) ->
    code(<<SP:8,Rest/binary>>, add_pos(Pos,8), [continue|Parsed]);
code(<<R:8,E:8,T:8,U:8,R:8,N:8,SP:8,Rest/binary>>, Pos, Parsed) when
        ?OR(R,$R,$r) andalso ?OR(E,$E,$e) andalso ?OR(T,$T,$t) andalso
        ?OR(U,$U,$u) andalso ?OR(N,$N,$n) andalso
        (not (?IS_ALPHA(SP) orelse ?IS_NUMBER(SP))) ->
    {Rest0, Pos0, Return} = expression(<<SP:8,Rest/binary>>, add_pos(Pos,6), []),
    case Return of
        [] -> code(Rest0, Pos0, [add_line(#return{}, Pos)|Parsed]);
        _ -> code(Rest0, Pos0, [add_line(#return{value=Return}, Pos)|Parsed])
    end;
code(<<"@",Rest/binary>>, Pos, Parsed) ->
    {Rest0, Pos0, RParsed0} = code(Rest, add_pos(Pos,1), []),
    [ToSilent|Parsed0] = lists:reverse(RParsed0),
    Silent = {silent, ToSilent},
    {Rest0, Pos0, lists:reverse([Silent|Parsed0]) ++ Parsed};
code(<<G:8,L:8,O:8,B:8,A:8,L:8,SP:8,Rest/binary>>, Pos, Parsed) when
        ?OR(G,$G,$g) andalso ?OR(L,$L,$l) andalso ?OR(O,$O,$o) andalso
        ?OR(B,$B,$b) andalso ?OR(A,$A,$a) andalso
        (?IS_SPACE(SP) orelse ?IS_NEWLINE(SP)) ->
    {Rest0, Pos0} = remove_spaces(Rest, add_pos(Pos,7)),
    {Rest1, Pos1, [Global]} = st_global(Rest0, Pos0, []),
    code(Rest1, copy_level(Pos, Pos1), [Global|Parsed]);
code(<<"}",Rest/binary>>, {code_block,_,_}=Pos, Parsed) ->
    {Rest, add_pos(Pos,1), lists:reverse(Parsed)};
code(<<"}",Rest/binary>>, {switch_block,_,_}=Pos, Parsed) ->
    {Rest, add_pos(Pos,1), lists:reverse(switch_case_block(Parsed))};
code(<<E:8,N:8,D:8,I:8,F:8,Rest/binary>>, {if_old_block,_,_}=Pos, Parsed) when
        ?OR(E,$E,$e) andalso ?OR(N,$N,$n) andalso ?OR(D,$D,$d) andalso
        ?OR(I,$I,$i) andalso ?OR(F,$F,$f) ->
    {<<";",Rest0/binary>>, Pos0} = remove_spaces(Rest, add_pos(Pos,5)),
    {Rest0, add_pos(Pos0,1), lists:reverse(Parsed)};
code(<<E:8,N:8,D:8,F:8,O:8,R:8,E:8,A:8,C:8,H:8,Rest/binary>>,
     {foreach_old_block,_,_}=Pos, Parsed) when
        ?OR(E,$E,$e) andalso ?OR(N,$N,$n) andalso ?OR(D,$D,$d) andalso
        ?OR(F,$F,$f) andalso ?OR(O,$O,$o) andalso ?OR(R,$R,$r) andalso
        ?OR(A,$A,$a) andalso ?OR(C,$C,$c) andalso ?OR(H,$H,$h) ->
    {<<";",Rest0/binary>>, Pos0} = remove_spaces(Rest, add_pos(Pos,10)),
    {Rest0, add_pos(Pos0,1), lists:reverse(Parsed)};
code(<<E:8,N:8,D:8,F:8,O:8,R:8,Rest/binary>>,
     {for_old_block,_,_}=Pos, Parsed) when
        ?OR(E,$E,$e) andalso ?OR(N,$N,$n) andalso ?OR(D,$D,$d) andalso
        ?OR(F,$F,$f) andalso ?OR(O,$O,$o) andalso ?OR(R,$R,$r) ->
    {<<";",Rest0/binary>>, Pos0} = remove_spaces(Rest, add_pos(Pos,6)),
    {Rest0, add_pos(Pos0,1), lists:reverse(Parsed)};
code(<<E:8,N:8,D:8,W:8,H:8,I:8,L:8,E:8,Rest/binary>>,
     {while_old_block,_,_}=Pos, Parsed) when
        ?OR(E,$E,$e) andalso ?OR(N,$N,$n) andalso ?OR(D,$D,$d) andalso
        ?OR(W,$W,$w) andalso ?OR(H,$H,$h) andalso ?OR(I,$I,$i) andalso
        ?OR(L,$L,$l) ->
    {<<";",Rest0/binary>>, Pos0} = remove_spaces(Rest, add_pos(Pos,8)),
    {Rest0, add_pos(Pos0,1), lists:reverse(Parsed)};
code(<<";",_/binary>> = Rest, {code_statement,_,_}=Pos, Parsed) ->
    {Rest, add_pos(Pos,1), Parsed};
code(<<T:8,R:8,U:8,E:8,SP:8,Rest/binary>>, Pos, Parsed)
        when ?OR(T,$t,$T) andalso ?OR(R,$r,$R) andalso ?OR(U,$u,$U)
        andalso ?OR(E,$e,$E) andalso (?IS_SPACE(SP) orelse ?IS_NEWLINE(SP)) ->
    {Rest0, Pos0, Exp} = expression(Rest, Pos, [{op,[true]}]),
    code(Rest0, copy_level(Pos, Pos0), [Exp|Parsed]);
code(<<F:8,A:8,L:8,S:8,E:8,SP:8,Rest/binary>>, Pos, Parsed)
        when ?OR(F,$f,$F) andalso ?OR(A,$a,$A) andalso ?OR(L,$l,$L)
        andalso ?OR(S,$s,$S) andalso ?OR(E,$e,$E)
        andalso (?IS_SPACE(SP) orelse ?IS_NEWLINE(SP)) ->
    {Rest0, Pos0, Exp} = expression(Rest, Pos, [{op,[false]}]),
    code(Rest0, copy_level(Pos, Pos0), [Exp|Parsed]);
code(<<I:8,F:8,SP:8,Rest/binary>>, Pos, Parsed)
        when ?OR(I,$i,$I) andalso ?OR(F,$f,$F) andalso ?OR(SP,32,$() ->
    {Rest0, Pos0} = remove_spaces(<<SP:8,Rest/binary>>, Pos),
    {Rest1, Pos1, NewParsed} = st_if(Rest0, Pos0, Parsed),
    code(Rest1, copy_level(Pos,Pos1), NewParsed);
code(<<W:8,H:8,I:8,L:8,E:8,SP:8,Rest/binary>>, Pos, Parsed)
        when ?OR(W,$w,$W) andalso ?OR(H,$h,$H) andalso ?OR(I,$i,$I)
        andalso ?OR(L,$l,$L) andalso ?OR(E,$e,$E) andalso ?OR(SP,32,$() ->
    {Rest0, Pos0} = remove_spaces(<<SP:8,Rest/binary>>, add_pos(Pos,5)),
    {Rest1, Pos1, NewParsed} = st_while(Rest0, Pos0, Parsed),
    code(Rest1, copy_level(Pos,Pos1), NewParsed);
code(<<D:8,O:8,SP:8,Rest/binary>>, Pos, Parsed)
        when ?OR(D,$d,$D) andalso ?OR(O,$o,$O) andalso
        (?IS_SPACE(SP) orelse ?OR(SP,${,$:)) ->
    {Rest0, Pos0, [DoWhile]} = st_do_while(Rest, add_pos(Pos,3), []),
    code(Rest0, copy_level(Pos,Pos0), [DoWhile|Parsed]);
code(<<F:8,O:8,R:8,E:8,A:8,C:8,H:8,SP:8,Rest/binary>>, Pos, Parsed)
        when ?OR(F,$f,$F) andalso ?OR(O,$o,$O) andalso ?OR(R,$r,$R)
        andalso ?OR(E,$e,$E) andalso ?OR(A,$a,$A) andalso ?OR(C,$c,$C)
        andalso ?OR(H,$h,$H)
        andalso (?IS_SPACE(SP) orelse ?IS_NEWLINE(SP) orelse SP =:= $() ->
    {Rest0, Pos0} = remove_spaces(<<SP:8,Rest/binary>>,Pos),
    {Rest1, Pos1, NewParsed} = st_foreach(Rest0, Pos0, Parsed),
    code(Rest1, copy_level(Pos, Pos1), NewParsed);
code(<<F:8,O:8,R:8,SP:8,Rest/binary>>, Pos, Parsed)
        when ?OR(F,$f,$F) andalso ?OR(O,$o,$O) andalso ?OR(R,$r,$R)
        andalso (?IS_SPACE(SP) orelse ?IS_NEWLINE(SP) orelse SP =:= $() ->
    {Rest0, Pos0} = remove_spaces(<<SP:8,Rest/binary>>,Pos),
    {Rest1, Pos1, NewParsed} = st_for(Rest0, Pos0, Parsed),
    code(Rest1, copy_level(Pos, Pos1), NewParsed);
code(<<E:8,L:8,S:8,E:8,SP:8,_/binary>> = Rest, {if_old_block,_,_}=Pos, Parsed)
        when ?OR(E,$e,$E) andalso ?OR(L,$l,$L) andalso ?OR(S,$s,$S)
        andalso (SP =:= $: orelse ?IS_SPACE(SP) orelse ?OR(SP,$i,$I)) ->
    {Rest, Pos, Parsed};
code(<<E:8,L:8,S:8,E:8,SP:8,Rest/binary>>, Pos, [#if_block{}|_]=Parsed)
        when ?OR(E,$e,$E) andalso ?OR(L,$l,$L) andalso ?OR(S,$s,$S)
        andalso (?OR(SP,${,$:) orelse ?IS_SPACE(SP) orelse ?OR(SP,$i,$I)) ->
    {Rest0, Pos0} = remove_spaces(<<SP:8,Rest/binary>>, Pos),
    {Rest1, Pos1, NewParsed} = st_else(Rest0, Pos0, Parsed),
    code(Rest1, copy_level(Pos, Pos1), NewParsed);
code(<<S:8,W:8,I:8,T:8,C:8,H:8,SP:8,Rest/binary>>, Pos, Parsed) when
        ?OR(S,$S,$s) andalso ?OR(W,$W,$w) andalso ?OR(I,$I,$i) andalso
        ?OR(T,$T,$t) andalso ?OR(C,$C,$c) andalso ?OR(H,$H,$h) andalso
        (?IS_SPACE(SP) orelse ?IS_NEWLINE(SP) orelse SP =:= $() ->
    {<<"(",_/binary>> = Rest0, Pos0} = remove_spaces(<<SP:8,Rest/binary>>, Pos),
    {Rest1, Pos1, NewParsed} = st_switch(Rest0, add_pos(Pos0,6), Parsed),
    code(Rest1, copy_level(Pos, Pos1), NewParsed);
code(<<C:8,A:8,S:8,E:8,SP:8,Rest/binary>>, {switch_block,_,_}=Pos, Parsed) when
        ?OR(C,$C,$c) andalso ?OR(A,$A,$a) andalso ?OR(S,$S,$s) andalso
        ?OR(E,$E,$e) andalso (?IS_SPACE(SP) orelse ?IS_NEWLINE(SP)) ->
    {Rest0, Pos0} = remove_spaces(<<SP:8,Rest/binary>>, add_pos(Pos,4)),
    NewPos = switch_block_level(Pos0),
    {<<":",Rest1/binary>>, Pos1, Exp} = expression(Rest0, NewPos, []),
    NewParsed = [add_line(#switch_case{
        label=Exp,
        code_block=[]
    }, Pos)|switch_case_block(Parsed)],
    code(Rest1, copy_level(Pos, add_pos(Pos1,1)), NewParsed);
code(<<D:8,E:8,F:8,A:8,U:8,L:8,T:8,SP:8,Rest/binary>>,
     {switch_block,_,_}=Pos, Parsed) when
        ?OR(D,$D,$d) andalso ?OR(E,$E,$e) andalso ?OR(F,$F,$f) andalso
        ?OR(A,$A,$a) andalso ?OR(U,$U,$u) andalso ?OR(L,$L,$l) andalso
        ?OR(T,$T,$t) andalso
        (?IS_SPACE(SP) orelse ?IS_NEWLINE(SP) orelse SP =:= $:) ->
    {<<":",Rest0/binary>>, Pos0} = remove_spaces(<<SP:8,Rest/binary>>,
                                                 add_pos(Pos,4)),
    NewParsed = [add_line(#switch_case{
        label=default,
        code_block=[]
    }, Pos)|switch_case_block(Parsed)],
    code(Rest0, copy_level(Pos, add_pos(Pos0,1)), NewParsed);
code(<<E:8,C:8,H:8,O:8,SP:8,Rest/binary>>, Pos, Parsed)
        when ?OR(E,$e,$E) andalso ?OR(C,$c,$C) andalso ?OR(H,$h,$H)
        andalso ?OR(O,$o,$O) andalso ?OR(SP,32,$() ->
    {Rest0, Pos0, Exp} = expression(<<SP:8,Rest/binary>>,
                                     arg_level(add_pos(Pos,5)), []),
    % FIXME if we detect an OR or AND expression, we put around print
    Print = case Exp of
        #operation{type = Type} when Type =:= 'or' orelse Type =:= 'and' ->
            Exp#operation{
                expression_left = get_print(Exp#operation.expression_left, Pos)
            };
        _ ->
            get_print(Exp, Pos)
    end,
    code(Rest0, copy_level(Pos, Pos0), [Print|Parsed]);
code(<<P:8,R:8,I:8,N:8,T:8,SP:8,Rest/binary>>, Pos, Parsed)
        when ?OR(P,$p,$P) andalso ?OR(R,$r,$R) andalso ?OR(I,$i,$I)
        andalso ?OR(N,$n,$N) andalso ?OR(T,$t,$T) andalso ?OR(SP,32,$() ->
    {Rest0, Pos0, Exp} = expression(<<SP:8,Rest/binary>>,
                                     arg_level(add_pos(Pos,6)), []),
    % FIXME if we detect an OR or AND expression, we put around print
    Print = case Exp of
        #operation{type = Type} when Type =:= 'or' orelse Type =:= 'and' ->
            Exp#operation{
                expression_left = get_print(Exp#operation.expression_left, Pos)
            };
        _ ->
            get_print(Exp, Pos)
    end,
    code(Rest0, copy_level(Pos, Pos0), [Print|Parsed]);
code(<<C:8,O:8,N:8,S:8,T:8,SP:8,Rest/binary>>, Pos, Parsed)
        when ?OR(C,$c,$C) andalso ?OR(O,$o,$O) andalso ?OR(N,$n,$N)
        andalso ?OR(S,$s,$S) andalso ?OR(T,$t,$T) andalso ?IS_SPACE(SP) ->
    {Rest0, Pos0, #constant{}=Constant} =
        expression(Rest, add_pos(Pos,6), []),
    code(Rest0, copy_level(Pos, Pos0), [Constant|Parsed]);
code(<<F:8,U:8,N:8,C:8,T:8,I:8,O:8,N:8,SP:8,Rest/binary>>, Pos, Parsed) when
        ?OR(F,$F,$f) andalso ?OR(U,$U,$u) andalso ?OR(N,$N,$n) andalso
        ?OR(C,$C,$c) andalso ?OR(T,$T,$t) andalso ?OR(I,$I,$i) andalso
        ?OR(O,$O,$o) andalso ?IS_SPACE(SP) ->
    {Rest0, Pos0, [#function{}=Function]} =
        st_function(Rest, add_pos(Pos,9), []),
    code(Rest0, copy_level(Pos, Pos0), [Function|Parsed]);
code(<<F:8,U:8,N:8,C:8,T:8,I:8,O:8,N:8,SP:8,Rest/binary>>, Pos, Parsed) when
        ?OR(F,$F,$f) andalso ?OR(U,$U,$u) andalso ?OR(N,$N,$n) andalso
        ?OR(C,$C,$c) andalso ?OR(T,$T,$t) andalso ?OR(I,$I,$i) andalso
        ?OR(O,$O,$o) andalso ?IS_NEWLINE(SP) ->
    NewPos = new_line(add_pos(Pos,8)),
    {Rest0, Pos0, #function{}=Function} = st_function(Rest, NewPos, []),
    code(Rest0, copy_level(Pos, Pos0), [Function|Parsed]);
code(<<"?>\n",Rest/binary>>, {code_value,_,_}=Pos, [Parsed]) ->
    {Rest, add_pos(Pos,3), Parsed};
code(<<"?>",Rest/binary>>, {code_value,_,_}=Pos, [Parsed]) ->
    {Rest, add_pos(Pos,2), Parsed};
code(<<"?>\n",Rest/binary>>, {code_block,_,_}=Pos, Parsed) ->
    {Rest0, Pos0, Text} = document(Rest, literal_level(add_pos(Pos,3)), []),
    code(Rest0, copy_level(Pos,Pos0), Text ++ Parsed);
code(<<"?>",Rest/binary>>, {code_block,_,_}=Pos, Parsed) ->
    {Rest0, Pos0, Text} = document(Rest, literal_level(add_pos(Pos,2)), []),
    code(Rest0, copy_level(Pos,Pos0), Text ++ Parsed);
code(<<"?>\n",Rest/binary>>, Pos, Parsed) ->
    {Rest, add_pos(Pos,3), Parsed};
code(<<"?>",Rest/binary>>, Pos, Parsed) ->
    {Rest, add_pos(Pos,2), Parsed};
code(<<"//",Rest/binary>>, Pos, Parsed) ->
    {Rest0, Pos0, _} = comment_line(Rest, Pos, Parsed),
    code(Rest0, Pos0, Parsed);
code(<<"#",Rest/binary>>, Pos, Parsed) ->
    {Rest0, Pos0, _} = comment_line(Rest, Pos, Parsed),
    code(Rest0, Pos0, Parsed);
code(<<"/*",Rest/binary>>, Pos, Parsed) ->
    {Rest0, Pos0, _} = comment_block(Rest, Pos, Parsed),
    code(Rest0, Pos0, Parsed);
code(<<"<<<",_/binary>> = Rest, Pos, Parsed) ->
    {Rest0, Pos0, S} = string(Rest,Pos,[]),
    code(Rest0, copy_level(Pos, Pos0), [S|Parsed]);
code(<<I:8,N:8,C:8,L:8,U:8,D:8,E:8,SP:8,Rest/binary>>, Pos, Parsed) when
        ?OR(I,$I,$i) andalso ?OR(N,$N,$n) andalso ?OR(C,$C,$c) andalso
        ?OR(L,$L,$l) andalso ?OR(U,$U,$u) andalso ?OR(D,$D,$d) andalso
        ?OR(E,$E,$e) andalso ?OR(SP,$(,32) ->
    {Rest0, Pos0} = remove_spaces(<<SP:8,Rest/binary>>, add_pos(Pos, 7)),
    {Rest1, Pos1, Exp} = expression(Rest0, Pos0, []),
    Include = add_line(#call{name = <<"include">>, args=[Exp]}, Pos),
    code(Rest1, Pos1, [Include|Parsed]);
code(<<I:8,N:8,C:8,L:8,U:8,D:8,E:8,$_,O:8,N:8,C:8,E:8,SP:8,Rest/binary>>,
     Pos, Parsed) when
        ?OR(I,$I,$i) andalso ?OR(N,$N,$n) andalso ?OR(C,$C,$c) andalso
        ?OR(L,$L,$l) andalso ?OR(U,$U,$u) andalso ?OR(D,$D,$d) andalso
        ?OR(E,$E,$e) andalso ?OR(O,$O,$o) andalso ?OR(SP,$(,32) ->
    {Rest0, Pos0} = remove_spaces(<<SP:8,Rest/binary>>, add_pos(Pos, 7)),
    {Rest1, Pos1, Exp} = expression(Rest0, Pos0, []),
    Include = add_line(#call{name = <<"include_once">>, args=[Exp]}, Pos),
    code(Rest1, Pos1, [Include|Parsed]);
code(<<R:8,E:8,Q:8,U:8,I:8,R:8,E:8,SP:8,Rest/binary>>, Pos, Parsed) when
        ?OR(R,$R,$r) andalso ?OR(E,$E,$e) andalso ?OR(Q,$Q,$q) andalso
        ?OR(U,$U,$u) andalso ?OR(I,$I,$i) andalso ?OR(SP,$(,32) ->
    {Rest0, Pos0} = remove_spaces(<<SP:8,Rest/binary>>, add_pos(Pos, 7)),
    {Rest1, Pos1, Exp} = expression(Rest0, Pos0, []),
    Include = add_line(#call{name = <<"require">>, args=[Exp]}, Pos),
    code(Rest1, Pos1, [Include|Parsed]);
code(<<R:8,E:8,Q:8,U:8,I:8,R:8,E:8,$_,O:8,N:8,C:8,E:8,SP:8,Rest/binary>>,
     Pos, Parsed) when
        ?OR(R,$R,$r) andalso ?OR(E,$E,$e) andalso ?OR(Q,$Q,$q) andalso
        ?OR(U,$U,$u) andalso ?OR(I,$I,$i) andalso ?OR(O,$O,$o) andalso
        ?OR(N,$N,$n) andalso ?OR(C,$C,$c) andalso ?OR(SP,$(,32) ->
    {Rest0, Pos0} = remove_spaces(<<SP:8,Rest/binary>>, add_pos(Pos, 7)),
    {Rest1, Pos1, Exp} = expression(Rest0, Pos0, []),
    Include = add_line(#call{name = <<"require_once">>, args=[Exp]}, Pos),
    code(Rest1, Pos1, [Include|Parsed]);
code(<<A:8,_/binary>> = Rest, Pos, Parsed) when ?IS_ALPHA(A) orelse A =:= $_ ->
    {Rest0, Pos0, Parsed0} = constant(Rest,Pos,[]),
    code(Rest0, copy_level(Pos, Pos0), Parsed0 ++ Parsed);
code(<<A:8,_/binary>> = Rest, Pos, Parsed) when ?IS_NUMBER(A)
                                           orelse A =:= $- orelse A =:= $(
                                           orelse A =:= $" orelse A =:= $'
                                           orelse A =:= $$ orelse A =:= $+
                                           orelse A =:= 126 ->
    {Rest0, Pos0, Exp} = expression(Rest, Pos, []),
    code(Rest0, copy_level(Pos, Pos0), [Exp|Parsed]);
code(<<Space:8,Rest/binary>>, Pos, Parsed) when ?IS_SPACE(Space) ->
    code(Rest, add_pos(Pos,1), Parsed);
code(<<NewLine:8,Rest/binary>>, Pos, Parsed) when ?IS_NEWLINE(NewLine) ->
    code(Rest, new_line(Pos), Parsed);
code(<<";",Rest/binary>>, Pos, Parsed) ->
    code(Rest, add_pos(Pos,1), Parsed);
code(Text, Pos, _Parsed) ->
    throw_error(eparse, Pos, Text).

code_block(<<"{",Rest/binary>>, Pos, Parsed) ->
    code(Rest, code_block_level(add_pos(Pos,1)), Parsed);
code_block(<<":",Rest/binary>>, {if_block,_,_}=Pos, Parsed) ->
    code(Rest, if_old_block_level(add_pos(Pos,1)), Parsed);
code_block(<<":",Rest/binary>>, {foreach_block,_,_}=Pos, Parsed) ->
    code(Rest, foreach_old_block_level(add_pos(Pos,1)), Parsed);
code_block(<<":",Rest/binary>>, {for_block,_,_}=Pos, Parsed) ->
    code(Rest, for_old_block_level(add_pos(Pos,1)), Parsed);
code_block(<<":",Rest/binary>>, {while_block,_,_}=Pos, Parsed) ->
    code(Rest, while_old_block_level(add_pos(Pos,1)), Parsed);
code_block(<<SP:8,Rest/binary>>, Pos, Parsed) when ?IS_SPACE(SP) ->
    code_block(Rest, add_pos(Pos,1), Parsed);
code_block(<<SP:8,Rest/binary>>, Pos, Parsed) when ?IS_NEWLINE(SP) ->
    code_block(Rest, new_line(Pos), Parsed);
code_block(<<>>, Pos, Parsed) ->
    {<<>>, Pos, Parsed};
code_block(Rest, Pos, Parsed) ->
    code(Rest, code_statement_level(Pos), Parsed).

expression(<<A:8,R:8,R:8,A:8,Y:8,SP:8,Rest/binary>>, Pos, Parsed)
        when ?OR(A,$a,$A) andalso ?OR(R,$r,$R) andalso ?OR(Y,$y,$Y)
        andalso not (?IS_ALPHA(SP) orelse ?IS_NUMBER(SP) orelse SP =:= $_) ->
    NewPos = array_def_level(add_pos(Pos, 5)),
    {Rest1, Pos1, Content} = array_def(<<SP:8,Rest/binary>>, NewPos, []),
    NewParsed = add_op(add_line(#array{elements=Content}, Pos), Parsed),
    expression(Rest1, copy_level(Pos, Pos1), NewParsed);
expression(<<"[",Rest/binary>>, Pos, []) ->
    NewPos = array_def_54_level(add_pos(Pos, 1)),
    {Rest1, Pos1, Content} = array_def(Rest, NewPos, []),
    NewParsed = add_op(add_line(#array{elements=Content}, Pos), []),
    expression(Rest1, copy_level(Pos, Pos1), NewParsed);
expression(<<N:8,U:8,L:8,L:8,SP:8,Rest/binary>>, Pos, Parsed)
        when ?OR(N,$N,$n) andalso ?OR(U,$U,$u) andalso ?OR(L,$L,$l)
        andalso not (?IS_ALPHA(SP) orelse ?IS_NUMBER(SP) orelse SP =:= $_) ->
    expression(<<SP:8,Rest/binary>>, add_pos(Pos,4), add_op(undefined, Parsed));
expression(<<T:8,R:8,U:8,E:8,SP:8,Rest/binary>>, Pos, Parsed)
        when ?OR(T,$t,$T) andalso ?OR(R,$r,$R) andalso ?OR(U,$u,$U)
        andalso ?OR(E,$e,$E)
        andalso not (?IS_ALPHA(SP) orelse ?IS_NUMBER(SP) orelse SP =:= $_) ->
    expression(<<SP:8,Rest/binary>>, add_pos(Pos,4), add_op(true, Parsed));
expression(<<F:8,A:8,L:8,S:8,E:8,SP:8,Rest/binary>>, Pos, Parsed)
        when ?OR(F,$f,$F) andalso ?OR(A,$a,$A) andalso ?OR(L,$l,$L)
        andalso ?OR(S,$s,$S) andalso ?OR(E,$e,$E)
        andalso not (?IS_ALPHA(SP) orelse ?IS_NUMBER(SP) orelse SP =:= $_) ->
    expression(<<SP:8,Rest/binary>>, add_pos(Pos,5), add_op(false, Parsed));
expression(<<SP:8,Rest/binary>>, Pos, Parsed) when ?IS_SPACE(SP) ->
    expression(Rest, add_pos(Pos,1), Parsed);
expression(<<SP:8,Rest/binary>>, Pos, Parsed) when ?IS_NEWLINE(SP) ->
    expression(Rest, new_line(Pos), Parsed);
expression(<<"//",Rest/binary>>, Pos, Parsed) ->
    {Rest0, Pos0, _} = comment_line(Rest, Pos, Parsed),
    expression(Rest0, Pos0, Parsed);
expression(<<"#",Rest/binary>>, Pos, Parsed) ->
    {Rest0, Pos0, _} = comment_line(Rest, Pos, Parsed),
    expression(Rest0, Pos0, Parsed);
expression(<<"/*",Rest/binary>>, Pos, Parsed) ->
    {Rest0, Pos0, _} = comment_block(Rest, Pos, Parsed),
    expression(Rest0, Pos0, Parsed);
expression(<<"(",Rest/binary>>, Pos, [{op,[#variable{}=V]}|Parsed]) ->
    Call = #call{name = V, line = V#variable.line},
    {Rest0, Pos0, [Function]} = function(Rest, add_pos(Pos,1), [Call|Parsed]),
    expression(Rest0, copy_level(Pos, Pos0), add_op(Function, Parsed));
expression(<<"(",Rest/binary>>, {L,R,C}=Pos, Parsed) when not is_number(L) ->
    {Rest0, Pos0, Op} = expression(Rest, {1,R,C+1}, []),
    expression(Rest0, copy_level(Pos, Pos0), add_op(Op, Parsed));
expression(<<"(",Rest/binary>>, {L,R,C}=Pos, Parsed) ->
    {Rest0, Pos0, Op} = expression(Rest, {L+1,R,C+1}, []),
    expression(Rest0, copy_level(Pos, Pos0), add_op(Op, Parsed));
expression(<<";",Rest/binary>>, Pos, [{op,_}=Exp,#if_block{}=If]) ->
    IfBlock = If#if_block{
        true_block = add_op('end', [Exp])
    },
    {Rest, add_pos(Pos,1), IfBlock};
expression(<<A:8,_/binary>> = Rest, {arg,_,_}=Pos, Parsed)
        when A =:= $, orelse A =:= $) ->
    {Rest, add_pos(Pos,1), add_op('end', Parsed)};
expression(<<A:8,_/binary>> = Rest, {{array_def,0},_,_}=Pos, [Parsed])
        when A =:= $, orelse A =:= $) ->
    {Rest, add_pos(Pos,1), add_op('end', [Parsed])};
expression(<<A:8,_/binary>> = Rest, {{array_def,0},_,_}=Pos, Parsed)
        when A =:= $, orelse A =:= $) ->
    [Arg,Idx] = Parsed,
    {Rest, add_pos(Pos,1), [Idx,add_op('end', [Arg])]};
expression(<<A:8,_/binary>> = Rest, {{array_def,54},_,_}=Pos, [Parsed])
        when A =:= $, orelse A =:= $] ->
    {Rest, add_pos(Pos,1), add_op('end', [Parsed])};
expression(<<A:8,_/binary>> = Rest, {{array_def,54},_,_}=Pos, Parsed)
        when A =:= $, orelse A =:= $] ->
    [Arg,Idx] = Parsed,
    {Rest, add_pos(Pos,1), [Idx,add_op('end', [Arg])]};
expression(<<A:8,_/binary>> = Rest, {L,_,_}=Pos, Parsed)
        when not is_number(L) andalso (A =:= $) orelse A =:= $;) ->
    {Rest, add_pos(Pos,1), add_op('end', Parsed)};
% TODO: maybe we need to change the foreach_block for _arg...
expression(<<A:8,S:8,_/binary>> = Rest, {foreach_block,_,_}=Pos, Parsed)
        when ?OR(A,$a,$A) andalso ?OR(S,$s,$S) ->
    {Rest, Pos, add_op('end', Parsed)};
expression(<<")",Rest/binary>>, {L,_Row,_Col}=Pos, Parsed) when is_number(L) ->
    {Rest, add_pos(Pos,1), add_op('end', Parsed)};
expression(<<"]",Rest/binary>>, {array,_,_}=Pos, Parsed) ->
    {Rest, add_pos(Pos,1), add_op('end', Parsed)};
expression(<<"?>\n",_/binary>> = Rest, {L,_,_}=Pos, Parsed)
        when not is_number(L) ->
    {Rest, Pos, add_op('end', Parsed)};
expression(<<"?>",_/binary>> = Rest, {L,_,_}=Pos, Parsed)
        when not is_number(L) ->
    {Rest, Pos, add_op('end', Parsed)};
expression(<<"&$",Rest/binary>>, Pos, Parsed) ->
    {Rest0, Pos0, [Var]} = variable(Rest, add_pos(Pos,2), []),
    Ref = add_line(#ref{var=Var}, Pos),
    expression(Rest0, Pos0, add_op(Ref, Parsed));
expression(<<"$",Rest/binary>>, Pos, Parsed) ->
    {Rest0, Pos0, [Var]} = variable(Rest, add_pos(Pos,1), []),
    expression(Rest0, Pos0, add_op(Var, Parsed));
expression(<<A:8,_/binary>> = Rest, Pos, Parsed) when ?IS_NUMBER(A) ->
    {Rest0, Pos0, [Number]} = number(Rest, Pos, []),
    expression(Rest0, copy_level(Pos, Pos0), add_op(Number, Parsed));
expression(<<A:8,_/binary>> = Rest, Pos, Parsed) when
        A =:= $" orelse A =:= $' ->
    {Rest0, Pos0, String} = string(Rest, Pos, []),
    expression(Rest0, Pos0, add_op(String, Parsed));
expression(<<I:8,N:8,C:8,L:8,U:8,D:8,E:8,SP:8,Rest/binary>>, Pos, Parsed) when
        ?OR(I,$I,$i) andalso ?OR(N,$N,$n) andalso ?OR(C,$C,$c) andalso
        ?OR(L,$L,$l) andalso ?OR(U,$U,$u) andalso ?OR(D,$D,$d) andalso
        ?OR(E,$E,$e) andalso ?OR(SP,$(,32) ->
    {Rest0, Pos0} = remove_spaces(<<SP:8,Rest/binary>>, add_pos(Pos, 7)),
    {Rest1, Pos1, Exp} = expression(Rest0, Pos0, []),
    Include = add_line(#call{name = <<"include">>, args=[Exp]}, Pos),
    expression(Rest1, Pos1, add_op(Include, Parsed));
expression(<<I:8,N:8,C:8,L:8,U:8,D:8,E:8,$_,O:8,N:8,C:8,E:8,SP:8,Rest/binary>>,
     Pos, Parsed) when
        ?OR(I,$I,$i) andalso ?OR(N,$N,$n) andalso ?OR(C,$C,$c) andalso
        ?OR(L,$L,$l) andalso ?OR(U,$U,$u) andalso ?OR(D,$D,$d) andalso
        ?OR(E,$E,$e) andalso ?OR(O,$O,$o) andalso ?OR(SP,$(,32) ->
    {Rest0, Pos0} = remove_spaces(<<SP:8,Rest/binary>>, add_pos(Pos, 7)),
    {Rest1, Pos1, Exp} = expression(Rest0, Pos0, []),
    Include = add_line(#call{name = <<"include_once">>, args=[Exp]}, Pos),
    expression(Rest1, Pos1, add_op(Include, Parsed));
expression(<<R:8,E:8,Q:8,U:8,I:8,R:8,E:8,SP:8,Rest/binary>>, Pos, Parsed) when
        ?OR(R,$R,$r) andalso ?OR(E,$E,$e) andalso ?OR(Q,$Q,$q) andalso
        ?OR(U,$U,$u) andalso ?OR(I,$I,$i) andalso ?OR(SP,$(,32) ->
    {Rest0, Pos0} = remove_spaces(<<SP:8,Rest/binary>>, add_pos(Pos, 7)),
    {Rest1, Pos1, Exp} = expression(Rest0, Pos0, []),
    Include = add_line(#call{name = <<"require">>, args=[Exp]}, Pos),
    expression(Rest1, Pos1, add_op(Include, Parsed));
expression(<<R:8,E:8,Q:8,U:8,I:8,R:8,E:8,$_,O:8,N:8,C:8,E:8,SP:8,Rest/binary>>,
     Pos, Parsed) when
        ?OR(R,$R,$r) andalso ?OR(E,$E,$e) andalso ?OR(Q,$Q,$q) andalso
        ?OR(U,$U,$u) andalso ?OR(I,$I,$i) andalso ?OR(O,$O,$o) andalso
        ?OR(N,$N,$n) andalso ?OR(C,$C,$c) andalso ?OR(SP,$(,32) ->
    {Rest0, Pos0} = remove_spaces(<<SP:8,Rest/binary>>, add_pos(Pos, 7)),
    {Rest1, Pos1, Exp} = expression(Rest0, Pos0, []),
    Include = add_line(#call{name = <<"require_once">>, args=[Exp]}, Pos),
    expression(Rest1, Pos1, add_op(Include, Parsed));
expression(<<A:1/binary,"=",Rest/binary>>, Pos, [{op,[#variable{}=V]}|_])
        when ?IS_OP1_ARITH(A) ->
    NewPos = code_statement_level(add_pos(Pos,2)),
    {Rest0, Pos0, Exp} = expression(Rest, NewPos, []),
    Op = add_line(operator(A,V,Exp), Pos),
    Assign = add_line(#assign{variable=V, expression=Op}, Pos),
    {Rest0, Pos0, Assign};
expression(<<A:8,N:8,D:8,SP:8,Rest/binary>>, Pos, Parsed)
        when ?OR(A,$a,$A) andalso ?OR(N,$n,$N) andalso ?OR(D,$d,$D)
        andalso (not (?IS_ALPHA(SP) orelse ?IS_NUMBER(SP))) ->
    OpL = <<"and">>,
    expression(Rest, add_pos(Pos,3), add_op({OpL,precedence(OpL),Pos}, Parsed));
expression(<<X:8,O:8,R:8,SP:8,Rest/binary>>, Pos, Parsed)
        when ?OR(X,$x,$X) andalso ?OR(O,$o,$O) andalso ?OR(R,$r,$R)
        andalso (not (?IS_ALPHA(SP) orelse ?IS_NUMBER(SP))) ->
    OpL = <<"xor">>,
    expression(Rest, add_pos(Pos,3), add_op({OpL,precedence(OpL),Pos}, Parsed));
expression(<<Op:3/binary,Rest/binary>>, Pos, Parsed) when ?IS_OP3(Op) ->
    OpL = ephp_string:to_lower(Op),
    expression(Rest, add_pos(Pos,3), add_op({OpL,precedence(OpL),Pos}, Parsed));
expression(<<O:8,R:8,SP:8,Rest/binary>>, Pos, Parsed)
        when ?OR(O,$o,$O) andalso ?OR(R,$r,$R)
        andalso (not (?IS_ALPHA(SP) orelse ?IS_NUMBER(SP))) ->
    OpL = <<"or">>,
    expression(Rest, add_pos(Pos,2), add_op({OpL,precedence(OpL),Pos}, Parsed));
expression(<<Op:2/binary,Rest/binary>>, Pos, Parsed) when ?IS_OP2(Op) ->
    OpL = ephp_string:to_lower(Op),
    expression(Rest, add_pos(Pos,2), add_op({OpL,precedence(OpL),Pos}, Parsed));
expression(<<Op:1/binary,Rest/binary>>, Pos, Parsed) when ?IS_OP1(Op) ->
    expression(Rest, add_pos(Pos,1), add_op({Op,precedence(Op),Pos}, Parsed));
expression(<<A:8,_/binary>> = Rest, {L,_,_}=Pos, Parsed) when
        ?IS_ALPHA(A) orelse A =:= $_ ->
    {Rest0, {_,R,C}, [Constant]} = constant(Rest, Pos, []),
    expression(Rest0, {L,R,C}, add_op(Constant, Parsed));
expression(<<"=>",Rest/binary>>, {{array_def,_},_,_}=Pos, [{op,_}=Op|Parser]) ->
    expression(Rest, add_pos(Pos,2), [{op,[]},add_op('end', [Op])|Parser]);
%% TODO support for list(...) = ...
expression(<<"=",Rest/binary>>, Pos, [{op,[#variable{}=V]}|_]) ->
    NewPos = code_statement_level(add_pos(Pos,1)),
    {Rest0, Pos0, Exp} = expression(Rest, NewPos, []),
    Assign = add_line(#assign{variable=V, expression=Exp}, Pos),
    {Rest0, Pos0, Assign};
expression(<<"=",Rest/binary>>, Pos, [{op,[#constant{}=C]}|_]) ->
    NewPos = code_statement_level(add_pos(Pos,1)),
    {Rest0, Pos0, Exp} = expression(Rest, NewPos, []),
    Constant = add_line(C#constant{type=define, value=Exp}, Pos),
    {Rest0, Pos0, Constant};
expression(<<"?",Rest/binary>>, Pos, [{op,_}]=Exp) ->
    expression(Rest, add_pos(Pos,1), [#if_block{conditions=add_op('end', Exp)}]);
expression(<<":",Rest/binary>>, Pos, [{op,_}=Exp,#if_block{}=If]) ->
    {Rest1, Pos1, ElseExp} = expression(Rest, add_pos(Pos,1), []),
    IfBlock = If#if_block{
        true_block = add_op('end', [Exp]),
        false_block = ElseExp
    },
    {Rest1, copy_level(Pos, Pos1), IfBlock};
expression(<<":",_/binary>> = Rest, {switch_block,_,_}=Pos, [Exp]) ->
    {Rest, Pos, add_op('end', [Exp])};
expression(<<>>, Pos, _Parsed) ->
    throw_error(eparse, Pos, <<>>).

variable(<<SP:8,Rest/binary>>, Pos, []) when ?IS_SPACE(SP) ->
    variable(Rest, add_pos(Pos,1), []);
variable(<<SP:8,Rest/binary>>, Pos, []) when ?IS_NEWLINE(SP) ->
    variable(Rest, new_line(Pos), []);
variable(<<"$",Rest/binary>>, Pos, []) ->
    variable(Rest, add_pos(Pos,1), []);
variable(<<A:8,Rest/binary>>, Pos, [])
        when ?IS_ALPHA(A) orelse A =:= $_ orelse A >= 16#7f ->
    Var = add_line(#variable{name = <<A:8>>}, Pos),
    variable(Rest, add_pos(Pos,1), [Var]);
variable(<<A:8,Rest/binary>>, {_,_,_}=Pos, [#variable{name=N}=V])
        when ?IS_NUMBER(A) orelse ?IS_ALPHA(A) orelse A =:= $_
        orelse A >= 16#7f ->
    variable(Rest, add_pos(Pos,1), [V#variable{name = <<N/binary,A:8>>}]);
variable(<<SP:8,Rest/binary>>, {enclosed,_,_}=Pos, Var) when ?IS_SPACE(SP) ->
    variable(Rest, add_pos(Pos,1), Var);
variable(<<SP:8,Rest/binary>>, {enclosed,_,_}=Pos, Var) when ?IS_NEWLINE(SP) ->
    variable(Rest, add_pos(Pos,1), Var);
variable(<<"}",Rest/binary>>, {enclosed,_,_}=Pos, Var) ->
    {Rest, add_pos(Pos,1), Var};
variable(<<"[",Rest/binary>>, Pos, [#variable{idx=Indexes}=Var]) ->
    {Rest1, Pos1, RawIdx} = expression(Rest, array_level(add_pos(Pos,1)), []),
    Idx = case RawIdx of
        [] -> auto;
        _ -> RawIdx
    end,
    variable(Rest1, copy_level(Pos, Pos1), [Var#variable{idx=Indexes ++ [Idx]}]);
variable(Rest, Pos, Parsed) ->
    {Rest, Pos, Parsed}.

number(<<A:8,Rest/binary>>, Pos, []) when ?IS_NUMBER(A) orelse A =:= $- ->
    number(Rest, add_pos(Pos,1), [add_line(#int{int = <<A:8>>}, Pos)]);
number(<<A:8,Rest/binary>>, Pos, [#int{int=N}=I]) when ?IS_NUMBER(A) ->
    number(Rest, add_pos(Pos,1), [I#int{int = <<N/binary,A:8>>}]);
number(<<".",Rest/binary>>, Pos, [#int{int=N,line=Line}]) ->
    number(Rest, add_pos(Pos,1), [#float{float = <<N/binary,".">>,line=Line}]);
number(<<A:8,Rest/binary>>, Pos, [#float{float=N}=F]) when ?IS_NUMBER(A) ->
    number(Rest, add_pos(Pos,1), [F#float{float = <<N/binary,A:8>>}]);
number(Rest, Pos, [#int{int=N}=I]) ->
    {Rest, Pos, [I#int{int=binary_to_integer(N)}]};
number(Rest, Pos, [#float{float=N}=F]) ->
    {Rest, Pos, [F#float{float=binary_to_float(N)}]}.

constant(<<A:8,Rest/binary>>, Pos, []) when ?IS_ALPHA(A) orelse A =:= $_ ->
    constant(Rest, add_pos(Pos,1), [add_line(#constant{name = <<A:8>>},Pos)]);
constant(<<A:8,Rest/binary>>, Pos, [#constant{name=N}=C])
        when ?IS_ALPHA(A) orelse ?IS_NUMBER(A) orelse A =:= $_ ->
    constant(Rest, add_pos(Pos,1), [C#constant{name = <<N/binary, A:8>>}]);
constant(<<SP:8,Rest/binary>>, Pos, [#constant{}|_]=Parsed)
        when ?IS_SPACE(SP) ->
    constant_wait(Rest, add_pos(Pos,1), Parsed);
constant(<<SP:8,Rest/binary>>, Pos, [#constant{}|_]=Parsed)
        when ?IS_NEWLINE(SP) ->
    constant_wait(Rest, new_line(Pos), Parsed);
constant(<<"(",_/binary>> = Rest, Pos, Parsed) ->
    constant_wait(Rest, Pos, Parsed);
constant(Rest, Pos, Parsed) ->
    {Rest, Pos, constant_known(Parsed, Pos)}.

%% if after one or several spaces there are a parens, it's a function
%% but if not, it should returns
constant_wait(<<"(",Rest/binary>>, Pos, [#constant{}=C|Parsed]) ->
    Call = #call{name = C#constant.name, line = C#constant.line},
    function(Rest, add_pos(Pos,1), [Call|Parsed]);
constant_wait(<<SP:8,Rest/binary>>, Pos, [#constant{}|_]=Parsed)
        when ?IS_SPACE(SP) ->
    constant_wait(Rest, add_pos(Pos,1), Parsed);
constant_wait(<<SP:8,Rest/binary>>, Pos, [#constant{}|_]=Parsed)
        when ?IS_NEWLINE(SP) ->
    constant_wait(Rest, new_line(Pos), Parsed);
constant_wait(Rest, Pos, Parsed) ->
    {Rest, Pos, constant_known(Parsed, Pos)}.

constant_known([#constant{name = <<"__LINE__">>}|Parsed], {_,R,_}=Pos) ->
    [add_line(#int{int=R}, Pos)|Parsed];
constant_known(C, _Pos) ->
    C.

array_def(<<SP:8,Rest/binary>>, Pos, Args) when ?IS_SPACE(SP) ->
    array_def(Rest, add_pos(Pos,1), Args);
array_def(<<SP:8,Rest/binary>>, Pos, Args) when ?IS_NEWLINE(SP) ->
    array_def(Rest, new_line(Pos), Args);
array_def(<<")",Rest/binary>>, {{array_def,0},_,_}=Pos, Args) ->
    {Rest,add_pos(Pos,1),Args};
array_def(<<"]",Rest/binary>>, {{array_def,54},_,_}=Pos, Args) ->
    {Rest,add_pos(Pos,1),Args};
%% TODO add error missing closing params
array_def(<<"(",Rest/binary>>, Pos, []) ->
    array_def(Rest, add_pos(Pos,1), []);
array_def(Rest, Pos, Args) when Rest =/= <<>> ->
    case expression(Rest, Pos, []) of
        {<<")",Rest0/binary>>, {{array_def,0},_,_}=Pos0, []} ->
            {Rest0, add_pos(Pos0,1), Args};
        {<<")",Rest0/binary>>, {{array_def,0},_,_}=Pos0, [Idx,Arg]} ->
            NewArg = add_line(#array_element{idx=Idx, element=Arg}, Pos),
            {Rest0, add_pos(Pos0,1), Args ++ [NewArg]};
        {<<")",Rest0/binary>>, {{array_def,0},_,_}=Pos0, Arg} ->
            NewArg = add_line(#array_element{element=Arg}, Pos),
            {Rest0, add_pos(Pos0,1), Args ++ [NewArg]};
        {<<"]",Rest0/binary>>, {{array_def,54},_,_}=Pos0, []} ->
            {Rest0, add_pos(Pos0,1), Args};
        {<<"]",Rest0/binary>>, {{array_def,54},_,_}=Pos0, [Idx,Arg]} ->
            NewArg = add_line(#array_element{idx=Idx, element=Arg}, Pos),
            {Rest0, add_pos(Pos0,1), Args ++ [NewArg]};
        {<<"]",Rest0/binary>>, {{array_def,54},_,_}=Pos0, Arg} ->
            NewArg = add_line(#array_element{element=Arg}, Pos),
            {Rest0, add_pos(Pos0,1), Args ++ [NewArg]};
        {<<",",Rest0/binary>>, Pos0, [Idx,Arg]} ->
            NewArg = add_line(#array_element{idx=Idx, element=Arg}, Pos),
            array_def(Rest0, add_pos(Pos0, 1), Args ++ [NewArg]);
        {<<",",Rest0/binary>>, Pos0, Arg} ->
            NewArg = add_line(#array_element{element=Arg}, Pos),
            array_def(Rest0, add_pos(Pos0, 1), Args ++ [NewArg]);
        {Rest0, Pos0, []} ->
            array_def(Rest0, Pos0, Args);
        {Rest0, Pos0, Arg} ->
            array_def(Rest0, Pos0, Args ++ [Arg])
    end.

function(<<SP:8,Rest/binary>>, Pos, [#call{}|_]=Parsed) when ?IS_SPACE(SP) ->
    function(Rest, add_pos(Pos,1), Parsed);
function(<<SP:8,Rest/binary>>, Pos, [#call{}|_]=Parsed) when ?IS_NEWLINE(SP) ->
    function(Rest, new_line(Pos), Parsed);
function(<<")",Rest/binary>>, Pos, Parsed) ->
    {Rest,add_pos(Pos,1),Parsed};
%% TODO error missing closing params
function(Rest, Pos, [#call{args=Args}=C|Parsed]) when Rest =/= <<>> ->
    case expression(Rest, arg_level(Pos), []) of
        {<<")",Rest0/binary>>, Pos0, []} ->
            {Rest0, add_pos(Pos0,1), [C|Parsed]};
        {<<")",Rest0/binary>>, Pos0, Arg} ->
            {Rest0, add_pos(Pos0,1), [C#call{args=Args ++ [Arg]}|Parsed]};
        {<<",",Rest0/binary>>, Pos0, Arg} ->
            NewCall = C#call{args=Args ++ [Arg]},
            function(Rest0, add_pos(Pos0, 1), [NewCall|Parsed]);
        %% TODO error missing closing params
        {Rest0, Pos0, []} ->
            function(Rest0, Pos0, [C|Parsed]);
        {Rest0, Pos0, Arg} ->
            function(Rest0, Pos0, [C#call{args=Args ++ [Arg]}|Parsed])
    end.

string(<<"\"",Rest/binary>>, Pos, []) ->
    string_parsed(Rest, Pos, add_line(#text_to_process{text=[]}, Pos));
string(<<"'",Rest/binary>>, Pos, []) ->
    string_fixed(Rest, Pos, add_line(#text{text = <<>>}, Pos));
string(<<"<<<'",Rest/binary>>, {Level,Row,_}=Pos, []) ->
    [W,Rest0] = binary:split(Rest, <<"'">>),
    [Text,Rest1] = binary:split(Rest0, <<"\n", W/binary, ";">>),
    NPos = {Level,Row+length(binary:matches(Text,<<"\n">>)),1},
    {Rest1, add_pos(NPos,byte_size(W)+1), add_line(#text{text=Text}, Pos)};
string(<<"<<<",Rest/binary>>, Pos, []) ->
    [W,Rest0] = binary:split(Rest, <<"\n">>),
    Wsize = byte_size(W),
    [RawText,Rest1] = binary:split(Rest0, <<"\n", W/binary, ";">>),
    case heredoc(RawText, add_pos(Pos,Wsize+4), []) of
        {Pos2, [Text]} when is_binary(Text) ->
            {Rest1, Pos2, add_line(#text{text=Text}, Pos)};
        {Pos2, Text} ->
            {Rest1, Pos2, add_line(#text_to_process{text=Text}, Pos)}
    end.

heredoc(<<>>, Pos, C) ->
    {Pos, lists:reverse(C)};
heredoc(<<"${",Rest/binary>>, {Level,Row,Col}, C) ->
    {Rest0, {_,Row0,Col0}, [Var]} = variable(Rest, {enclosed,Row,Col+2}, []),
    heredoc(Rest0, {Level,Row0,Col0}, [Var|C]);
heredoc(<<"{$",Rest/binary>>, {Level,Row,Col}, C) ->
    {Rest0, {_,Row0,Col0}, [Var]} = variable(Rest, {enclosed,Row,Col+2}, []),
    heredoc(Rest0, {Level,Row0,Col0}, [Var|C]);
heredoc(<<"$",Rest/binary>>, {Level,Row,Col}, C) ->
    {Rest0, {_,Row0,Col0}, [Var]} = variable(Rest, {Level,Row,Col+1}, []),
    heredoc(Rest0, {Level,Row0,Col0}, [Var|C]);
heredoc(<<"\n",Rest/binary>>, Pos, [C|R]) when is_binary(C) ->
    heredoc(Rest, new_line(Pos), [<<C/binary, "\n">>|R]);
heredoc(<<A/utf8,Rest/binary>>, Pos, [C|R]) when is_binary(C) ->
    heredoc(Rest, add_pos(Pos,1), [<<C/binary, A/utf8>>|R]);
heredoc(Rest, Pos, [C|_]=S) when not is_binary(C) ->
    heredoc(Rest, Pos, [<<>>|S]).

string_fixed(<<"\\\\",Rest/binary>>, Pos, #text{text=C}=S) ->
    string_fixed(Rest, add_pos(Pos,1), S#text{text = <<C/binary, "\\\\">>});
string_fixed(<<"\\'",Rest/binary>>, Pos, #text{text=C}=S) ->
    string_fixed(Rest, add_pos(Pos,1), S#text{text = <<C/binary, "\\'">>});
string_fixed(<<"'",Rest/binary>>, Pos, Parsed) ->
    {Rest, add_pos(Pos,1), Parsed};
string_fixed(<<"\n",Rest/binary>>, Pos, #text{text=C}=S) ->
    string_fixed(Rest, new_line(Pos), S#text{text = <<C/binary, "\n">>});
string_fixed(<<A/utf8,Rest/binary>>, Pos, #text{text=C}=S) ->
    string_fixed(Rest, add_pos(Pos,1), S#text{text = <<C/binary, A/utf8>>}).

string_parsed(<<"\\\\",Rest/binary>>, Pos, #text_to_process{text=[C|R]}=S)
        when is_binary(C) ->
    NewText = S#text_to_process{text = [<<C/binary, "\\\\">>|R]},
    string_parsed(Rest, add_pos(Pos,1), NewText);
string_parsed(<<"\\\"",Rest/binary>>, Pos, #text_to_process{text=[C|R]}=S)
        when is_binary(C) ->
    NewText = S#text_to_process{text = [<<C/binary, "\\\"">>|R]},
    string_parsed(Rest, add_pos(Pos,1), NewText);
string_parsed(<<"\\$",Rest/binary>>, Pos, #text_to_process{text=[C|R]}=S)
        when is_binary(C) ->
    NewText = S#text_to_process{text = [<<C/binary, "$">>|R]},
    string_parsed(Rest, add_pos(Pos,2), NewText);
string_parsed(<<"\"",Rest/binary>>, Pos, #text_to_process{text=[C]}=S)
        when is_binary(C) ->
    {Rest, add_pos(Pos,1), #text{text=C, line=S#text_to_process.line}};
string_parsed(<<"\"",Rest/binary>>, Pos, #text_to_process{text=C}=S) ->
    {Rest, add_pos(Pos,1), S#text_to_process{text=lists:reverse(C)}};
string_parsed(<<"\\n",Rest/binary>>, Pos, #text_to_process{text=T}=S) ->
    NewT = case T of
        [C|R] when is_binary(C) ->
            [<<C/binary, $\n>>|R];
        T ->
            [<<$\n>>|T]
    end,
    string_parsed(Rest, add_pos(Pos,2), S#text_to_process{text=NewT});
string_parsed(<<"\\t",Rest/binary>>, Pos, #text_to_process{text=T}=S) ->
    NewT = case T of
        [C|R] when is_binary(C) ->
            [<<C/binary, $\t>>|R];
        T ->
            [<<$\t>>|T]
    end,
    string_parsed(Rest, add_pos(Pos,2), S#text_to_process{text=NewT});
string_parsed(<<"\\r",Rest/binary>>, Pos, #text_to_process{text=T}=S) ->
    NewT = case T of
        [C|R] when is_binary(C) ->
            [<<C/binary, $\r>>|R];
        T ->
            [<<$\r>>|T]
    end,
    string_parsed(Rest, add_pos(Pos,2), S#text_to_process{text=NewT});
string_parsed(<<"\n",Rest/binary>>, Pos, #text_to_process{text=[C|R]}=S)
        when is_binary(C) ->
    NewText = S#text_to_process{text = [<<C/binary, "\n">>|R]},
    string_parsed(Rest, new_line(Pos), NewText);
string_parsed(<<"${",Rest/binary>>, {Level,Row,Col},
              #text_to_process{text=C}=S) ->
    {Rest0, {_,Row0,Col0}, [Var]} = variable(Rest, {enclosed,Row,Col+2}, []),
    NewText = S#text_to_process{text=[Var|C]},
    string_parsed(Rest0, {Level,Row0,Col0}, NewText);
string_parsed(<<"{$",Rest/binary>>, {Level,Row,Col},
              #text_to_process{text=C}=S) ->
    {Rest0, {_,Row0,Col0}, [Var]} = variable(Rest, {enclosed,Row,Col+2}, []),
    NewText = S#text_to_process{text=[Var|C]},
    string_parsed(Rest0, {Level,Row0,Col0}, NewText);
string_parsed(<<"$",Rest/binary>>, {Level,Row,Col},
              #text_to_process{text=C}=S) ->
    {Rest0, {_,Row0,Col0}, [Var]} = variable(Rest, {Level,Row,Col+1}, []),
    NewText = S#text_to_process{text=[Var|C]},
    string_parsed(Rest0, {Level,Row0,Col0}, NewText);
string_parsed(<<A/utf8,Rest/binary>>, Pos, #text_to_process{text=[C|R]}=S)
        when is_binary(C) ->
    NewText = S#text_to_process{text = [<<C/binary, A/utf8>>|R]},
    string_parsed(Rest, add_pos(Pos,1), NewText);
string_parsed(Rest, Pos, #text_to_process{text=C}=S)
        when not is_binary(C) ->
    string_parsed(Rest, Pos, S#text_to_process{text=[<<>>|C]}).

st_global(<<SP:8,Rest/binary>>, Pos, Parsed) when ?IS_SPACE(SP) ->
    st_global(Rest, add_pos(Pos,1), Parsed);
st_global(<<SP:8,Rest/binary>>, Pos, Parsed) when ?IS_NEWLINE(SP) ->
    st_global(Rest, new_line(Pos), Parsed);
st_global(<<",",Rest/binary>>, Pos, Parsed) ->
    st_global(Rest, add_pos(Pos,1), Parsed);
st_global(<<";",Rest/binary>>, Pos, Parsed) ->
    Global = add_line(#global{vars = Parsed}, Pos),
    {Rest, add_pos(Pos,1), [Global]};
st_global(<<"$",_/binary>> = Rest, Pos, Parsed) ->
    {Rest0, Pos0, [Var]} = variable(Rest, Pos, []),
    st_global(Rest0, Pos0, [Var|Parsed]).

st_function(<<SP:8,Rest/binary>>, Pos, Parsed) when ?IS_SPACE(SP) ->
    st_function(Rest, add_pos(Pos,1), Parsed);
st_function(<<SP:8,Rest/binary>>, Pos, Parsed) when ?IS_NEWLINE(SP) ->
    st_function(Rest, new_line(Pos), Parsed);
% TODO if the following char is '(' maybe this is a anon-function
st_function(Rest, Pos, Parsed) ->
    {Rest0, Pos0, Name} = funct_name(Rest, Pos, []),
    {<<"(",Rest1/binary>>, Pos1} = remove_spaces(Rest0, Pos0),
    {Rest2, Pos2, Args} = funct_args(Rest1, Pos1, []),
    {Rest3, Pos3, CodeBlock} = code_block(Rest2, Pos2, []),
    Function = add_line(#function{
        name = Name,
        args = Args,
        code = CodeBlock
    }, Pos),
    {Rest3, copy_level(Pos, Pos3), [Function|Parsed]}.

funct_name(<<A:8,Rest/binary>>, Pos, []) when ?IS_ALPHA(A) ->
    funct_name(Rest, add_pos(Pos,1), [<<A:8>>]);
funct_name(<<A:8,Rest/binary>>, Pos, [N])
        when ?IS_ALPHA(A) orelse ?IS_NUMBER(A) orelse A =:= $_ ->
    funct_name(Rest, add_pos(Pos,1), [<<N/binary, A:8>>]);
funct_name(Rest, Pos, [N]) ->
    {Rest, Pos, N}.

funct_args(<<SP:8,Rest/binary>>, Pos, Parsed) when ?IS_SPACE(SP) ->
    funct_args(Rest, add_pos(Pos,1), Parsed);
funct_args(<<SP:8,Rest/binary>>, Pos, Parsed) when ?IS_NEWLINE(SP) ->
    funct_args(Rest, new_line(Pos), Parsed);
funct_args(<<"&",Rest/binary>>, Pos, Parsed) ->
    {Rest0, Pos0, [Var|Parsed0]} = funct_args(Rest, Pos, Parsed),
    {Rest0, Pos0, [add_line(#ref{var=Var}, Pos)|Parsed0]};
funct_args(<<",",Rest/binary>>, Pos, Parsed) ->
    funct_args(Rest, add_pos(Pos,1), Parsed);
funct_args(<<")",Rest/binary>>, Pos, Parsed) ->
    {Rest, add_pos(Pos,1), lists:reverse(Parsed)};
funct_args(Rest, Pos, Parsed) ->
    {Rest0, Pos0, [Var]} = variable(Rest, Pos, []),
    case remove_spaces(Rest0, Pos0) of
        {<<"=",Rest1/binary>>, Pos1} ->
            NewPos = arg_level(add_pos(Pos1,1)),
            {Rest2, Pos2, Default} = expression(Rest1, NewPos, []),
            NewVar = add_line(Var#variable{default_value = Default}, Pos),
            funct_args(Rest2, copy_level(Pos, Pos2), [NewVar|Parsed]);
        {Rest1, Pos1} ->
            funct_args(Rest1, add_pos(Pos1,1), [Var|Parsed])
    end.

st_while(<<SP:8,Rest/binary>>, Pos, Parsed) when ?IS_SPACE(SP) ->
    st_while(Rest, add_pos(Pos,1), Parsed);
st_while(<<SP:8,Rest/binary>>, Pos, Parsed) when ?IS_NEWLINE(SP) ->
    st_while(Rest, new_line(Pos), Parsed);
st_while(<<"(",Rest/binary>>, Pos, Parsed) ->
    NewPos = add_pos(Pos,1),
    {<<")",Rest1/binary>>, Pos1, Conditions} =
        expression(Rest, arg_level(NewPos), []),
    {Rest2, Pos2, CodeBlock} = code_block(Rest1, while_block_level(Pos1), []),
    While = add_line(#while{
        type=pre,
        conditions=Conditions,
        loop_block=CodeBlock
    }, Pos),
    {Rest2, copy_level(Pos, Pos2), [While|Parsed]};
st_while(<<>>, Pos, _Parsed) ->
    throw_error(eparse, Pos, <<>>).

st_do_while(Rest, Pos, Parsed) ->
    case code_block(Rest, Pos, []) of
        {<<";",Rest0/binary>>, Pos0, CodeBlock} -> ok;
        {Rest0, Pos0, CodeBlock} -> ok
    end,
    {<<WhileRaw:5/binary,Rest1/binary>>, Pos1} = remove_spaces(Rest0, Pos0),
    <<"while">> = ephp_string:to_lower(WhileRaw),
    {Rest2, Pos2, [While]} = st_while(Rest1, Pos1, []),
    DoWhile = add_line(While#while{
        type=post,
        loop_block=CodeBlock
    }, Pos),
    {Rest2, copy_level(Pos, Pos2), [DoWhile|Parsed]}.

st_if(<<SP:8,Rest/binary>>, Pos, Parsed) when ?IS_SPACE(SP) ->
    st_if(Rest, add_pos(Pos,1), Parsed);
st_if(<<SP:8,Rest/binary>>, Pos, Parsed) when ?IS_NEWLINE(SP) ->
    st_if(Rest, new_line(Pos), Parsed);
st_if(<<"(",Rest/binary>>, Pos, Parsed) ->
    NewPos = add_pos(Pos,1),
    {<<")",Rest1/binary>>, Pos1, Conditions} =
        expression(Rest, arg_level(NewPos), []),
    {Rest2, Pos2, CodeBlock} = code_block(Rest1, if_block_level(Pos1), []),
    If = add_line(#if_block{
        conditions=Conditions,
        true_block=CodeBlock
    }, Pos),
    {Rest2, copy_level(Pos, Pos2), [If|Parsed]};
st_if(<<>>, Pos, _Parsed) ->
    throw_error(eparse, Pos, <<>>).

st_else(<<SP:8,Rest/binary>>, Pos, Parsed) when ?IS_SPACE(SP) ->
    st_else(Rest, add_pos(Pos,1), Parsed);
st_else(<<SP:8,Rest/binary>>, Pos, Parsed) when ?IS_NEWLINE(SP) ->
    st_else(Rest, new_line(Pos), Parsed);
st_else(Rest0, {Level,_,_}=Pos0, [#if_block{}=If|Parsed]) ->
    BlockPos = if_block_level(add_pos(Pos0,4)),
    {Rest1, {_,Row1,Col1}, CodeBlock} = code_block(Rest0, BlockPos, []),
    IfWithElse = If#if_block{false_block=CodeBlock},
    {Rest1, {Level,Row1,Col1}, [IfWithElse|Parsed]};
st_else(<<>>, Pos, _Parsed) ->
    throw_error(eparse, Pos, <<>>).

args(<<SP:8,Rest/binary>>, Pos, Parsed) when ?IS_SPACE(SP) ->
    args(Rest, add_pos(Pos,1), Parsed);
args(<<SP:8,Rest/binary>>, Pos, Parsed) when ?IS_NEWLINE(SP) ->
    args(Rest, new_line(Pos), Parsed);
args(Rest, Pos, Args) when Rest =/= <<>> ->
    case expression(Rest, arg_level(Pos), []) of
        {<<")",_/binary>> = Rest0, Pos0, Arg} ->
            {Rest0, add_pos(Pos0,1), Args ++ [Arg]};
        {<<";",_/binary>> = Rest0, Pos0, Arg} ->
            {Rest0, add_pos(Pos0,1), Args ++ [Arg]};
        {<<",", Rest0/binary>>, Pos0, Arg} ->
            args(Rest0, add_pos(Pos0, 1), Args ++ [Arg]);
        {Rest0, Pos0, Arg} ->
            args(Rest0, Pos0, Args ++ [Arg])
    end.

st_foreach(<<SP:8,Rest/binary>>, Pos, Parsed) when ?IS_SPACE(SP) ->
    st_foreach(Rest, add_pos(Pos,1), Parsed);
st_foreach(<<SP:8,Rest/binary>>, Pos, Parsed) when ?IS_NEWLINE(SP) ->
    st_foreach(Rest, new_line(Pos), Parsed);
st_foreach(<<"(",Rest/binary>>, Pos, Parsed) ->
    {Rest0, Pos0, Exp} = expression(Rest, foreach_block_level(Pos), []),
    {<<AS:2/binary,Rest1/binary>>, Pos1} = remove_spaces(Rest0, Pos0),
    <<"as">> = ephp_string:to_lower(AS),
    NewPos = array_def_level(add_pos(Pos1,2)),
    {<<")",Rest2/binary>>, Pos2, ExpIter} = expression(Rest1, NewPos, []),
    BlockPos = foreach_block_level(add_pos(Pos2,1)),
    {Rest3, Pos3, CodeBlock} = code_block(Rest2, BlockPos, []),
    RawFor = add_line(#foreach{
        iter=ExpIter,
        elements=Exp,
        loop_block=CodeBlock
    }, Pos),
    For = case ExpIter of
        #variable{} ->
            RawFor;
        [KIter,Iter] ->
            RawFor#foreach{kiter=KIter, iter=Iter}
    end,
    {Rest3, copy_level(Pos, Pos3), [For|Parsed]}.

switch_case_block([]) ->
    [];
switch_case_block(Blocks) ->
    {Block, [Switch|Rest]} = lists:splitwith(fun
        (#switch_case{}) -> false;
        (_) -> true
    end, Blocks),
    [Switch#switch_case{code_block=lists:reverse(Block)}|Rest].

st_switch(<<"(",Rest/binary>>, Pos, Parsed) ->
    {<<")", Rest0/binary>>, Pos0, Cond} = expression(Rest, add_pos(Pos,1), []),
    {<<"{", Rest1/binary>>, Pos1} = remove_spaces(Rest0, add_pos(Pos0, 1)),
    NewPos = switch_block_level(add_pos(Pos1, 1)),
    {Rest2, Pos2, CodeBlock} = code(Rest1, NewPos, []),
    Switch = add_line(#switch{
        condition=Cond,
        cases=CodeBlock
    }, Pos),
    {Rest2, copy_level(Pos, Pos2), [Switch|Parsed]}.

st_for(<<SP:8,Rest/binary>>, Pos, Parsed) when ?IS_SPACE(SP) ->
    st_for(Rest, add_pos(Pos,1), Parsed);
st_for(<<SP:8,Rest/binary>>, Pos, Parsed) when ?IS_NEWLINE(SP) ->
    st_for(Rest, new_line(Pos), Parsed);
st_for(<<"(",Rest/binary>>, Pos, Parsed) ->
    {<<";",Rest0/binary>>, Pos0, Init} = args(Rest, add_pos(Pos,1), []),
    {<<";",Rest1/binary>>, Pos1, [Cond]} = args(Rest0, add_pos(Pos0,1), []),
    {<<")",Rest2/binary>>, Pos2, Upda} = args(Rest1, add_pos(Pos1,1), []),
    {Rest3, Pos3, CodeBlock} = code_block(Rest2,
                                          for_block_level(add_pos(Pos2,1)), []),
    For = add_line(#for{
        init=Init, conditions=Cond, update=Upda, loop_block=CodeBlock
    }, Pos),
    {Rest3, copy_level(Pos, Pos3), [For|Parsed]}.

comment_line(<<>>, _Pos, Parsed) ->
    Parsed;
comment_line(<<"\n",Rest/binary>>, Pos, Parsed) ->
    {Rest, new_line(Pos), Parsed};
comment_line(<<_/utf8,Rest/binary>>, Pos, Parsed) ->
    comment_line(Rest, add_pos(Pos,1), Parsed).

comment_block(<<>>, Pos, _Parsed) ->
    %% TODO: throw parse error
    throw({error, {parse, Pos, missng_comment_end}});
comment_block(<<"*/",Rest/binary>>, Pos, Parsed) ->
    {Rest, add_pos(Pos,2), Parsed};
comment_block(<<"\n",Rest/binary>>, Pos, Parsed) ->
    comment_block(Rest, new_line(Pos), Parsed);
comment_block(<<_/utf8,Rest/binary>>, Pos, Parsed) ->
    comment_block(Rest, add_pos(Pos,1), Parsed).

%%------------------------------------------------------------------------------
%% helper functions
%%------------------------------------------------------------------------------

add_to_text(L, _Pos, [#print_text{text=Text}=P|Parsed]) ->
    NewText = <<Text/binary, L/binary>>,
    [P#print_text{text=NewText}|Parsed];
add_to_text(L, Pos, Parsed) ->
    [add_line(#print_text{text=L}, Pos)|Parsed].

add_pos({Level,Row,Col}, Offset) ->
    {Level,Row,Col+Offset}.

new_line({Level,Row,_Col}) ->
    {Level,Row+1,1}.

if_old_block_level({_,Row,Col}) -> {if_old_block,Row,Col}.
for_old_block_level({_,Row,Col}) -> {for_old_block,Row,Col}.
foreach_old_block_level({_,Row,Col}) -> {foreach_old_block,Row,Col}.
while_old_block_level({_,Row,Col}) -> {while_old_block,Row,Col}.

if_block_level({_,Row,Col}) -> {if_block,Row,Col}.
for_block_level({_,Row,Col}) -> {for_block,Row,Col}.
foreach_block_level({_,Row,Col}) -> {foreach_block,Row,Col}.
while_block_level({_,Row,Col}) -> {while_block,Row,Col}.
switch_block_level({_,Row,Col}) -> {switch_block,Row,Col}.

normal_level({_,Row,Col}) -> {code,Row,Col}.
code_block_level({_,Row,Col}) -> {code_block,Row,Col}.
code_value_level({_,Row,Col}) -> {code_value,Row,Col}.
code_statement_level({_,Row,Col}) -> {code_statement,Row,Col}.
arg_level({_,Row,Col}) -> {arg,Row,Col}.
array_level({_,Row,Col}) -> {array,Row,Col}.
array_def_level({_,Row,Col}) -> {{array_def,0},Row,Col}.
array_def_54_level({_,Row,Col}) -> {{array_def,54},Row,Col}.
literal_level({_,Row,Col}) -> {literal,Row,Col}.

add_op('end', []) ->
    [];
add_op('end', [{op,Content}]) ->
    solve(process_incr_decr(Content));
add_op('end', Parsed) ->
    Parsed;
add_op(Add, [{op,Content}|Parsed]) ->
    [{op, Content ++ [Add]}|Parsed];
add_op(Add, Parsed) ->
    [{op,[Add]}|Parsed].

process_incr_decr(Content) ->
    process_incr_decr(Content, []).

process_incr_decr([], Processed) ->
    Processed;
process_incr_decr([{<<"++">>,_,Pos},#variable{}=V|Rest], Processed) ->
    process_incr_decr(Rest, Processed ++ [{pre_incr, V, Pos}]);
process_incr_decr([{<<"--">>,_,Pos},#variable{}=V|Rest], Processed) ->
    process_incr_decr(Rest, Processed ++ [{pre_decr, V, Pos}]);
process_incr_decr([#variable{}=V,{<<"++">>,_,Pos}|Rest], Processed) ->
    process_incr_decr(Rest, Processed ++ [{post_incr, V, Pos}]);
process_incr_decr([#variable{}=V,{<<"--">>,_,Pos}|Rest], Processed) ->
    process_incr_decr(Rest, Processed ++ [{post_decr, V, Pos}]);
process_incr_decr([A|Rest], Processed) ->
    process_incr_decr(Rest, Processed ++ [A]).

%% took from http://php.net/manual/en/language.operators.precedence.php

-type associativity() :: no_assoc | left | right.
-spec precedence(binary()) -> {associativity(), pos_integer()} | false.

precedence(<<"clone">>) -> {no_assoc, 1};
precedence(<<"new">>) -> {no_assoc, 1};
%precedence(<<"[">>) -> {left, 2}; %% array
precedence(<<"**">>) -> {right, 3}; %% arith
precedence(<<"++">>) -> {right, 4};
precedence(<<"--">>) -> {right, 4};
precedence(<<126>>) -> {right, 4}; %% ~ (types and increment/decrement)
precedence(<<"(int)">>) -> {right, 4};
precedence(<<"(float)">>) -> {right, 4};
precedence(<<"(string)">>) -> {right, 4};
precedence(<<"(array)">>) -> {right, 4};
precedence(<<"(object)">>) -> {right, 4};
precedence(<<"(bool)">>) -> {right, 4};
precedence(<<"@">>) -> {right, 4};
precedence(<<"instaceof">>) -> {no_assoc, 5};
precedence(<<"!">>) -> {right, 6}; %% logic
precedence(<<"*">>) -> {left, 7};
precedence(<<"/">>) -> {left, 7};
precedence(<<"%">>) -> {left, 7};
precedence(<<"+">>) -> {left, 8};
precedence(<<"-">>) -> {left, 8};
precedence(<<".">>) -> {left, 8}; %% concat
precedence(<<"<<">>) -> {left, 9}; %% bit by bit
precedence(<<">>">>) -> {left, 9}; %% bit by bit
precedence(<<"<">>) -> {no_assoc, 10};
precedence(<<"<=">>) -> {no_assoc, 10};
precedence(<<">">>) -> {no_assoc, 10};
precedence(<<">=">>) -> {no_assoc, 10};
precedence(<<"==">>) -> {no_assoc, 11};
precedence(<<"!=">>) -> {no_assoc, 11};
precedence(<<"===">>) -> {no_assoc, 11};
precedence(<<"!==">>) -> {no_assoc, 11};
precedence(<<"<>">>) -> {no_assoc, 11};
precedence(<<"<=>">>) -> {no_assoc, 11};
precedence(<<"&">>) -> {left, 12}; %% bit by bit & references
precedence(<<"^">>) -> {left, 13}; %% bit by bit
precedence(<<"|">>) -> {left, 14}; %% bit by bit
precedence(<<"&&">>) -> {left, 15}; %% logic
precedence(<<"||">>) -> {left, 16}; %% logic
precedence(<<"??">>) -> {right, 17}; %% comparison
precedence(<<"?:">>) -> {left, 18}; %% ternary
precedence(<<"=">>) -> {right, 19}; %% assign
precedence(<<"+=">>) -> {right, 19};
precedence(<<"-=">>) -> {right, 19};
precedence(<<"*=">>) -> {right, 19};
precedence(<<"**=">>) -> {right, 19};
precedence(<<"/=">>) -> {right, 19};
precedence(<<".=">>) -> {right, 19};
precedence(<<"%=">>) -> {right, 19};
precedence(<<"&=">>) -> {right, 19};
precedence(<<"|=">>) -> {right, 19};
precedence(<<"^=">>) -> {right, 19};
precedence(<<"<<=">>) -> {right, 19};
precedence(<<">>=">>) -> {right, 19};
precedence(<<"and">>) -> {left, 20};
precedence(<<"xor">>) -> {left, 21};
precedence(<<"or">>) -> {left, 22};
precedence(_) -> false.

operator(<<"and">>,Left,Right) -> operator('and',Left,Right);
operator(<<"or">>,Left,Right) -> operator('or',Left,Right);
operator(<<"&&">>,Left,Right) -> operator('and',Left,Right);
operator(<<"||">>,Left,Right) -> operator('or',Left,Right);
operator(<<"<=">>,Left,Right) -> operator(<<"=<">>,Left,Right);
operator(Op,R1,R2) when is_boolean(R1) andalso is_boolean(R2) ->
    case Op of
        'and' -> R1 and R2;
        'or' -> R1 or R2;
        _ -> #operation{type=Op, expression_left=R1, expression_right=R2}
    end;
operator(Op,R1,R2) when (is_record(R1, int) orelse is_record(R1, float))
                andalso (is_record(R2, int) orelse is_record(R2, float)) ->
    N1 = element(2, R1),
    N2 = element(2, R2),
    Res = case Op of
        <<"+">> -> N1+N2;
        <<"-">> -> N1-N2;
        <<"*">> -> N1*N2;
        <<"/">> -> N1/N2;
        <<"%">> -> N1 rem N2;
        <<">">> -> N1 > N2;
        <<"<">> -> N1 < N2;
        <<"==">> -> N1 == N2;
        <<"=<">> -> N1 =< N2;
        <<">=">> -> N1 >= N2;
        <<"^">> -> N1 bxor N2;
        <<"&">> -> N1 band N2;
        <<"|">> -> N1 bor N2
    end,
    if
        is_integer(Res) -> #int{int=Res};
        is_float(Res) -> #float{float=Res};
        is_boolean(Res) -> Res;
        true -> throw({error, R1, R2, Res})
    end;
operator(<<".">>,#text{text=T1},#text{text=T2}) ->
    #text{text = <<T1/binary,T2/binary>>};
operator(<<".">>,Left,Right) ->
    ProcessedLeft = concat(Left),
    ProcessedRight = concat(Right),
    #concat{texts=ProcessedLeft ++ ProcessedRight};
operator(Op,Left,Right) ->
    #operation{type=Op, expression_left=Left, expression_right=Right}.

concat(#concat{texts=T}) -> T;
concat(T) -> [T].

solve(Expression) ->
    Postfix = shunting_yard(Expression, [], []),
    [Operation] = gen_op(Postfix, []),
    Operation.

gen_op([], Stack) ->
    Stack;
gen_op([#variable{}=V,{<<"&">>,{left,_},Pos}], []) ->
    [add_line(#ref{var=V}, Pos)];
gen_op([{<<"@">>,{right,_},{_,_,_}}|Rest], Stack) ->
    [{silent, gen_op(Rest, Stack)}];
gen_op([{<<126>>,{_,_},{_,R,C}}|Rest], [A|Stack]) ->
    gen_op(Rest, [{operation_bnot, A, {{line,R},{column,C}}}|Stack]);
gen_op([{<<"!">>,{_,_},{_,R,C}}|Rest], [A|Stack]) ->
    gen_op(Rest, [{operation_not, A, {{line,R},{column,C}}}|Stack]);
gen_op([{Op,{_,_},Pos}|Rest], [B,A|Stack]) ->
    gen_op(Rest, [add_line(operator(Op,A,B),Pos)|Stack]);
gen_op([{<<"-">>,{_,_},Pos}|Rest], [#int{}=I]) ->
    gen_op(Rest, [add_line(#int{int=-I#int.int},Pos)]);
gen_op([{<<"-">>,{_,_},Pos}|Rest], [#float{}=F]) ->
    gen_op(Rest, [add_line(#float{float=-F#float.float},Pos)]);
gen_op([A|Rest], Stack) ->
    gen_op(Rest, [A|Stack]).

shunting_yard([], [], Postfix) ->
    Postfix;
shunting_yard([], OpS, Postfix) ->
    Postfix ++ OpS;
shunting_yard([{_,{_,_},_}=Op|Rest], [], Postfix) ->
    shunting_yard(Rest, [Op], Postfix);
shunting_yard([open|Rest], OpS, Postfix) ->
    shunting_yard(Rest, [open|OpS], Postfix);
%% TODO it could be a fail, find a close parens without other operators in stack
% shunting_yard([close|Rest], [], Postfix) ->
%     shunting_yard(Rest, [], Postfix);
shunting_yard([close|Rest]=_A, OpS, Postfix) ->
    {Add, [open|NewOpS]} = lists:splitwith(fun(A) -> A =/= open end, OpS),
    shunting_yard(Rest, NewOpS, Postfix ++ Add);
shunting_yard([{_,{left,P1},_}=Op|Rest], [{_,{_,P2},_}=Op1|OpS], Postfix)
        when P1 > P2 ->
    shunting_yard(Rest, [Op|OpS], Postfix ++ [Op1]);
shunting_yard([{_,{_,P1},_}=Op|Rest], [{_,{_,P2},_}=Op1|OpS], Postfix)
        when P1 >= P2 ->
    shunting_yard(Rest, [Op|OpS], Postfix ++ [Op1]);
shunting_yard([{_,{left,P1},_}=Op|Rest], [{_,{_,P2},_}|_]=OpS, Postfix)
        when P1 =< P2 ->
    shunting_yard(Rest, [Op|OpS], Postfix);
shunting_yard([{_,{_,P1},_}=Op|Rest], [{_,{_,P2},_}|_]=OpS, Postfix)
        when P1 < P2 ->
    shunting_yard(Rest, [Op|OpS], Postfix);
shunting_yard([{_,{_,_},_}=Op|Rest], [open|_]=OpS, Postfix) ->
    shunting_yard(Rest, [Op|OpS], Postfix);
shunting_yard([A|Rest], OpS, Postfix) ->
    shunting_yard(Rest, OpS, Postfix ++ [A]).

add_line(true, _) -> true;
add_line(false, _) -> false;
add_line(#array{}=A, {_,Row,Col}) -> A#array{line={{line,Row},{column,Col}}};
add_line(#eval{}=E, {_,Row,Col}) -> E#eval{line={{line,Row},{column,Col}}};
add_line(#print{}=P, {_,Row,Col}) -> P#print{line={{line,Row},{column,Col}}};
add_line(#print_text{}=P, {_,Row,Col}) ->
    P#print_text{line={{line,Row},{column,Col}}};
add_line(#variable{}=V, {_,R,C}) -> V#variable{line={{line,R},{column,C}}};
add_line(#constant{}=O, {_,R,C}) -> O#constant{line={{line,R},{column,C}}};
add_line(#int{}=I, {_,R,C}) -> I#int{line={{line,R},{column,C}}};
add_line(#float{}=F, {_,R,C}) -> F#float{line={{line,R},{column,C}}};
add_line(#text_to_process{}=T, {_,R,C}) ->
    T#text_to_process{line={{line,R},{column,C}}};
add_line(#text{}=T, {_,R,C}) -> T#text{line={{line,R},{column,C}}};
add_line(#if_block{}=I, {_,R,C}) -> I#if_block{line={{line,R},{column,C}}};
add_line(#assign{}=A, {_,R,C}) -> A#assign{line={{line,R},{column,C}}};
add_line(#array_element{}=A, {_,R,C}) ->
    A#array_element{line={{line,R},{column,C}}};
add_line(#for{}=F, {_,R,C}) -> F#for{line={{line,R},{column,C}}};
add_line(#foreach{}=F, {_,R,C}) -> F#foreach{line={{line,R},{column,C}}};
add_line(#operation{}=O, {_,R,C}) -> O#operation{line={{line,R},{column,C}}};
add_line(#concat{}=O, {_,R,C}) -> O#concat{line={{line,R},{column,C}}};
add_line(#while{}=W, {_,R,C}) -> W#while{line={{line,R},{column,C}}};
add_line(#return{}=Rt, {_,R,C}) -> Rt#return{line={{line,R},{column,C}}};
add_line(#function{}=F, {_,R,C}) -> F#function{line={{line,R},{column,C}}};
add_line(#global{}=G, {_,R,C}) -> G#global{line={{line,R},{column,C}}};
add_line(#ref{}=Rf, {_,R,C}) -> Rf#ref{line={{line,R},{column,C}}};
add_line(#switch{}=S, {_,R,C}) -> S#switch{line={{line,R},{column,C}}};
add_line(#switch_case{}=S, {_,R,C}) -> S#switch_case{line={{line,R},{column,C}}};
add_line(#call{}=Cl, {_,R,C}) -> Cl#call{line={{line,R},{column,C}}}.

remove_spaces(<<SP:8,Rest/binary>>, Pos) when ?IS_SPACE(SP) ->
    remove_spaces(Rest, add_pos(Pos,1));
remove_spaces(<<SP:8,Rest/binary>>, Pos) when ?IS_NEWLINE(SP) ->
    remove_spaces(Rest, new_line(Pos));
remove_spaces(<<>>, Pos) -> {<<>>, Pos};
remove_spaces(Rest, Pos) -> {Rest, Pos}.

get_print({Type, Value, _}, Pos) when
        Type =:= int; Type =:= float; Type =:= text ->
    add_line(#print_text{text=ephp_data:to_bin(Value)}, Pos);
get_print(Value, Pos) when is_atom(Value) ->
    add_line(#print_text{text=ephp_data:to_bin(Value)}, Pos);
get_print(Expr, Pos) ->
    add_line(#print{expression=Expr}, Pos).

throw_error(Error, {_Level,Row,Col}, Data) ->
    Output = iolist_to_binary(Data),
    Size = min(byte_size(Output), 20),
    Index = {{line,Row},{column,Col}},
    ephp_error:error({error, Error, Index, ?E_PARSE,
        <<Output:Size/binary, "...">>}).
