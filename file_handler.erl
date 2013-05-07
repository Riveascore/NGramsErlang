-module(file_handler).
%-export([file_reader/2,make_file_readers/1,normalize_list/1,index/1,processFile/1,processChunks/2,processChunk/2]).
-export([normalize_list/1]).
-define(Punctuation,"(\\ |\\,|\\.|\\;|\\:|\\t|\\n|\\(|\\))+").

normalize_list(List) ->
    lists:map(fun(Word) -> string:to_lower(Word) end, List).
		      
