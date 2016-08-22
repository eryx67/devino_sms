%%% @author Vladimir G. Sekissov <eryx67@gmail.com>
%%% @copyright (C) 2014, Vladimir G. Sekissov
%%% @doc API SMS-серрвиса http://www.devinotele.com/support/api
%%% ++++
%%% <p/>
%%% ++++
%%% @end
%%% Created : 15 Dec 2014 by Vladimir G. Sekissov <eryx67@gmail.com>

-module(devino_sms_srv).
-behaviour(gen_server).
-define(SRV, ?MODULE).

-export([start_link/0]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-include_lib("sutil/include/log.hrl").

-record(st, {base_url,
             login,
             password,
             src_address,
             request_opts,
             session_id
            }).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?SRV}, ?MODULE, [], []).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init([]) ->
    {ok, BaseUrl} = devino_sms:get_env(base_url),
    {ok, ReqOpts} = devino_sms:get_env(request_opts),
    {ok, Login} = devino_sms:get_env(login),
    {ok, Pass} = devino_sms:get_env(password),
    {ok, SrcAddr} = devino_sms:get_env(src_address),
    State = #st{base_url=ensure_binary(BaseUrl),
                request_opts=ReqOpts,
                login=ensure_binary(Login),
                password=ensure_binary(Pass),
                src_address=ensure_binary(SrcAddr)
               },
    {ok, State}.

handle_call(authenticate, _From, S) ->
    {Res, S1} = handle_authenticate(S),
    {reply, Res, S1};
handle_call(balance, _From, State) ->
    Path = [<<"user">>, <<"balance">>],
    Params = [],
    {Res, State1} = handle_request(get, Path, Params, State),
    {reply, Res, State1};
handle_call({send_sms, DestAddrs, Data, LifeTime}, _From, S=#st{src_address=SrcAddr}) ->
    Path = [<<"sms">>, <<"sendbulk">>],
    Params1 = [{<<"sourceAddress">>, SrcAddr},
               {<<"data">>, Data}|
               [{<<"destinationAddresses">>, DA} ||
                   DA <- if is_list(DestAddrs) -> DestAddrs;
                            true -> [DestAddrs]
                         end]
              ],
    Params2 = case LifeTime of
                  undefined ->
                      Params1;
                  _ ->
                      [{<<"validity">>, integer_to_binary(LifeTime)}|Params1]
              end,
    {Res, S1} = handle_request(post, Path, Params2, S),
    {reply, Res, S1};
handle_call({sent_state, MsgId}, _From, State) ->
    Path = [<<"sms">>, <<"state">>],
    Params = [{<<"messageId">>, MsgId}],
    {Res, State1} = handle_request(get, Path, Params, State),
    {reply, Res, State1}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
handle_request(Method, Path, Params, S=#st{session_id=undefined}) ->
    case handle_authenticate(S) of
        {ok, S1} ->
            handle_request(Method, Path, Params, S1);
        Error ->
            {Error, S}
    end;
handle_request(Method, Path, Params, S=#st{session_id=SessId}) ->
    case do_request(Method, Path, [{<<"sessionId">>, SessId}|Params], S) of
        Res={ok, _} ->
            {Res, S};
        {error, {State, Code}} when State == 400 andalso Code == invalid_session ->
            handle_request(Method, Path, Params, S#st{session_id=undefined});
        Error={error, _} ->
            {Error, S}
    end.

handle_authenticate(S=#st{login=L, password=P}) ->
    Path = [<<"user">>, <<"sessionid">>],
    Params = [{<<"login">>, L}, {<<"password">>, P}],
    case do_request(get, Path, Params, S) of
        {ok, SessId} ->
            {ok, S#st{session_id=SessId}};
        Error={error, _} ->
            {Error, S}
    end.

do_request(Method, Path, Params, #st{base_url=BaseUrl, request_opts=ReqOpts}) ->
    Path1 = join([BaseUrl|Path], $/),
    case hackney:request(Method, Path1, [], {form, Params}, ReqOpts) of
        {ok, Status, _Headers, Client} when Status =:= 200;
                                            Status =:= 201 ->
            case hackney:body(Client) of
                {ok, RespBody} ->
                    {ok, decode_body(RespBody)};
                {error, _Reason} = Error ->
                    Error
            end;
        {ok, Status, _Headers, Client} ->
            case hackney:body(Client) of
                {ok, RespBody} ->
                    ?debug("~p ~p -> ~p", [Path1, Params, RespBody]),
                    {error, {Status, decode_resp(RespBody)}};
                {error, _Reason} -> 
                    {error, {Status, undefined}}
            end;
        {error, R} ->
            {error, R}
    end.

decode_resp(Data) ->
    {ok, Res} =
        sutil:maybe(fun () -> jiffy:decode(Data) end,
                    fun ({KVs=[{_K,_V}|_]}) ->
                            case proplists:get_value(<<"Code">>, KVs) of
                                undefined ->
                                    KVs;
                                Code ->
                                    decode_rest_code(Code)
                            end;
                        (Json) ->
                            Json
                    end,
                    fun (_) -> Data end),
    Res.

decode_body(B= <<>>) ->
    B;
decode_body(Body) ->
    jiffy:decode(Body).

decode_rest_code(1) -> argument_required;
decode_rest_code(2) -> invalid_argument;
decode_rest_code(3) -> invalid_session;
decode_rest_code(4) -> unauthorized;
decode_rest_code(5) -> no_credit;
decode_rest_code(6) -> invalid_operation;
decode_rest_code(7) -> forbidden;
decode_rest_code(8) -> bad_gateway;
decode_rest_code(9) -> internal;
decode_rest_code(Code) -> Code.

join(Parts, Sep) ->
    join(Parts, Sep, <<>>).

join([], _Sep, Ret) ->
    Ret;
join([P], _Sep, Acc) ->
    <<Acc/binary, P/binary>>;
join([P|Rest], Sep, Acc) ->
    join(Rest, Sep, <<Acc/binary, P/binary, Sep>>).

ensure_binary(L) when is_list(L) ->
    list_to_binary(L);
ensure_binary(B) when is_binary(B) ->
    B.
