-module(triplet_handler).
-export([send_chunk_off/2,update_counters/2,overall_counter/3,make_triplet_generators/4,make_triplet_counters/4,generate_triplet/1,count_triplet/1]).
-record(triplet, {triplet=[], count=0}).


send_chunk_off(ChunkList, ListOfTripletGenerators) ->
    io:fwrite("ChunkList ~p~n", [ChunkList]).

count_triplet(OverallCounterPID) ->
    receive
	{triplet, Triplet} ->
	    count_triplet(OverallCounterPID)
    end.

generate_triplet(ListOfTripletCounters) ->
    receive
	{chunk, ChunkList} ->
	    %do stuff with ChunkList here :)
	    generate_triplet(ListOfTripletCounters)
    end.

make_triplet_counters(0, TripletCounterList, OverallCounter, CounterLoopPID) ->
    TripletCounterList;

make_triplet_counters(NumberLeft, TripletCounterList, OverallCounter, CounterLoopPID) ->
    Node = node_handler:round_robin(CounterLoopPID),
    TripletCounterPID = spawn(Node, triplet_handler, count_triplet, [OverallCounter]),
    NewList = lists:append(TripletCounterList, TripletCounterPID),
    make_triplet_counters(NumberLeft-1, NewList, OverallCounter, CounterLoopPID).

make_triplet_generators(0, TripletGeneratorList, TripletCounterList, CounterLoopPID) ->
    TripletGeneratorList;

make_triplet_generators(NumberLeft, TripletGeneratorList, TripletCounterList, CounterLoopPID) ->
    Node = node_handler:round_robin(CounterLoopPID),
    TripletGeneratorPID = spawn(Node, triplet_handler, generate_triplet, [TripletCounterList]),
    NewList = lists:append(TripletGeneratorList, TripletGeneratorPID),
    make_triplet_generators(NumberLeft-1, NewList, TripletCounterList, CounterLoopPID).

overall_counter(TableName, NumberOfFiles, FilesCompleted) ->
    receive
	{triplet, TripletMap} ->
	    spawn(triplet_handler, update_counters, [TripletMap, TableName]),
	    overall_counter(TableName, NumberOfFiles, FilesCompleted);
	{file_finished} ->
	    NewFilesCompleted = FilesCompleted + 1,
	    case NumberOfFiles == NewFilesCompleted of
		true ->
		    io:fwrite("done");
		false ->
		    overall_counter(TableName, NumberOfFiles, NewFilesCompleted)
	    end
    end.

update_counters([], TableName) ->
    ok;
update_counters(TripletMap, TableName) ->
    [Triplet|Rest] = TripletMap,
    case ets:member(TableName, Triplet#triplet.triplet) of
	true ->
	    ets:update_counter(TableName, Triplet#triplet.triplet, Triplet#triplet.count);
	false ->
	    ets:insert_new(TableName, {Triplet#triplet.triplet, Triplet#triplet.count})
    end,
    update_counters(Rest, TableName).
