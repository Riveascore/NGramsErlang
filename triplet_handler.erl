-module(triplet_handler).
-export([overall_counter/4,count_triplet/4,send_triplets/3,send_chunk_off/3,update_counters/2,overall_counter/3,make_triplet_generators/4,make_triplet_counters/4,generate_triplet/1,count_triplet/5]).

send_chunk_off([], ListOfTripletGenerators, Finished) ->
    ok;

send_chunk_off(ChunkList, ListOfTripletGenerators, Finished) ->
    % here, send message with Chunk to randomly selected triplet_generator
    RandomNumber = crypto:rand_uniform(1, length(ListOfTripletGenerators)+1),
    TripletGenerator = lists:nth(RandomNumber, ListOfTripletGenerators),
    TripletGenerator ! {chunk, ChunkList, Finished}.

count_triplet(OverallCounterPID, NumberOfMessagesReceived, MaxMessagesAllowed, TableNameSuffix, true) ->

    TableNamePrefix = atom_to_list(countTriplet),
    TableName = list_to_atom(TableNamePrefix++TableNameSuffix),

    ets:new(TableName, [named_table]),
    count_triplet(OverallCounterPID, NumberOfMessagesReceived, MaxMessagesAllowed, TableName).

count_triplet(OverallCounterPID, NumberOfMessagesReceived, MaxMessagesAllowed, TableName) ->
    receive
	{triplet, Triplet, Finished} ->
	    io:fwrite("Triplet: ~p, on node: ~p~n", [Triplet, node()]),
	    %NewTripletMap = lists:append(TripletMap, [{Triplet, 1}]),
	    update_counters([{Triplet, 1}], TableName),

	    case NumberOfMessagesReceived >= MaxMessagesAllowed of
		true ->
		    TotalTripletMap = ets:tab2list(TableName),
		    io:fwrite("TotalTripletMap: ~p~n", [TotalTripletMap]),
		    OverallCounterPID ! {tripletMap, TotalTripletMap, Finished},
		    ets:delete_all_objects(TableName),
		    NewNumberOfMessagesReceived = 0;
		false ->
		    NewNumberOfMessagesReceived = NumberOfMessagesReceived+1
            end
    after
	1000 ->
	    TotalTripletMap = ets:tab2list(TableName),  
	    OverallCounterPID ! {tripletMap, TotalTripletMap, false},
	    ets:delete_all_objects(TableName),
	    NewNumberOfMessagesReceived = 0
    end,
    
    count_triplet(OverallCounterPID, NewNumberOfMessagesReceived, MaxMessagesAllowed, TableName).

send_triplets(ListOfTripletCounters, ChunkList, Finished) ->
    case length(ChunkList) > 2 of
	true ->  
	    % get triplet, send message to TC based on hash on LOTCs, call send_trips again
	    Triplet = lists:sublist(ChunkList, 3),
	    [_|Rest] = ChunkList,
	    Hash = erlang:phash2(Triplet),
	    ChosenCounterIndex = (Hash rem length(ListOfTripletCounters)) + 1,
	    TripletCounter = lists:nth(ChosenCounterIndex, ListOfTripletCounters),
	    TripletCounter ! {triplet, Triplet, Finished},

	    send_triplets(ListOfTripletCounters, Rest, Finished);
	false ->
	    ok
    end.
	

generate_triplet(ListOfTripletCounters) ->
    receive
	{chunk, ChunkList, Finished} ->
	    send_triplets(ListOfTripletCounters, ChunkList, Finished),
	    generate_triplet(ListOfTripletCounters)
    end.

make_triplet_counters(0, TripletCounterList, OverallCounter, CounterLoopPID) ->
    TripletCounterList;

make_triplet_counters(NumberLeft, TripletCounterList, OverallCounter, CounterLoopPID) ->
    Node = node_handler:round_robin(CounterLoopPID),
    
    MaxMessagesAllowed = crypto:rand_uniform(2, 10),
    
    TableNameSuffix = lists:flatten(io_lib:format("~p", [NumberLeft])),

    %spawn(Node, ets, new, [TableName, [ordered_set, named_table]]), <- this is old and doesn't work cuz Erlang is mean :(
    TripletCounterPID = spawn(Node, triplet_handler, count_triplet, [OverallCounter, 0, MaxMessagesAllowed, TableNameSuffix, true]),
    
    NewList = lists:append(TripletCounterList, [TripletCounterPID]),
    make_triplet_counters(NumberLeft-1, NewList, OverallCounter, CounterLoopPID).

make_triplet_generators(0, TripletGeneratorList, TripletCounterList, CounterLoopPID) ->
    TripletGeneratorList;

make_triplet_generators(NumberLeft, TripletGeneratorList, TripletCounterList, CounterLoopPID) ->
    Node = node_handler:round_robin(CounterLoopPID),
    TripletGeneratorPID = spawn(Node, triplet_handler, generate_triplet, [TripletCounterList]),
    NewList = lists:append(TripletGeneratorList, [TripletGeneratorPID]),
    make_triplet_generators(NumberLeft-1, NewList, TripletCounterList, CounterLoopPID).

overall_counter(TableName, NumberOfFiles, FilesCompleted, true) ->
    %ets:new(TableName, [named_table]),
    NewTableName = overallCounter,
    ets:new(NewTableName, [named_table]),
    overall_counter(NewTableName, NumberOfFiles, FilesCompleted).

overall_counter(TableName, NumberOfFiles, FilesCompleted) ->
    receive
	{tripletMap, TripletMap, Finished} ->
	    update_counters(TripletMap, TableName),
	    case Finished of
		true ->
		    NewFilesCompleted = FilesCompleted + 1;
		false ->
		    NewFilesCompleted = FilesCompleted
	    end,

	    case NumberOfFiles >= NewFilesCompleted of
		true ->
		   io:fwrite("Whole Table: ~p~n", [ets:tab2list(TableName)]);
		false ->
		   overall_counter(TableName, NumberOfFiles, NewFilesCompleted)
	    end
    end.

update_counters([], TableName) ->
    ok;
update_counters(TripletMap, TableName) ->
    [TripletObject|Rest] = TripletMap,
    %io:fwrite("TripletObject: ~p~n", [TripletObject]),

    Triplet = element(1, TripletObject),
    Count = element(2, TripletObject),

    %io:fwrite("TableName: ~p, Triplet: ~p, node: ~p~n", [TableName, Triplet, node()]),
    %io:fwrite("member? ~p~n", [ets:member(TableName, Triplet)]),
    case ets:member(TableName, Triplet) of
	true ->
	    ets:update_counter(TableName, Triplet, Count);
	false ->
	    ets:insert_new(TableName, {Triplet, Count})
    end,

    update_counters(Rest, TableName).
