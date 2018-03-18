@testset "collectnamedtuples" begin
    v = [@NT(a = 1, b = 2), @NT(a = 1, b = 3)]
    @test collectcolumns(v) == Columns(@NT(a = Int[1, 1], b = Int[2, 3]))

    # test inferrability with constant eltype
    itr = [@NT(a = 1, b = 2), @NT(a = 1, b = 2), @NT(a = 1, b = 12)]
    st = start(itr)
    el, st = next(itr, st)
    dest = similar(IndexedTables.arrayof(typeof(el)), 3)
    dest[1] = el
    @inferred IndexedTables.collect_to_columns!(dest, itr, 2, st)

    v = [@NT(a = 1, b = 2), @NT(a = 1.2, b = 3)]
    @test collectcolumns(v) == Columns(@NT(a = Real[1, 1.2], b = Int[2, 3]))

    v = [@NT(a = 1, b = 2), @NT(a = 1.2, b = "3")]
    @test collectcolumns(v) == Columns(@NT(a = Real[1, 1.2], b = Any[2, "3"]))

    v = [@NT(a = 1, b = 2), @NT(a = 1.2, b = 2), @NT(a = 1, b = "3")]
    @test collectcolumns(v) == Columns(@NT(a = Real[1, 1.2, 1], b = Any[2, 2, "3"]))
end

@testset "collecttuples" begin
    v = [(1, 2), (1, 3)]
    @test collectcolumns(v) == Columns((Int[1, 1], Int[2, 3]))
    @inferred collectcolumns(v)

    v = [(1, 2), (1.2, 3)]
    @test collectcolumns(v) == Columns((Real[1, 1.2], Int[2, 3]))

    v = [(1, 2), (1.2, "3")]
    @test collectcolumns(v) == Columns((Real[1, 1.2], Any[2, "3"]))

    v = [(1, 2), (1.2, 2), (1, "3")]
    @test collectcolumns(v) == Columns((Real[1, 1.2, 1], Any[2, 2, "3"]))
end
