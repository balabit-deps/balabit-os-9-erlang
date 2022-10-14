%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 1996-2021. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% %CopyrightEnd%
%%

-module(docgen_otp_specs).

-export([module/2, package/2, overview/2, type/1]).

-include("xmerl.hrl").

-define(XML_EXPORT, xmerl_xml).
-define(DEFAULT_XML_EXPORT, ?XML_EXPORT).
-define(DEFAULT_PP, erl_pp).
-define(IND(N), #xmlText{value="\n" ++ lists:duplicate(N, $\s)}).
-define(NL, "\n").

module(Element, Options) ->
    XML = layout_module(Element, init_opts(Options)),
    Export = proplists:get_value(xml_export, Options,
				 ?DEFAULT_XML_EXPORT),
    xmerl:export_simple(XML, Export, [#xmlAttribute{name=prolog,
                                                    value=""}]).

-record(opts, {pretty_print, file_suffix}).

init_opts(Options) ->
    #opts{pretty_print = proplists:get_value(pretty_print,
                                             Options, ?DEFAULT_PP),
          %% It *is* depending on edoc.hrl!
          file_suffix = proplists:get_value(file_suffix, Options, ".html")}.

layout_module(#xmlElement{name = module, content = Es}=E, Opts) ->
    Name = get_attrval(name, E),
    Functions = [{function_name(Elem), Elem} ||
                    Elem <- get_content(functions, Es)],
    Types = [{type_name(Elem), Elem} || Elem <- get_content(typedecls, Es)],
    Body = [{module,
             [{name,[Name]}],
             ([?NL] ++ types(lists:sort(Types), Opts)
              ++ functions(lists:sort(Functions), Opts)
              ++ timestamp())}],
    Body.

timestamp() ->
    [{timestamp, [io_lib:fwrite("Generated by EDoc, ~s, ~s.",
                                [edoc_lib:datestr(date()),
                                 edoc_lib:timestr(time())])]},?NL].

functions(Fs, Opts) ->
    lists:flatmap(fun ({Name, E}) -> function(Name, E, Opts) end, Fs).

function(Name, #xmlElement{content = Es}, Opts) ->
    TSs = get_elem(typespec, Es),
    case TSs of
	[] ->
	    spec_clause(Name, [], Opts);
	[_|_] ->
	    lists:concat([ spec_clause(Name, TS, Opts)
			   || #xmlElement{content = TS} <- TSs ])
    end.

spec_clause(Name, TS, Opts) ->
    Spec = typespec(TS, Opts),
    [{spec,(Name
            ++ [?IND(2),{contract,Spec}]
            ++ typespec_annos(TS))},
     ?NL].

function_name(E) ->
    [] = get_attrval(module, E),
    [?IND(2),{name,[atom(get_attrval(name, E))]},
     ?IND(2),{arity,[get_attrval(arity, E)]}].

label_anchor(Content, E) ->
    case get_attrval(label, E) of
	"" -> Content;
	Ref -> [{marker, [{id, Ref}], Content}]
    end.

typespec([], _Opts) -> [];
typespec(Es, Opts) ->
    {Head, LDefs} = collect_clause(Es, Opts),
    clause(Head, LDefs) ++ [?IND(2)].

collect_clause(Es, Opts) ->
    Name = t_name(get_elem(erlangName, Es)),
    Defs = get_elem(localdef, Es),
    [Type] = get_elem(type, Es),
    {format_spec(Name, Type, Opts), collect_local_defs(Defs, Opts)}.

clause(Head, LDefs) ->
    FC = [?IND(6),{head,Head}] ++ local_clause_defs(LDefs),
    [?IND(4),{clause,FC}].

local_clause_defs([]) -> [];
local_clause_defs(LDefs) ->
    LocalDefs = [{subtype,T} || T <- coalesce_local_defs(LDefs, [])],
    [?IND(6),{guard,margin(8, LocalDefs)}].

types(Ts, Opts) ->
    lists:flatmap(fun ({Name, E}) -> typedecl(Name, E, Opts) end, Ts).

typedecl(Name, E=#xmlElement{content = Es}, Opts) ->
    TD = get_content(typedef, Es),
    TypeDef = typedef(E, TD, Opts),
    [{type,(Name
            ++ [?IND(2),{typedecl, TypeDef}]
            ++ typedef_annos(TD))},
      ?NL].

type_name(#xmlElement{content = Es}) ->
    Typedef = get_content(typedef, Es),
    [E] = get_elem(erlangName, Typedef),
    Args = get_content(argtypes, Typedef),
    [] = get_attrval(module, E),
    [?IND(2),{name,[atom(get_attrval(name, E))]},
     ?IND(2),{n_vars,[integer_to_list(length(Args))]}].

typedef(E, Es, Opts) ->
    Ns = get_elem(erlangName, Es),
    Name =
        ([t_name(Ns), "("]
         ++ seq(fun t_utype_elem/1, get_content(argtypes, Es), [")"])),
    LDefs = collect_local_defs(get_elem(localdef, Es), Opts),
    TypeHead = case get_elem(type, Es) of
                   [] -> label_anchor(Name, E);
                   Type -> (label_anchor(Name, E)
                            ++ format_type(Name, Type, Opts))
               end,
    ([?IND(6),{typehead,TypeHead}]
     ++ local_type_defs(LDefs, [])).

local_type_defs([], _) -> [];
local_type_defs(LDefs, Last) ->
    LocalDefs = [{local_def,T} || T <- coalesce_local_defs(LDefs, Last)],
    [?IND(6),{local_defs,margin(8, LocalDefs)}].

collect_local_defs(Es, Opts) ->
    [collect_localdef(E, Opts) || E <- Es].

collect_localdef(E = #xmlElement{content = Es}, Opts) ->
    Name = case get_elem(typevar, Es) of
               [] ->
                   label_anchor(N0 = t_abstype(get_content(abstype, Es)), E);
               [V] ->
                   N0 = t_var(V)
           end,
    {Name,N0,format_type(N0, get_elem(type, Es), Opts)}.

%% "A = t(), B = t()" is coalesced into "A = B = t()".
%% Names as B above are kept, but the formated string is empty.
coalesce_local_defs([], _Last) ->
    [];
coalesce_local_defs([{Name,N0,TypeS} | L], Last) when Name =:= N0 ->
    cld(L, [{Name,N0}], TypeS, Last);
coalesce_local_defs([{Name,N0,TypeS} | L], Last) ->
    [local_def(N0, Name, TypeS, Last, L) | coalesce_local_defs(L, Last)].

cld([{Name,N0,TypeS} | L], Names, TypeS, Last) when Name =:= N0 ->
    cld(L, [{Name,N0} | Names], TypeS, Last);
cld(L, Names0, TypeS, Last) ->
    Names = [{_,Name0} | Names1] = lists:reverse(Names0),
    NS = join([N || {N,_} <- Names], [" = "]),
    ([local_def(Name0, NS, TypeS, Last, L) |
      [local_def(N0, "", "", [], L) || {_,N0} <- Names1]]
     ++ coalesce_local_defs(L, Last)).

local_def(Name, NS, TypeS, Last, L) ->
    [{typename,Name},{string,NS ++ TypeS ++ [Last || L =:= []]}].

%% join([], Sep) when is_list(Sep) ->
%%     [];
join([H|T], Sep) ->
    H ++ lists:append([Sep ++ X || X <- T]).

%% Use the default formatting of EDoc, which creates references, and
%% then insert newlines and indentation according to erl_pp (the
%% (fast) Erlang pretty printer).
format_spec(Name, Type, #opts{pretty_print = erl_pp}=Opts) ->
    try
        L = t_clause(Name, Type),
        O = pp_clause(Name, Type),
        {R, ".\n"} = diaf(L, O, Opts),
        R
    catch _:_ ->
        %% Example: "@spec ... -> record(a)"
        format_spec(Name, Type, Opts#opts{pretty_print=default})
    end;
format_spec(Sep, Type, _Opts) ->
    t_clause(Sep, Type).

t_clause(Name, Type) ->
    #xmlElement{content = [#xmlElement{name = 'fun', content = C}]} = Type,
    [Name] ++ t_fun(C).

pp_clause(Pre, Type) ->
    Types = ot_utype([Type]),
    Atom = lists:duplicate(iolist_size(Pre), $a),
    Attr = {attribute,0,spec,{{list_to_atom(Atom),0},[Types]}},
    L1 = erl_pp:attribute(erl_parse:new_anno(Attr)),
    "-spec " ++ L2 = lists:flatten(L1),
    L3 = Pre ++ lists:nthtail(length(Atom), L2),
    re:replace(L3, "\n      ", "\n", [{return,list},global]).

format_type(Name, Type, #opts{pretty_print = erl_pp}=Opts) ->
    try
        L = t_utype(Type),
        O = pp_type(Name, Type),
        {R, ".\n"} = diaf(L, O, Opts),
        [" = "] ++ R
    catch _:_ ->
        %% Example: "t() = record(a)."
        format_type(Name, Type, Opts#opts{pretty_print=default})
    end;
format_type(_Name, Type, _Opts) ->
    [" = "] ++ t_utype(Type).

pp_type(Prefix, Type) ->
    Atom = list_to_atom(lists:duplicate(iolist_size(Prefix), $a)),
    Attr = {attribute,0,type,{Atom,ot_utype(Type),[]}},
    L1 = erl_pp:attribute(erl_parse:new_anno(Attr)),
    {L2,N} = case lists:dropwhile(fun(C) -> C =/= $: end, lists:flatten(L1)) of
                 ":: " ++ L3 -> {L3,9}; % compensation for extra "()" and ":"
                 "::\n" ++ L3 -> {"\n"++L3,6}
             end,
    Ss = lists:duplicate(N, $\s),
    re:replace(L2, "\n"++Ss, "\n", [{return,list},global]).

diaf(L, O0, Opts) ->
    {R0, O} = diaf(L, [], O0, [], Opts),
    R1 = rewrite_some_predefs(lists:reverse(R0)),
    R = indentation(lists:flatten(R1)),
    {R, O}.

diaf([C | L], St, [C | O], R, Opts) ->
    diaf(L, St, O, [[C] | R], Opts);
diaf(" "++L, St, O, R, Opts) ->
    diaf(L, St, O, R, Opts);
diaf("", [Cs | St], O, R, Opts) ->
    diaf(Cs, St, O, R, Opts);
diaf("", [], O, R, _Opts) ->
    {R, O};
diaf(L, St, " "++O, R, Opts) ->
    diaf(L, St, O, [" " | R], Opts);
diaf(L, St, "\n"++O, R, Opts) ->
    Ss = lists:takewhile(fun(C) -> C =:= $\s end, O),
    diaf(L, St, lists:nthtail(length(Ss), O), ["\n"++Ss | R], Opts);
diaf([{seetype, HRef0, S0} | L], St, O0, R, Opts) ->
    {S, O} = diaf(S0, app_fix(O0), Opts),
    HRef = fix_mod_ref(HRef0, Opts),
    diaf(L, St, O, [{seetype, HRef, S} | R], Opts);
diaf("="++L, St, "::"++O, R, Opts) ->
    %% EDoc uses "=" for record field types; Dialyzer uses "::". Maybe
    %% there should be an option for this, possibly affecting other
    %% similar discrepancies.
    diaf(L, St, O, ["=" | R], Opts);
diaf([Cs | L], St, O, R, Opts) ->
    diaf(Cs, [L | St], O, R, Opts).

rewrite_some_predefs(S) ->
    xpredef(lists:flatten(S)).

xpredef([]) ->
    [];
xpredef("neg_integer()"++L) ->
    ["integer() =< -1"] ++ xpredef(L);
xpredef("non_neg_integer()"++L) ->
    ["integer() >= 0"] ++ xpredef(L);
xpredef("pos_integer()"++L) ->
    ["integer() >= 1"] ++ xpredef(L);
xpredef([T | Es]) when is_tuple(T) ->
    [T | xpredef(Es)];
xpredef([E | Es]) ->
    [[E] | xpredef(Es)].

indentation([]) ->
    [];
indentation([$\n|L]) ->
    [{br,[]}|indent(L)];
indentation([T | Es]) when is_tuple(T) ->
    [T | indentation(Es)];
indentation([E|L]) ->
    [[E]|indentation(L)].

indent([$\s|L]) ->
    [{nbsp,[]}|indent(L)];
indent(L) ->
    indentation(L).

app_fix(L) ->
    try
        {"//" ++ R1,L2} = app_fix(L, 1),
        [App, Mod] = string:lexemes(R1, "/"),
        "//" ++ atom(App) ++ "/" ++ atom(Mod) ++ L2
    catch _:_ -> L
    end.

app_fix(L, I) -> % a bit slow
    {L1, L2} = lists:split(I, L),
    case erl_scan:tokens([], L1 ++ ". ", 1) of
        {done, {ok,[{atom,_,Atom}|_],_}, _} -> {atom_to_list(Atom), L2};
        _ -> app_fix(L, I+1)
    end.

%% Translate edoc absolute links to local links
fix_mod_ref([{marker, "specs://" ++ HRef}], Opts) ->
    case string:split(HRef,"/",all) of
        %% We don't need to prefix with "app:" on the link
        %% it will be added later anyway
        [_App, "doc", ModRef] ->
            fix_mod_ref([{marker,ModRef}], Opts)
    end;
%% Remove the file suffix from module references.
fix_mod_ref(HRef, #opts{file_suffix = ""}) ->
    HRef;
fix_mod_ref([{marker, S}]=HRef0, #opts{file_suffix = FS}) ->
    {A, B} = lists:splitwith(fun(C) -> C =/= $# end, S),
    case lists:member($:, A) of
        true ->
            HRef0; % should "save" most application references "http:"
        false ->
            case {lists:suffix(FS, A), B} of
                {true, "#"++_} ->
                    [{marker, lists:sublist(A, length(A)-length(FS)) ++ B}];
                _ ->
                    HRef0
            end
    end.

see(E, Es) ->
    case href(E) of
	[] -> Es;
        [{marker,Ref}] ->
	    [{seetype, [{marker,lists:flatten(string:replace(Ref,"#type-","#"))}], Es}]
    end.

href(E) ->
    case get_attrval(href, E) of
	"" -> [];
	URI ->
	    [{marker, URI}]
    end.

atom(String) ->
    io_lib:write_atom(list_to_atom(String)).

t_name([E]) ->
    N = get_attrval(name, E),
    case get_attrval(module, E) of
	"" -> atom(N);
	M ->
	    S = atom(M) ++ ":" ++ atom(N),
	    case get_attrval(app, E) of
		"" -> S;
		A -> "//" ++ atom(A) ++ "/" ++ S
	    end
    end.

t_utype([E]) ->
    t_utype_elem(E).

t_utype_elem(E=#xmlElement{content = Es}) ->
    case get_attrval(name, E) of
	"" -> t_type(Es);
	Name ->
	    T = t_type(Es),
	    case T of
		[Name] -> T;    % avoid generating "Foo::Foo"
		T -> [Name] ++ ["::"] ++ T
	    end
    end.

t_type([E=#xmlElement{name = typevar}]) ->
    t_var(E);
t_type([E=#xmlElement{name = atom}]) ->
    t_atom(E);
t_type([E=#xmlElement{name = integer}]) ->
    t_integer(E);
t_type([E=#xmlElement{name = range}]) ->
    t_range(E);
t_type([E=#xmlElement{name = binary}]) ->
    t_binary(E);
t_type([E=#xmlElement{name = float}]) ->
    t_float(E);
t_type([#xmlElement{name = nil}]) ->
    t_nil();
t_type([#xmlElement{name = paren, content = Es}]) ->
    t_paren(Es);
t_type([#xmlElement{name = list, content = Es}]) ->
    t_list(Es);
t_type([#xmlElement{name = nonempty_list, content = Es}]) ->
    t_nonempty_list(Es);
t_type([#xmlElement{name = map, content = Es}]) ->
    t_map(Es);
t_type([#xmlElement{name = tuple, content = Es}]) ->
    t_tuple(Es);
t_type([#xmlElement{name = 'fun', content = Es}]) ->
    ["fun("] ++ t_fun(Es) ++ [")"];
t_type([E = #xmlElement{name = record, content = Es}]) ->
    t_record(E, Es);
t_type([E = #xmlElement{name = abstype, content = Es}]) ->
    t_abstype(E, Es);
t_type([#xmlElement{name = union, content = Es}]) ->
    t_union(Es).

t_var(E) ->
    [get_attrval(name, E)].

t_atom(E) ->
    [io_lib:write(list_to_atom(get_attrval(value, E)))].

t_integer(E) ->
    [get_attrval(value, E)].

t_range(E) ->
    [get_attrval(value, E)].

t_binary(E) ->
    [get_attrval(value, E)].

t_float(E) ->
    [get_attrval(value, E)].

t_nil() ->
    ["[]"].

t_paren(Es) ->
    ["("] ++ t_utype(get_elem(type, Es)) ++ [")"].

t_list(Es) ->
    ["["] ++ t_utype(get_elem(type, Es)) ++ ["]"].

t_nonempty_list(Es) ->
    ["["] ++ t_utype(get_elem(type, Es)) ++ [", ...]"].

t_tuple(Es) ->
    ["{"] ++ seq(fun t_utype_elem/1, Es, ["}"]).

t_fun(Es) ->
    ["("] ++ seq(fun t_utype_elem/1, get_content(argtypes, Es),
		 [") -> "] ++ t_utype(get_elem(type, Es))).

t_map(Es) ->
    Fs = get_elem(map_field, Es),
    ["#{"] ++ seq(fun t_map_field/1, Fs, ["}"]).

t_map_field(#xmlElement{content = [K,V]}=E) ->
    KElem = t_utype_elem(K),
    VElem = t_utype_elem(V),
    AS = case get_attrval(assoc_type, E) of
             "assoc" -> " => ";
             "exact" -> " := "
         end,
    KElem ++ [AS] ++ VElem.

t_record(E, Es) ->
    Name = ["#"] ++ t_type(get_elem(atom, Es)),
    case get_elem(field, Es) of
        [] ->
            see(E, [Name, "{}"]);
        Fs ->
            see(E, Name) ++ ["{"] ++ seq(fun t_field/1, Fs, ["}"])
    end.

t_field(#xmlElement{content = Es}) ->
    t_type(get_elem(atom, Es)) ++ [" = "] ++ t_utype(get_elem(type, Es)).

t_abstype(E, Es) ->
    Name = t_name(get_elem(erlangName, Es)),
    case get_elem(type, Es) of
        [] ->
            see(E, [Name, "()"]);
        Ts ->
            see(E, [Name]) ++ ["("] ++ seq(fun t_utype_elem/1, Ts, [")"])
    end.

t_abstype(Es) ->
    ([t_name(get_elem(erlangName, Es)), "("]
     ++ seq(fun t_utype_elem/1, get_elem(type, Es), [")"])).

t_union(Es) ->
    seq(fun t_utype_elem/1, Es, " | ", []).

seq(F, Es, Tail) ->
    seq(F, Es, ", ", Tail).

seq(F, [E], _Sep, Tail) ->
    F(E) ++ Tail;
seq(F, [E | Es], Sep, Tail) ->
    F(E) ++ [Sep] ++ seq(F, Es, Sep, Tail);
seq(_F, [], _Sep, Tail) ->
    Tail.

get_elem(Name, [#xmlElement{name = Name} = E | Es]) ->
    [E | get_elem(Name, Es)];
get_elem(Name, [_ | Es]) ->
    get_elem(Name, Es);
get_elem(_, []) ->
    [].

get_attr(Name, [#xmlAttribute{name = Name} = A | As]) ->
    [A | get_attr(Name, As)];
get_attr(Name, [_ | As]) ->
    get_attr(Name, As);
get_attr(_, []) ->
    [].

get_attrval(Name, #xmlElement{attributes = As}) ->
    case get_attr(Name, As) of
	[#xmlAttribute{value = V}] ->
	    V;
	[] -> ""
    end.

get_content(Name, Es) ->
    case get_elem(Name, Es) of
	[#xmlElement{content = Es1}] ->
	    Es1;
	[] -> []
    end.

overview(_, _Options) -> [].

package(_, _Options) -> [].

type(_) -> [].

%% ---------------------------------------------------------------------

ot_utype([E]) ->
    ot_utype_elem(E).

ot_utype_elem(E=#xmlElement{content = Es}) ->
    case get_attrval(name, E) of
	"" -> ot_type(Es);
	N ->
            Name = {var,0,list_to_atom(N)},
	    T = ot_type(Es),
	    case T of
		Name -> T;
                T -> {ann_type,0,[Name, T]}
	    end
    end.

ot_type([E=#xmlElement{name = typevar}]) ->
    ot_var(E);
ot_type([E=#xmlElement{name = atom}]) ->
    ot_atom(E);
ot_type([E=#xmlElement{name = integer}]) ->
    ot_integer(E);
ot_type([E=#xmlElement{name = range}]) ->
    ot_range(E);
ot_type([E=#xmlElement{name = binary}]) ->
    ot_binary(E);
ot_type([E=#xmlElement{name = float}]) ->
    ot_float(E);
ot_type([#xmlElement{name = nil}]) ->
    ot_nil();
ot_type([#xmlElement{name = paren, content = Es}]) ->
    ot_paren(Es);
ot_type([#xmlElement{name = list, content = Es}]) ->
    ot_list(Es);
ot_type([#xmlElement{name = nonempty_list, content = Es}]) ->
    ot_nonempty_list(Es);
ot_type([#xmlElement{name = tuple, content = Es}]) ->
    ot_tuple(Es);
ot_type([#xmlElement{name = map, content = Es}]) ->
    ot_map(Es);
ot_type([#xmlElement{name = 'fun', content = Es}]) ->
    ot_fun(Es);
ot_type([#xmlElement{name = record, content = Es}]) ->
    ot_record(Es);
ot_type([#xmlElement{name = abstype, content = Es}]) ->
    ot_abstype(Es);
ot_type([#xmlElement{name = union, content = Es}]) ->
    ot_union(Es).

ot_var(E) ->
    {var,0,list_to_atom(get_attrval(name, E))}.

ot_atom(E) ->
    {ok, [{atom,A,Name}], _} = erl_scan:string(lists:flatten(t_atom(E)), 0),
    {atom,erl_anno:line(A),Name}.

ot_integer(E) ->
    {integer,0,list_to_integer(get_attrval(value, E))}.

ot_range(E) ->
    [I1, I2] = string:lexemes(get_attrval(value, E), "."),
    {type,0,range,[{integer,0,list_to_integer(I1)},
                   {integer,0,list_to_integer(I2)}]}.

ot_binary(E) ->
    {Base, Unit} =
        case string:lexemes(get_attrval(value, E), ",:*><") of
            [] ->
                {0, 0};
            ["_",B] ->
                {list_to_integer(B), 0};
            ["_","_",U] ->
                {0, list_to_integer(U)};
            ["_",B,_,"_",U] ->
                {list_to_integer(B), list_to_integer(U)}
        end,
    {type,0,binary,[{integer,0,Base},{integer,0,Unit}]}.

ot_float(E) ->
    {float,0,list_to_float(get_attrval(value, E))}.

ot_nil() ->
    {nil,0}.

ot_paren(Es) ->
    {paren_type,0,[ot_utype(get_elem(type, Es))]}.

ot_list(Es) ->
    {type,0,list,[ot_utype(get_elem(type, Es))]}.

ot_nonempty_list(Es) ->
    {type,0,nonempty_list,[ot_utype(get_elem(type, Es))]}.

ot_tuple(Es) ->
    {type,0,tuple,[ot_utype_elem(E) || E <- Es]}.

ot_map(Es) ->
    {type,0,map,[ot_map_field(E) || E <- get_elem(map_field,Es)]}.

ot_map_field(#xmlElement{content=[K,V]}=E) ->
    A = case get_attrval(assoc_type, E) of
            "assoc" -> map_field_assoc;
            "exact" -> map_field_exact
        end,
    {type,0,A,[ot_utype_elem(K), ot_utype_elem(V)]}.

ot_fun(Es) ->
    Range = ot_utype(get_elem(type, Es)),
    Args = [ot_utype_elem(A) || A <- get_content(argtypes, Es)],
    {type,0,'fun',[{type,0,product,Args},Range]}.

ot_record(Es) ->
    {type,0,record,[ot_type(get_elem(atom, Es)) |
                    [ot_field(F) || F <- get_elem(field, Es)]]}.

ot_field(#xmlElement{content = Es}) ->
    {type,0,field_type,
     [ot_type(get_elem(atom, Es)), ot_utype(get_elem(type, Es))]}.

ot_abstype(Es) ->
    ot_name(get_elem(erlangName, Es),
            [ot_utype_elem(Elem) || Elem <- get_elem(type, Es)]).

ot_union(Es) ->
    {type,0,union,[ot_utype_elem(E) || E <- Es]}.

ot_name(Es, T) ->
    case ot_name(Es) of
        [Mod, ":", Atom] ->
            {remote_type,0,[{atom,0,list_to_atom(Mod)},
                            {atom,0,list_to_atom(Atom)},T]};
        "tuple" when T =:= [] ->
            {type,0,tuple,any};
        "map" when T =:= [] ->
            {type,0,map,any};
        Atom ->
            {type,0,list_to_atom(Atom),T}
    end.

ot_name([E]) ->
    Atom = get_attrval(name, E),
    case get_attrval(module, E) of
	"" -> Atom;
	M ->
	    case get_attrval(app, E) of
		"" ->
                    [M, ":", Atom];
                A ->
                    ["//"++A++"/" ++ M, ":", Atom] % EDoc only!
	    end
    end.

%% Returns exactly those annotations that can be referred to. Note
%% that a Dialyzer type/spec (currently) can have more annotations
%% than can be represented by EDoc types. Note also that edoc_dia
%% has annotated all type variables with themselves.
typespec_annos([]) -> [?NL];
typespec_annos([_|Es]) ->
    annotations(clause_annos(Es)).

clause_annos(Es) ->
    [annos(get_elem(type, Es)), local_defs_annos(get_elem(localdef, Es))].

typedef_annos(Es) ->
    annotations([(case get_elem(type, Es) of
                      [] -> [];
                      T -> annos(T)
                  end
                  ++ lists:flatmap(fun annos_elem/1,
                                   get_content(argtypes, Es))),
                 local_defs_annos(get_elem(localdef, Es))]).

local_defs_annos(Es) ->
    lists:flatmap(fun localdef_annos/1, Es).

localdef_annos(#xmlElement{content = Es}) ->
    annos(get_elem(type, Es)).

annotations(AnnoL) ->
    Annos = lists:usort(lists:flatten(AnnoL)),
    margin(2, Annos).

margin(N, L) ->
    lists:append([[?IND(N),E] || E <- L]) ++ [?IND(N-2)].

annos([E]) ->
    annos_elem(E).

annos_elem(E=#xmlElement{content = Es}) ->
    case get_attrval(name, E) of
	"" -> annos_type(Es);
        "..." -> annos_type(Es); % compensate for a kludge in edoc_dia.erl
	N ->
            [{anno,[N]} | annos_type(Es)]
    end.

annos_type([#xmlElement{name = list, content = Es}]) ->
    annos(get_elem(type, Es));
annos_type([#xmlElement{name = nonempty_list, content = Es}]) ->
    annos(get_elem(type, Es));
annos_type([#xmlElement{name = tuple, content = Es}]) ->
    lists:flatmap(fun annos_elem/1, Es);
annos_type([#xmlElement{name = 'fun', content = Es}]) ->
    (annos(get_elem(type, Es))
     ++ lists:flatmap(fun annos_elem/1, get_content(argtypes, Es)));
annos_type([#xmlElement{name = record, content = Es}]) ->
    lists:append([annos(get_elem(type, Es1)) ||
                     #xmlElement{content = Es1} <- get_elem(field, Es)]);
annos_type([#xmlElement{name = abstype, content = Es}]) ->
    lists:flatmap(fun annos_elem/1, get_elem(type, Es));
annos_type([#xmlElement{name = union, content = Es}]) ->
    lists:flatmap(fun annos_elem/1, Es);
annos_type([E=#xmlElement{name = typevar}]) ->
    annos_elem(E);
annos_type([#xmlElement{name = paren, content = Es}]) ->
    annos(get_elem(type, Es));
annos_type([#xmlElement{name = map, content = Es}]) ->
    lists:flatmap(fun(E) -> annos_type([E]) end, Es);
annos_type([#xmlElement{name = map_field, content = Es}]) ->
    lists:flatmap(fun annos_elem/1, get_elem(type,Es));
annos_type(_) ->
    [].
