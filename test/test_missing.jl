@testset "Missing" begin 
    @testset "Table equality with missing" begin 
        @test ismissing(table([1, 2, missing]) == table([1, 2, missing]))
        @test isequal(table([1,2,missing]), table([1,2,missing]))
        @test ismissing(ndsparse([1], [missing]) == ndsparse([1], [missing]))
        @test isequal(ndsparse([1], [missing]), ndsparse([1], [missing]))
        @test !isequal(ndsparse([2], [missing]), ndsparse([1], [missing]))
    end
    @testset "stack/unstack" begin
        t = table(1:4, [1, missing, 9, 16], [1, 8, 27, missing], names = [:x, :x2, :x3], pkey = :x)
        @test isequal(t, unstack(stack(t)))
    end
end

@testset "dropmissing" begin 
    a = table([[rand(Bool) ? missing : rand() for i in 1:30] for i in 1:3]...)
    a2 = dropmissing(a)
    @test all(!ismissing, a2)
    @test all(x -> eltype(x) == Float64, columns(a2))

    b = table([DataValueArray(rand(30), rand(Bool, 30)) for i in 1:3]...)
    b2 = dropmissing(b, missingtype=DataValue)
    @test all(!isna, b2)
    @test all(x -> eltype(x) == Float64, columns(b2))
end