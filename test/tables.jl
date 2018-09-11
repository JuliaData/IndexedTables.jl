using Test, Tables, IndexedTables

@testset "Tables.jl" begin

t = table([1,2,3],[1.,2.,3.],["A","B","C"], names=[:a,:b,:c])
ct = t |> columntable
@test ct == columns(t)
rt = t |> rowtable
@test rt == rows(t)
@test table(t |> columntable) == t
@test table(t |> rowtable) == t

end # testset