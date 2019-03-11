


@testset "Tables Interface" begin
    n = 1000
    x, y, z = 1:n, rand(Bool, n), randn(n)

    t = table((x=x, y=y, z=z), pkey=[:x, :y])

    @test Tables.istable(t)
    @test t == table(Tables.rowtable((x=x,y=y,z=z)))
    @test Tables.istable(columns(t))
    @test Tables.istable(Columns(columns(t)))
    @test Tables.rowaccess(typeof(t))
    @test Tables.columnaccess(typeof(t))
    @test Tables.schema(t) == Tables.Schema((:x, :y, :z), (Int, Bool, Float64))
end
