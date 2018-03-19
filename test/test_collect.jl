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
end
