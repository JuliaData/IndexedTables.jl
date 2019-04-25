@testset "collectnamedtuples" begin
    v = [(a = 1, b = 2), (a = 1, b = 3)]
    @test collect_columns(v) == Columns((a = Int[1, 1], b = Int[2, 3]))

    # test inferrability with constant eltype
    itr = [(a = 1, b = 2), (a = 1, b = 2), (a = 1, b = 12)]
    el, st = iterate(itr)
    dest = similar(IndexedTables.arrayof(typeof(el)), 3)
    dest[1] = el
    @inferred IndexedTables.collect_to_columns!(dest, itr, 2, st)

    v = [(a = 1, b = 2), (a = 1.2, b = 3)]
    @test collect_columns(v) == Columns((a = Real[1, 1.2], b = Int[2, 3]))
    @test typeof(collect_columns(v)) == typeof(Columns((a = Real[1, 1.2], b = Int[2, 3])))

    v = [(a = 1, b = 2), (a = 1.2, b = "3")]
    @test collect_columns(v) == Columns((a = Real[1, 1.2], b = Any[2, "3"]))
    @test typeof(collect_columns(v)) == typeof(Columns((a = Real[1, 1.2], b = Any[2, "3"])))

    v = [(a = 1, b = 2), (a = 1.2, b = 2), (a = 1, b = "3")]
    @test collect_columns(v) == Columns((a = Real[1, 1.2, 1], b = Any[2, 2, "3"]))
    @test typeof(collect_columns(v)) == typeof(Columns((a = Real[1, 1.2, 1], b = Any[2, 2, "3"])))

    # length unknown
    itr = Iterators.filter(isodd, 1:8)
    tuple_itr = ((a = i+1, b = i-1) for i in itr)
    @test collect_columns(tuple_itr) == Columns((a = [2, 4, 6, 8], b = [0, 2, 4, 6]))
    tuple_itr_real = (i == 1 ? (a = 1.2, b =i-1) : (a = i+1, b = i-1) for i in itr)
    @test collect_columns(tuple_itr_real) == Columns((a = Real[1.2, 4, 6, 8], b = [0, 2, 4, 6]))

    # empty
    itr = Iterators.filter(t -> t > 10, 1:8)
    tuple_itr = ((a = i+1, b = i-1) for i in itr)
    @test collect_columns(tuple_itr) == Columns((a = Int[], b = Int[]))

    itr = (i for i in 0:-1)
    tuple_itr = ((a = i+1, b = i-1) for i in itr)
    @test collect_columns(tuple_itr) == Columns((a = Int[], b = Int[]))
end

@testset "collecttuples" begin
    v = [(1, 2), (1, 3)]
    @test collect_columns(v) == Columns((Int[1, 1], Int[2, 3]))
    @inferred collect_columns(v)

    v = [(1, 2), (1.2, 3)]
    @test collect_columns(v) == Columns((Real[1, 1.2], Int[2, 3]))

    v = [(1, 2), (1.2, "3")]
    @test collect_columns(v) == Columns((Real[1, 1.2], Any[2, "3"]))
    @test typeof(collect_columns(v)) == typeof(Columns((Real[1, 1.2], Any[2, "3"])))

    v = [(1, 2), (1.2, 2), (1, "3")]
    @test collect_columns(v) == Columns((Real[1, 1.2, 1], Any[2, 2, "3"]))
    # length unknown
    itr = Iterators.filter(isodd, 1:8)
    tuple_itr = ((i+1, i-1) for i in itr)
    @test collect_columns(tuple_itr) == Columns(([2, 4, 6, 8], [0, 2, 4, 6]))
    tuple_itr_real = (i == 1 ? (1.2, i-1) : (i+1, i-1) for i in itr)
    @test collect_columns(tuple_itr_real) == Columns((Real[1.2, 4, 6, 8], [0, 2, 4, 6]))
    @test typeof(collect_columns(tuple_itr_real)) == typeof(Columns((Real[1.2, 4, 6, 8], [0, 2, 4, 6])))

    # empty
    itr = Iterators.filter(t -> t > 10, 1:8)
    tuple_itr = ((i+1, i-1) for i in itr)
    @test collect_columns(tuple_itr) == Columns((Int[], Int[]))

    itr = (i for i in 0:-1)
    tuple_itr = ((i+1, i-1) for i in itr)
    @test collect_columns(tuple_itr) == Columns((Int[], Int[]))
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
    @test eltype(collect_columns(real_itr)) == Real

    #empty
    itr = Iterators.filter(t -> t > 10, 1:8)
    tuple_itr = (exp(i) for i in itr)
    @test collect_columns(tuple_itr) == Float64[]

    itr = (i for i in 0:-1)
    tuple_itr = (exp(i) for i in itr)
    @test collect_columns(tuple_itr) == Float64[]

    t = collect_columns((a = i,) for i in (1, missing, 3))
    @test columns(t, 1) isa Vector{Union{Missing, Int}}
    @test isequal(columns(t, 1), [1, missing, 3])
end

@testset "collectpairs" begin
    v = (i=>i+1 for i in 1:3)
    @test collect_columns(v) == columnspair([1,2,3], [2,3,4])
    @test eltype(collect_columns(v)) == Pair{Int, Int}

    v = (i == 1 ? (1.2 => i+1) : (i => i+1) for i in 1:3)
    @test collect_columns(v) == columnspair(Real[1.2,2,3], [2,3,4])
    @test eltype(collect_columns(v)) == Pair{Real, Int}

    v = ((a=i,) => (b="a$i",) for i in 1:3)
    @test collect_columns(v) == columnspair(Columns((a = [1,2,3],)), Columns((b = ["a1","a2","a3"],)))
    @test eltype(collect_columns(v)) == Pair{NamedTuple{(:a,), Tuple{Int}}, NamedTuple{(:b,), Tuple{String}}}

    v = (i == 1 ? (a="1",) => (b="a$i",) : (a=i,) => (b="a$i",) for i in 1:3)
    @test collect_columns(v) == columnspair(Columns((a = ["1",2,3],)), Columns((b = ["a1","a2","a3"],)))
    @test eltype(collect_columns(v)) == Pair{NamedTuple{(:a,), Tuple{Any}}, NamedTuple{(:b,), Tuple{String}}}

    # empty
    v = ((a=i,) => (b="a$i",) for i in 0:-1)
    @test collect_columns(v) == columnspair(Columns((a = Int[],)), Columns((b = String[],)))
    @test eltype(collect_columns(v)) == Pair{NamedTuple{(:a,), Tuple{Int}}, NamedTuple{(:b,), Tuple{String}}}

    v = Iterators.filter(t -> t.first.a == 4, ((a=i,) => (b="a$i",) for i in 1:3))
    @test collect_columns(v) == columnspair(Columns((a = Int[],)), Columns((b = String[],)))
    @test eltype(collect_columns(v)) == Pair{NamedTuple{(:a,), Tuple{Int}}, NamedTuple{(:b,), Tuple{String}}}

    t = table(collect_columns((b = 1,) => (a = i,) for i in (2, missing, 3)))
    @test isequal(t, table((b = [1,1,1], a = [2, missing, 3]), pkey = :b))
end

@testset "collectflattened" begin
    t = [(:a => [1, 2]), (:b => [1, 3])]
    @test collect_columns_flattened(t) == columnspair([:a, :a, :b, :b], [1, 2, 1, 3])
    t = ([(a = 1,), (a = 2,)], [(a = 1.1,), (a = 2.2,)])
    @test collect_columns_flattened(t) == Columns(a = Real[1, 2, 1.1, 2.2])
    @test eltype(collect_columns_flattened(t)) == NamedTuple{(:a,), Tuple{Real}}
    t = [(:a => table(1:2, ["a", "b"])), (:b => table(3:4, ["c", "d"]))]
    @test table(collect_columns_flattened(t)) == table([:a, :a, :b, :b], 1:4, ["a", "b", "c", "d"], pkey = 1)
end
