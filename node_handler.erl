-module(node_handler).
-export([counter_loop/1,round_robin/1]).

counter_loop(Count) ->
    receive
	{update, FromPID} ->
	    FromPID ! {count_value, Count},
	    counter_loop(Count+1)
    end.

round_robin(CounterPID) ->
    CounterPID ! {update, self()},
    receive 
	{count_value, Count} ->
	    Counter = Count
    end,
    Nodes = [node()|nodes()],
    Node = lists:nth(length(Nodes)-(Counter rem length(Nodes)), Nodes),
    Node.
