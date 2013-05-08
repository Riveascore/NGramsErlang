-module(ngrams).
-export([ngrams/5]).
-import(triplet_handler, [make_triplet_counters/4, make_triplet_generators/4]).

ngrams(ListOfFiles, ListOfHosts, NumberOfTripletGenerators, NumberOfTripletCounters, ChunkSize) ->
    
    %FIRST, very important!!!
    %Have to ping all nodes based off of hosts so that round_robin doesn't poop itself
    net_adm:world_list(ListOfHosts),
    %now, [node()|nodes()] will get all nodes instead of just the ones running on the box that round_robin happens on (this one)

    %create ets table for counting total triplet counts
    TableName = overallCounter,
    ets:new(TableName, [ordered_set,named_table]),
    

    %create counter_loop for round robin distribution of processes
    CounterLoop = spawn(node_handler, counter_loop, [0]),

    %spawn process to handle total counts
    OverallCounterNode = node_handler:round_robin(CounterLoop),
    OverallCounterPID = spawn(OverallCounterNode, triplet_handler, overall_counter, [TableName, length(ListOfFiles), 0]),
      
    %make triplet counter list
    TripletCounterList = make_triplet_counters(NumberOfTripletCounters, [], OverallCounterPID, CounterLoop),
    										     
    %make triplet generator list
    TripletGeneratorList = make_triplet_generators(NumberOfTripletGenerators, [], TripletCounterList, CounterLoop),
    
    %Start handling files n stuff
    file_handler:processFiles(ListOfFiles, CounterLoop, ChunkSize, TripletGeneratorList).
