@testset "Missing" begin 
    @testset "Table equality with missing" begin 
        @test table([1, 2, missing]) == table([1, 2, missing])
    end
    @testset "stack/unstack" begin
        t = table(1:4, [1, missing, 9, 16], [1, 8, 27, missing], names = [:x, :x2, :x3], pkey = :x)
        @test t == unstack(stack(t))
    end
end