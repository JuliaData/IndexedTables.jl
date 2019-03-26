using IndexedTables, SparseArrays, BenchmarkTools, Random

N = 10_000

Random.seed!(666)
s = table((a = rand(1:3, N), b = rand(1:3, N), c1 = rand(N), d1 = rand(N)), pkey = (:a, :b))
t = table((a = rand(1:3, N), b = rand(1:3, N), c2 = rand(N), d2 = rand(N)), pkey = (:a, :b))

join(s, t)
join(merge, s, t)
groupjoin(s, t)
@time join(s, t)
@time join(merge, s, t)
@time groupjoin(s, t)

Random.seed!(666)
idx = Columns(p=rand(1:100, N), q=rand(1:100, N))
t = NDSparse(idx, rand(N))
t2 = NDSparse(Columns(q=rand(1:100, N)), rand(N))
@btime broadcast(+, $t, $t2)

using SparseArrays
Random.seed!(666)
S = sprand(1000, 1000,.1)
v = rand(1000)
nd = convert(NDSparse, S)
ndv = convert(NDSparse,v)
@btime broadcast(*, $nd, $ndv)
