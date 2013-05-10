-module(handle_triplets).
-export([overall_counter/7,count_triplet/4,send_triplets/2,send_chunk_off/2,update_counters/2,overall_counter/6,make_triplet_generators/4,make_triplet_counters/4,generate_triplet/1,count_triplet/5]).

send_chunk_off([], ListOfTripletGenerators) ->
    ok;

send_chunk_off(ChunkList, ListOfTripletGenerators) ->
    % here, send message with Chunk to randomly selected triplet_generator
    RandomNumber = crypto:rand_uniform(1, length(ListOfTripletGenerators)+1),
    TripletGenerator = lists:nth(RandomNumber, ListOfTripletGenerators),
    TripletGenerator ! {chunk, ChunkList}.

count_triplet(OverallCounterPID, NumberOfMessagesReceived, MaxMessagesAllowed, TableNameSuffix, true) ->

    TableNamePrefix = atom_to_list(countTriplet),
    TableName = list_to_atom(TableNamePrefix++TableNameSuffix),
    ets:new(TableName, [named_table, ordered_set]),
    count_triplet(OverallCounterPID, NumberOfMessagesReceived, MaxMessagesAllowed, TableName).

count_triplet(OverallCounterPID, NumberOfMessagesReceived, MaxMessagesAllowed, TableName) ->
    receive
	{triplet, Triplet} ->
	    update_counters([{Triplet, 1}], TableName),

	    case NumberOfMessagesReceived >= MaxMessagesAllowed of
		true ->
		    %somehow we're not sending the correct amount of NumberOfMessagesReceived here :(
		    TripletMap = ets:tab2list(TableName),
		    %io:fwrite("TripletMap: ~p, sent from node: ~p, to overall counter, NumberOfMessagesReceived: ~p~n", [TripletMap, node(), NumberOfMessagesReceived+1]),
		    OverallCounterPID ! {triplet_map, TripletMap, NumberOfMessagesReceived+1},
		    ets:delete_all_objects(TableName),
		    NewNumberOfMessagesReceived = 0;
		false ->
		    NewNumberOfMessagesReceived = NumberOfMessagesReceived+1
            end
    after
	1000 ->
	    NewNumberOfMessagesReceived = 0,
	    case ets:tab2list(TableName) of
		[] -> 
		    ok;
		TripletMap ->
		    %io:fwrite("After waiting 1 second, TripletMap: ~p, sent from node: ~p, to overall counter~n", [TripletMap, node()]),
	    	    OverallCounterPID ! {triplet_map, TripletMap, NumberOfMessagesReceived},
	    	    ets:delete_all_objects(TableName)
	    end 
    end,
    
    count_triplet(OverallCounterPID, NewNumberOfMessagesReceived, MaxMessagesAllowed, TableName).

send_triplets(ListOfTripletCounters, ChunkList) ->
    case length(ChunkList) > 2 of
	true ->  
	    % get triplet, send message to TC based on hash on LOTCs, call send_trips again
	    Triplet = lists:sublist(ChunkList, 3),
	    [_|Rest] = ChunkList,
	    Hash = erlang:phash2(Triplet),
	    ChosenCounterIndex = (Hash rem length(ListOfTripletCounters)) + 1,
	    TripletCounter = lists:nth(ChosenCounterIndex, ListOfTripletCounters),
	    TripletCounter ! {triplet, Triplet},

	    send_triplets(ListOfTripletCounters, Rest);
	false ->
	    ok
    end.
	

generate_triplet(ListOfTripletCounters) ->
    receive
	{chunk, ChunkList} ->
	    send_triplets(ListOfTripletCounters, ChunkList),
	    generate_triplet(ListOfTripletCounters)
    end.

make_triplet_counters(0, TripletCounterList, OverallCounter, CounterLoopPID) ->
    TripletCounterList;

make_triplet_counters(NumberLeft, TripletCounterList, OverallCounter, CounterLoopPID) ->
    Node = node_handler:round_robin(CounterLoopPID),
    
    MaxMessagesAllowed = crypto:rand_uniform(50, 100),
    
    TableNameSuffix = lists:flatten(io_lib:format("~p", [NumberLeft])),

    %spawn(Node, ets, new, [TableName, [ordered_set, named_table]]), <- this is old and doesn't work cuz Erlang is mean :(
    TripletCounterPID = spawn(Node, handle_triplets, count_triplet, [OverallCounter, 0, MaxMessagesAllowed, TableNameSuffix, true]),
    
    NewList = lists:append(TripletCounterList, [TripletCounterPID]),
    make_triplet_counters(NumberLeft-1, NewList, OverallCounter, CounterLoopPID).

make_triplet_generators(0, TripletGeneratorList, TripletCounterList, CounterLoopPID) ->
    TripletGeneratorList;

make_triplet_generators(NumberLeft, TripletGeneratorList, TripletCounterList, CounterLoopPID) ->
    Node = node_handler:round_robin(CounterLoopPID),
    TripletGeneratorPID = spawn(Node, handle_triplets, generate_triplet, [TripletCounterList]),
    NewList = lists:append(TripletGeneratorList, [TripletGeneratorPID]),
    make_triplet_generators(NumberLeft-1, NewList, TripletCounterList, CounterLoopPID).

overall_counter(StartTime, NumberOfFiles, FilesCompleted, AddedTriplets, TotalTriplets, TripletsReceived, true) ->
    ets:new(overallCounter, [named_table, ordered_set]),
    overall_counter(StartTime, NumberOfFiles, FilesCompleted, AddedTriplets, TotalTriplets, TripletsReceived).

overall_counter(StartTime, NumberOfFiles, FilesCompleted, AddedTriplets, TotalTriplets, TripletsReceived) ->
    
    receive
	{added_triplets, AddedTripletsToComplete} ->
	    UpdatedTripletsToComplete = AddedTriplets + AddedTripletsToComplete,
	    %io:fwrite("AddedTriplets: ~p, TotalTriplets: ~p~n", [UpdatedTripletsToComplete, TotalTriplets]),
	    overall_counter(StartTime, NumberOfFiles, FilesCompleted, UpdatedTripletsToComplete, TotalTriplets, TripletsReceived);
	{eof} ->
	    NewFilesCompleted = FilesCompleted + 1,
	    case NewFilesCompleted == NumberOfFiles of
		true ->
		    overall_counter(StartTime, NumberOfFiles, NewFilesCompleted, AddedTriplets, AddedTriplets, TripletsReceived);
		false ->
		    overall_counter(StartTime, NumberOfFiles, NewFilesCompleted, AddedTriplets, TotalTriplets, TripletsReceived)
	    end;
	{triplet_map, TripletMap, NumberOfTriplets} ->
	    NewTripletsReceived = TripletsReceived + NumberOfTriplets,
	    %io:fwrite("AddedTriplets: ~p, TotalTriplets: ~p, TripletsReceived: ~p~n", [AddedTriplets, TotalTriplets, NumberOfTriplets]),
	    %io:fwrite("TripletMap received: ~p~n", [TripletMap]),
	    update_counters(TripletMap, overallCounter),
	    case NewTripletsReceived == TotalTriplets of
		true ->
		    %tv:start();
		    TimeStop = now(),
		    %io:fwrite("Table, on node: ~p~n~p~n", [node(), ets:tab2list(overallCounter)]),
		    io:fwrite("Total time: ~p~n", [timer:now_diff(TimeStop, StartTime)/1000000]);
		false ->
		    overall_counter(StartTime, NumberOfFiles, FilesCompleted, AddedTriplets, TotalTriplets, NewTripletsReceived)
	    end
     end.

update_counters([], TableName) ->
    ok;
update_counters(TripletMap, TableName) ->
    [TripletObject|Rest] = TripletMap,

    Triplet = element(1, TripletObject),
    Count = element(2, TripletObject),

    case ets:member(TableName, Triplet) of
	true ->
	    ets:update_counter(TableName, Triplet, Count);
	false ->
	    ets:insert_new(TableName, {Triplet, Count})
    end,

    update_counters(Rest, TableName).
