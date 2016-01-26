%%  [ct_tester:start(list_to_atom(X))|| X <- [[Y] || Y <- "abcde"]].

-module(ct_tester).
-compile([debug_info]).

-include("ct_records.hrl").

-behavior(gen_server).

-export([start/2]).
-export([init/1, handle_call/3, handle_cast/2,
  handle_info/2, code_change/3, terminate/2]).

-ifdef(debug).  % FIXME
-define(LOG(X), io:format("[~p,~p]: ~p~n", [?MODULE,?LINE,X])).
-else.
-define(LOG(X), true).
-endif.

-define(MAX_OP_INTERVAL, 1000). % max inter-operation interval
-define(MAX_OPERATIONS, 10).    % max number of operations
-define(READ_PROBABILITY, 2).   % 1 out of X is a read

% External API
start(Id, Store) when is_atom(Id), is_atom(Store) ->
  gen_server:start({local, Id}, ?MODULE, [Id, Store], []).

% Functions called by gen_server
init([Id, StoreModule]) ->
  process_flag(trap_exit, true), % To know when the parent shuts down
  random:seed(erlang:timestamp()), % To do once per process
  Timeout = random:uniform(?MAX_OP_INTERVAL),
  NumOp = random:uniform(?MAX_OPERATIONS),
  io:format("Client ~s initialized.~n", [Id]),
  {ok, #state{id=Id, store=StoreModule, num_op=NumOp, ops=[]}, Timeout}.

handle_call(_Message, _From, S) -> {noreply, S, random:uniform(?MAX_OP_INTERVAL)}.

handle_cast(_Message, S) -> {noreply, S, random:uniform(?MAX_OP_INTERVAL)}.

handle_info(timeout, S = #state{num_op=0}) ->
  {stop, normal, S};
handle_info(timeout, S = #state{id=N, num_op=NumOp, ops=Ops}) ->
  StartTime = erlang:monotonic_time(),
  case random:uniform(?READ_PROBABILITY) of
    1 ->
      OpType = read,
      Res = erlang:apply(S#state.store, read, [key]),
      io:format("Client ~s reads.~n",[N]);
    _ ->
      OpType = write,
      Res = erlang:apply(S#state.store, write,
        [key, erlang:unique_integer([monotonic,positive])]), % unique value, monotonic
      io:format("Client ~s writes.~n",[N])
  end,
  EndTime = erlang:monotonic_time(),
  %OpLatency = EndTime - StartTime,
  StateNew=S#state{num_op=(NumOp-1), ops = [#op{op_type=OpType,
    start_time = StartTime, end_time = EndTime, result = Res} | Ops]},
  Timeout = random:uniform(?MAX_OP_INTERVAL),
  {noreply, StateNew, Timeout};
handle_info(_Message, S) ->
  io:format("Client ~s received a message: ~s.~n",[S#state.id,_Message]),
  Timeout = random:uniform(?MAX_OP_INTERVAL),
  {noreply, S, Timeout}.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

terminate(normal, S) ->
  ets:insert(ops_db, {S#state.id, S#state.ops}),
  io:format("Client ~s terminated.~n",[S#state.id]);
terminate(Reason, S) ->
  io:format("Client ~s terminated, reason: ~p. State: ~p~n",[S#state.id, Reason, S#state.ops]).
