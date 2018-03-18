@testset "collectnamedtuples" begin
    v = [@NT(a = 1, b = 2), @NT(a = 1, b = 3)]
    @test collectcolumns(v) == Columns(@NT(a = Int[1, 1], b = Int[2, 3]))

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

    v = [(1, 2), (1.2, 3)]
    @test collectcolumns(v) == Columns((Real[1, 1.2], Int[2, 3]))

    v = [(1, 2), (1.2, "3")]
    @test collectcolumns(v) == Columns((Real[1, 1.2], Any[2, "3"]))

    v = [(1, 2), (1.2, 2), (1, "3")]
    @test collectcolumns(v) == Columns((Real[1, 1.2, 1], Any[2, 2, "3"]))
end
