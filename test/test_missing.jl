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