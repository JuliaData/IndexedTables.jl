


@testset "Tables Interface" begin 
    n = 1000
    x, y, z = 1:n, rand(Bool, n), randn(n)

    t = table((x=x, y=y, z=z), pkey=[:x, :y])
    nd = ndsparse((x=x, y=y), (z=z,))

    @test Tables.istable(t)
    @test Tables.istable(nd)
    @test Tables.istable(columns(t))
    @test Tables.istable(Columns(columns(t)))
    @test t == table(ndsparse(t))
    @test nd == ndsparse(table(nd))
    for (t_row, nd_row) in zip(rows(t), rows(nd))
        @test t_row == nd_row
    end
end