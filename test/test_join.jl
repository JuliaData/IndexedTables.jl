@testset "Test Joins" begin 
    y = rand(10)
    z = rand(10)

    t  = table((x=1:10,   y=y), pkey=:x)
    t2 = table((x=1:2:20, z=z), pkey=:x)

    @testset "how = :inner" begin
        t_inner = table((x = 1:2:9, y = y[1:2:9], z = z[1:5]), pkey = :x)
        @test isequal(join(t, t2; how=:inner), t_inner)
    end
    @testset "how = :left" begin
        # Missing
        z_left = Union{Float64,Missing}[missing for i in 1:10]
        z_left[1:2:9] = z[1:5]
        t_left = table((x = 1:10, y = y, z = z_left))
        @test isequal(join(t, t2; how=:left), t_left)

        # DataValue
        z_left2 = [DataValue{Float64}() for i in 1:10]
        z_left2[1:2:9] = z[1:5]
        t_left2 = table((x=1:10, y = y, z = z_left2))
        @test isequal(join(t, t2, how=:left, missingtype=DataValue), t_left2)
    end
    @testset "how = :outer" begin 
        # Missing
        x_outer = union(1:10, 1:2:20)
        y_outer = vcat(y, fill(missing, 5))
        z_left = Union{Float64,Missing}[missing for i in 1:10]
        z_left[1:2:9] = z[1:5]
        z_outer = vcat(z_left, z[6:10])
        t_outer = table((x=x_outer, y=y_outer, z=z_outer); pkey=:x)
        @test isequal(join(t, t2; how=:outer), t_outer)

        # DataValue 
        y_outer2 = vcat(y, fill(DataValue{Float64}(), 5))
        z_left2 = [DataValue{Float64}() for i in 1:10]
        z_left2[1:2:9] = z[1:5]
        z_outer2 = vcat(z_left2, z[6:10])
        t_outer2 = table((x=x_outer, y=y_outer2, z=z_outer2); pkey=:x)
        @test isequal(join(t, t2; how=:outer, missingtype=DataValue), t_outer2)
    end
    @testset "how = :anti" begin 
        t_anti = table((x=2:2:10, y=y[2:2:10]), pkey=:x)
        @test isequal(join(t, t2; how=:anti), t_anti)
    end
end