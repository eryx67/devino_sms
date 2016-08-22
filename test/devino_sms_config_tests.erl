-module(devino_sms_config_tests).

-include_lib("eunit/include/eunit.hrl").
-compile(export_all).

basic_test() ->
    Conf =
        [
         {["devino_sms", "password"], "pass"}
        , {["devino_sms", "login"], "user"}
        , {["devino_sms", "address"], "addr"}
        ],

    Config = cuttlefish_unit:generate_templated_config(
               ["../priv/devino_sms.schema"], Conf, []),

    ?debugFmt("~P", [Config, 1024]),
    ok.
