-module(ct_god).
-behaviour(gen_server).

-export([start_link/0,stop/0]).
-export([init_map/0]).
-export([init/1, handle_call/3,handle_cast/2,terminate/2,code_change/3,handle_info/2]).

-record(state,{}).

start_link() ->
    gen_server:start_link({local,?MODULE}, ?MODULE, [], []).
%% Client API    
init_map() ->
    gen_server:call(?MODULE, {init_map}).

%% Internal functions
init([]) ->
	io:format("ct_god has started (~w)~n", [self()]),
	State=#state{},
    {ok, State}.
stop() -> gen_server:cast(?MODULE, stop).

%% User Callbacks
handle_call({init_map}, _From, State) ->
    io:format("Creating map ~p~n", [_From]),
    X_list=lists:seq(1,ct_config:get_room_setup_max_x()),
    Y_list=lists:seq(1,ct_config:get_room_setup_max_y()),
    Combined_list=lists:foldl(fun (X, Acc) -> Acc ++ lists:map(fun (Y) -> [X,Y] end, X_list) end, [], Y_list),
    lists:foldl( fun(Room_coords, Sum) -> ct_room_sup:create_room(Room_coords), Sum+1 end,0, Combined_list),
    {reply, ok, State}.


%% System Callbacks
terminate(_Reason, State) -> {ok,State}.
handle_cast(stop, State) -> {stop, normal, State}.
code_change(_OldVsn, State, _Extra) -> {ok, State}.
handle_info( _, State) -> {noreply,State}.