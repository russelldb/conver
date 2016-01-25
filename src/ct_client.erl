-module(ct_client).
-export([behaviour_info/1]).

%% init/1, some_fun/0 and other/3 are now expected callbacks
behaviour_info(callbacks) -> [{init,1}, {read,1}, {write,2}, {delete,1}];
behaviour_info(_) -> undefined.