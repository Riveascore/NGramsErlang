-module(triplet_handler).
-export([send_triplets/2,send_chunk_off/2,update_counters/2,overall_counter/3,make_triplet_generators/4,make_triplet_counters/4,generate_triplet/1,count_triplet/4]).

send_chunk_off([], ListOfTripletGenerators) ->
    ok;

send_chunk_off(ChunkList, ListOfTripletGenerators) ->
    % here, send message with Chunk to randomly selected triplet_generator
    RandomNumber = crypto:rand_uniform(1, length(ListOfTripletGenerators)+1),
    TripletGenerator = lists:nth(RandomNumber, ListOfTripletGenerators),
    TripletGenerator ! {chunk, ChunkList}.
 
count_triplet(OverallCounterPID, NumberOfMessagesReceived, MaxMessagesAllowed, TripletMap) ->
    receive
	{triplet, Triplet} ->
	    
	    NewTripletMap = lists:append(TripletMap, [{Triplet, 1}]),
	    update_counters(NewTripletMap, countTriplet),

	    case NumberOfMessagesReceived >= MaxMessagesAllowed of
		true ->
		    % if received MaxMessagesAllowed messages or waited 10 seconds, send to overallcounter, erase table, and call count_triplet
		    TotalTripletMap = ets:tab2list(countTriplet),
		    OverallCounterPID ! {tripletMap, TotalTripletMap},
		    ets:delete_all_objects(countTriplet),
		    count_triplet(OverallCounterPID, 0, MaxMessagesAllowed, TripletMap);
		false ->
		    count_triplet(OverallCounterPID, NumberOfMessagesReceived+1, MaxMessagesAllowed, TripletMap)
            end
    after
	5000 ->   
	    TotalTripletMap = ets:tab2list(countTriplet),
	    OverallCounterPID ! {tripletMap, TotalTripletMap},
       	    ets:delete_all_objects(countTriplet),		
	    count_triplet(OverallCounterPID, 0, MaxMessagesAllowed, TripletMap) 
    end.

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
    
    MaxMessagesAllowed = crypto:rand_uniform(10, 100),
    TripletCounterPID = spawn(Node, triplet_handler, count_triplet, [OverallCounter, 0, MaxMessagesAllowed, []]),
    
    % make new ets table on particular Node, since ets tables
    % can have the same name IF they're on different nodes
    TableName = countTriplet, 
    spawn(Node, ets, new, [TableName, [ordered_set, named_table]]),
    
    NewList = lists:append(TripletCounterList, [TripletCounterPID]),
    make_triplet_counters(NumberLeft-1, NewList, OverallCounter, CounterLoopPID).

make_triplet_generators(0, TripletGeneratorList, TripletCounterList, CounterLoopPID) ->
    TripletGeneratorList;

make_triplet_generators(NumberLeft, TripletGeneratorList, TripletCounterList, CounterLoopPID) ->
    Node = node_handler:round_robin(CounterLoopPID),
    TripletGeneratorPID = spawn(Node, triplet_handler, generate_triplet, [TripletCounterList]),
    NewList = lists:append(TripletGeneratorList, [TripletGeneratorPID]),
    make_triplet_generators(NumberLeft-1, NewList, TripletCounterList, CounterLoopPID).

overall_counter(TableName, NumberOfFiles, FilesCompleted) ->
    receive
	{tripletMap, TripletMap} ->
	    spawn(triplet_handler, update_counters, [TripletMap, TableName]),
	    overall_counter(TableName, NumberOfFiles, FilesCompleted);
	{file_finished} ->
	    NewFilesCompleted = FilesCompleted + 1,
	    case NumberOfFiles == NewFilesCompleted of
		true ->
		    io:fwrite("Whole program is finished, well done!");
		false ->
		    overall_counter(TableName, NumberOfFiles, NewFilesCompleted)
	    end
    end.

update_counters([], TableName) ->
    ok;
update_counters(TripletMap, TableName) ->
    [TripletObject|Rest] = TripletMap,

    Triplet = element(1, TripletObject),
    Count = element(2, TripletObject),
    ets:member(TableName, Triplet),
    %io:fwrite("TableName: ~p, Triplet: ~p, Node: ~p, Exists?: ~p~n", [TableName, Triplet, node(), ets:member(TableName, Triplet)]),
    

    case ets:member(TableName, Triplet) of
	true ->
	    ets:update_counter(TableName, Triplet, Count);
	false ->
	    ets:insert_new(TableName, TripletObject)
    end,

    update_counters(Rest, TableName).
