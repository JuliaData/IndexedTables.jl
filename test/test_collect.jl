using IndexedTables: collect_columns_flattened

@testset "collectnamedtuples" begin
    v = [@NT(a = 1, b = 2), @NT(a = 1, b = 3)]
    @test collect_columns(v) == Columns(@NT(a = Int[1, 1], b = Int[2, 3]))

    # test inferrability with constant eltype
    itr = [@NT(a = 1, b = 2), @NT(a = 1, b = 2), @NT(a = 1, b = 12)]
    st = start(itr)
    el, st = next(itr, st)
    dest = similar(IndexedTables.arrayof(typeof(el)), 3)
    dest[1] = el
    @inferred IndexedTables.collect_to_columns!(dest, itr, 2, st)

    v = [@NT(a = 1, b = 2), @NT(a = 1.2, b = 3)]
    @test collect_columns(v) == Columns(@NT(a = [1, 1.2], b = Int[2, 3]))
    @test typeof(collect_columns(v)) == typeof(Columns(@NT(a = [1, 1.2], b = Int[2, 3])))

    v = [@NT(a = 1, b = 2), @NT(a = 1.2, b = "3")]
    @test collect_columns(v) == Columns(@NT(a = [1, 1.2], b = Any[2, "3"]))
    @test typeof(collect_columns(v)) == typeof(Columns(@NT(a = [1, 1.2], b = Any[2, "3"])))

    v = [@NT(a = 1, b = 2), @NT(a = 1.2, b = 2), @NT(a = 1, b = "3")]
    @test collect_columns(v) == Columns(@NT(a = [1, 1.2, 1], b = Any[2, 2, "3"]))
    @test typeof(collect_columns(v)) == typeof(Columns(@NT(a = [1, 1.2, 1], b = Any[2, 2, "3"])))

    # length unknown
    itr = Iterators.filter(isodd, 1:8)
    tuple_itr = (@NT(a = i+1, b = i-1) for i in itr)
    @test collect_columns(tuple_itr) == Columns(@NT(a = [2, 4, 6, 8], b = [0, 2, 4, 6]))
    tuple_itr_real = (i == 1 ? @NT(a = 1.2, b =i-1) : @NT(a = i+1, b = i-1) for i in itr)
    @test collect_columns(tuple_itr_real) == Columns(@NT(a = Real[1.2, 4, 6, 8], b = [0, 2, 4, 6]))

    # empty
    itr = Iterators.filter(t -> t > 10, 1:8)
    tuple_itr = (@NT(a = i+1, b = i-1) for i in itr)
    @test collect_columns(tuple_itr) == Columns(@NT(a = Int[], b = Int[]))

    itr = (i for i in 0:-1)
    tuple_itr = (@NT(a = i+1, b = i-1) for i in itr)
    @test collect_columns(tuple_itr) == Columns(@NT(a = Int[], b = Int[]))
end

@testset "collecttuples" begin
    v = [(1, 2), (1, 3)]
    @test collect_columns(v) == Columns((Int[1, 1], Int[2, 3]))
    @inferred collect_columns(v)

    v = [(1, 2), (1.2, 3)]
    @test collect_columns(v) == Columns(([1, 1.2], Int[2, 3]))

    v = [(1, 2), (1.2, "3")]
    @test collect_columns(v) == Columns(([1, 1.2], Any[2, "3"]))
    @test typeof(collect_columns(v)) == typeof(Columns(([1, 1.2], Any[2, "3"])))

    v = [(1, 2), (1.2, 2), (1, "3")]
    @test collect_columns(v) == Columns(([1, 1.2, 1], Any[2, 2, "3"]))
    # length unknown
    itr = Iterators.filter(isodd, 1:8)
    tuple_itr = ((i+1, i-1) for i in itr)
    @test collect_columns(tuple_itr) == Columns(([2, 4, 6, 8], [0, 2, 4, 6]))
    tuple_itr_real = (i == 1 ? (1.2, i-1) : (i+1, i-1) for i in itr)
    @test collect_columns(tuple_itr_real) == Columns(([1.2, 4, 6, 8], [0, 2, 4, 6]))
    @test typeof(collect_columns(tuple_itr_real)) == typeof(Columns(([1.2, 4, 6, 8], [0, 2, 4, 6])))

    # empty
    itr = Iterators.filter(t -> t > 10, 1:8)
    tuple_itr = ((i+1, i-1) for i in itr)
    @test collect_columns(tuple_itr) == Columns(Int[], Int[])

    itr = (i for i in 0:-1)
    tuple_itr = ((i+1, i-1) for i in itr)
    @test collect_columns(tuple_itr) == Columns(Int[], Int[])
end

@testset "collectscalars" begin
    v = (i for i in 1:3)
    @test collect_columns(v) == [1,2,3]
    @inferred collect_columns(v)

    v = (i == 1 ? 1.2 : i for i in 1:3)
    @test collect_columns(v) == collect(v)

    itr = Iterators.filter(isodd, 1:100)
    @test collect_columns(itr) == collect(itr)
    real_itr = (i == 1 ? 1.5 : i for i in itr)
    @test collect_columns(real_itr) == collect(real_itr)
    @test eltype(collect_columns(real_itr)) == Float64

    #empty
    itr = Iterators.filter(t -> t > 10, 1:8)
    tuple_itr = (exp(i) for i in itr)
    @test collect_columns(tuple_itr) == Float64[]

    itr = (i for i in 0:-1)
    tuple_itr = (exp(i) for i in itr)
    @test collect_columns(tuple_itr) == Float64[]

    t = collect_columns(@NT(a = i) for i in (1, DataValue{Int}(), 3))
    @test columns(t, 1) isa DataValueArray
    @test isequal(columns(t, 1), DataValueArray([1, DataValue{Int}(), 3]))
end

@testset "collectpairs" begin
    v = (i=>i+1 for i in 1:3)
    @test collect_columns(v) == Columns([1,2,3]=>[2,3,4])
    @test eltype(collect_columns(v)) == Pair{Int, Int}

    v = (i == 1 ? (1.2 => i+1) : (i => i+1) for i in 1:3)
    @test collect_columns(v) == Columns([1.2,2,3]=>[2,3,4])
    @test eltype(collect_columns(v)) == Pair{Float64, Int}

    v = (@NT(a=i) => @NT(b="a$i") for i in 1:3)
    @test collect_columns(v) == Columns(Columns(@NT(a = [1,2,3]))=>Columns(@NT(b = ["a1","a2","a3"])))
    @test eltype(collect_columns(v)) == Pair{NamedTuples._NT_a{Int64}, NamedTuples._NT_b{String}}

    v = (i == 1 ? @NT(a="1") => @NT(b="a$i") : @NT(a=i) => @NT(b="a$i") for i in 1:3)
    @test collect_columns(v) == Columns(Columns(@NT(a = ["1",2,3]))=>Columns(@NT(b = ["a1","a2","a3"])))
    @test eltype(collect_columns(v)) == Pair{NamedTuples._NT_a{Any}, NamedTuples._NT_b{String}}

    # empty
    v = (@NT(a=i) => @NT(b="a$i") for i in 0:-1)
    @test collect_columns(v) == Columns(Columns(@NT(a = Int[]))=>Columns(@NT(b = String[])))
    @test eltype(collect_columns(v)) == Pair{NamedTuples._NT_a{Int}, NamedTuples._NT_b{String}}

    v = Iterators.filter(t -> t.first.a == 4, (@NT(a=i) => @NT(b="a$i") for i in 1:3))
    @test collect_columns(v) == Columns(Columns(@NT(a = Int[]))=>Columns(@NT(b = String[])))
    @test eltype(collect_columns(v)) == Pair{NamedTuples._NT_a{Int}, NamedTuples._NT_b{String}}

    t = table(@NT(b=1) => @NT(a = i) for i in (2, DataValue{Int}(), 3))
    @test t == table(@NT(b = [1,1,1], a = [2, DataValue{Int}(), 3]), pkey = :b)
end

@testset "issubtype" begin
    @test IndexedTables._is_subtype(Int, Int)
    @test IndexedTables._is_subtype(Int, DataValue{Int})
    @test !IndexedTables._is_subtype(DataValue{Int}, Int)
    @test IndexedTables._is_subtype(DataValue{Int}, DataValue{Int})
    @test !IndexedTables._is_subtype(DataValue{Int}, DataValue{String})
    @test !IndexedTables._is_subtype(Int, String)
end

@testset "collectflattened" begin
    t = [(:a => [1, 2]), (:b => [1, 3])]
    @test collect_columns_flattened(t) == Columns([:a, :a, :b, :b] => [1, 2, 1, 3])
    t = ([@NT(a = 1), @NT(a = 2)], [@NT(a = 1.1), @NT(a = 2.2)])
    @test collect_columns_flattened(t) == Columns(a = [1, 2, 1.1, 2.2])
    @test eltype(collect_columns_flattened(t)) == typeof(@NT(a=1.1))
    t = [(:a => table(1:2, ["a", "b"])), (:b => table(3:4, ["c", "d"]))]
    @test table(collect_columns_flattened(t)) == table([:a, :a, :b, :b], 1:4, ["a", "b", "c", "d"], pkey = 1)
end
