-module(sudoku).
-import(lists, [member/2]).
-compile(export_all).

cross(SeqA, SeqB) ->
    %% Cross product of elements in SeqA and elements in SeqB.
    [[X,Y] || X <- SeqA, Y <- SeqB].

digits() ->
    "123456789".
rows() ->
    "ABCDEFGHI".
cols() ->
    digits().

squares() ->
    %% Returns a list of 81 square names, including "A1" etc.
    cross(rows(), cols()).

col_squares() ->
    %% All the square names for each column.
    [cross(rows(), [C]) || C <- cols()].
row_squares() ->
    %% All the square names for each row.
    [cross([R], cols()) || R <- rows()].
box_squares() ->
    %% All the square names for each box.
    [cross(Rows, Cols) || Rows <- ["ABC", "DEF", "GHI"],
                          Cols <- ["123", "456", "789"]].

unitlist() ->
    %% A list of all units (columns, rows, boxes) in a grid.
    col_squares() ++ row_squares() ++ box_squares().

units(Square) ->
    %% A list of units for a specific square
    [S || S <- unitlist(), member(Square, S)].

peers(Square) ->
    %% A unique list of squares (excluding this one)
    %% that are also part of the units for this square.
    NonUniquePeers = shallow_flatten([S || S <- units(Square)]),
    PeerSet = sets:from_list(NonUniquePeers),
    PeersWithSelf = sets:to_list(PeerSet),
    lists:delete(Square, PeersWithSelf).

shallow_flatten([]) -> [];
shallow_flatten(List) ->
    [H|T] = List,
    H ++ shallow_flatten(T).

grid_values(GridString) ->
    %% Converts a string of values into a dictionary of values keyed on square name.
    %% Non-digits and "0" is allowed here, it indicates an unset square.
    81 = length(GridString),
    Tuples =  lists:zipwith(fun zipfun/2, squares(), GridString),
    dict:from_list(Tuples).

zipfun(Square, Digit) ->
    Digits = digits(),
    case member(Digit, Digits) of
        true -> {Square, [Digit]};
        false -> {Square, Digits}
    end.

eliminate(ValuesDict, [], _) ->
    ValuesDict;

eliminate(ValuesDict, Squares, Digits) ->
    %% Eliminate the specified Digits from all specified Squares.
    [Square|T] = Squares,
    OldValues = dict:fetch(Square, ValuesDict),
    NewValues = lists:filter(fun(E) -> not member(E, Digits) end, OldValues),
    NewDict1 = dict:store(Square, NewValues, ValuesDict),
    NewDict2 = peer_eliminate(NewDict1, Square, NewValues, OldValues),
    eliminate(NewDict2, T, Digits).

peer_eliminate(ValuesDict, _, Vals, Vals) ->
    %% NewValues and OldValues are the same, already eliminated.
    ValuesDict;

peer_eliminate(ValuesDict, Square, [AssignedValue], _) ->
    %% If there is only one value left, we can also
    %% eliminate that value from the peers of Square
    Peers = peers(Square),
    eliminate(ValuesDict, Peers, [AssignedValue]);

peer_eliminate(ValuesDict, _, _, _) ->
    %% Multiple values, cannot eliminate from peers.
    ValuesDict.

assign(ValuesDict, Square, Digit) ->
    %% Assign by eliminating all values except the assigned value.
    OtherValues = lists:delete(Digit, dict:fetch(Square, ValuesDict)),
    eliminate(ValuesDict, [Square], OtherValues).

display(ValuesDict) ->
    Fun = fun({_, [V]}) -> [V];
             ({_, _}) -> "."
          end,
    lists:flatmap(Fun, lists:sort(dict:to_list(ValuesDict))).

solve(GridString) ->
    display(grid_values(GridString)).
