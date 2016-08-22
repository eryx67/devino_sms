%%% @author Vladimir G. Sekissov <eryx67@gmail.com>
%%% @copyright (C) 2014, Vladimir G. Sekissov
%%% @doc API SMS-серрвиса http://www.devinotele.com/support/api
%%% ++++
%%% <p/>
%%% ++++
%%% @end
%%% Created : 15 Dec 2014 by Vladimir G. Sekissov <eryx67@gmail.com>

-module(devino_sms).

-export([start/0, stop/0, send/2, pool_name/0, get_env/1, get_env/2]).

-define(APP, ?MODULE).

start() ->
    sutil:start_app_deps(?APP).

stop() ->
    application:stop(?APP).

-spec send(DestAddrs::[string()], Data::string()) ->
                  {ok, term()}|{error, term()}.
send(DestAddrs, Data) ->
    Msg = {send_sms, DestAddrs, Data, undefined},
    gen_server:call(devino_sms_srv, Msg, infinity).

pool_name() ->
    ?APP.

get_env(Key) ->
    Default = make_ref(),
    case get_env(Key, Default) of
        Default ->
            undefined;
        Val ->
            {ok, Val}
    end.

get_env(Key, Default) ->
    gproc:get_set_env(l, ?APP, Key, [app_env, {default, Default}]).
