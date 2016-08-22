-module(devino_sms_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    PoolName = devino_sms:pool_name(),
    Options = [{timeout, 150000}, {max_connections, 10}],
    ok = hackney_pool:start_pool(PoolName, Options),
    devino_sms_sup:start_link().

stop(_State) ->
    hackney_pool:stop_pool(devino_sms:pool_name()),
    ok.
