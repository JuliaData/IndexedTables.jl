using Test
using Random
using IndexedTables
using PooledArrays
using SparseArrays
using WeakRefStrings
import IndexedTables: update!, pkeynames, pkeys, excludecols, sortpermby, primaryperm, best_perm_estimate, hascolumns

    c = Columns([1,1,1,2,2], [1,2,4,3,5])
    d = Columns([1,1,2,2,2], [1,3,1,4,5])
    e = Columns([1,1,1], sort([rand(),0.5,rand()]))
    f = Columns([1,1,1], sort([rand(),0.5,rand()]))
    @test map(+,NDSparse(c,ones(5)),NDSparse(d,ones(5))).index == Columns([1,2],[1,5])
    @test length(map(+,NDSparse(e,ones(3)),NDSparse(f,ones(3)))) == 1
    @test eltype(c) == Tuple{Int,Int}
    @test map_rows(i -> (exp = exp(i), log = log(i)), 1:5) == Columns((exp = exp.(1:5), log = log.(1:5)))
    @test map_rows(tuple, 1:3, ["a","b","c"]) == Columns([1,2,3], ["a","b","c"])

 c = Columns(Columns((a=[1,2,3],)) => Columns((b=["a","b","c"],)))
    @test c.columns.first == Columns((a=[1,2,3],))
    @test c.columns.second == Columns((b=["a","b","c"],))
    @test colnames(c) == ((:a,) => (:b,))
    @test length(c) == 3
    @test ncols(c) == (1 => 1)
    @test eltype(c) == typeof((a=1,)=>(b="a",))
    @test c[1] == ((a=1,) => (b="a",))
    @test c[1:2] ==  Columns(Columns((a=[1,2],)) => Columns((b=["a","b"],)))
    @test view(c, 1:2) == Columns(Columns((a=view([1,2,3],1:2),))=>Columns((b=view(["a","b","c"],1:2),)))
    d = deepcopy(c)
    d[1] = (a=2,) => (b="aa",)
    @test d[1] == ((a=2,) => (b="aa",))
    d = deepcopy(c)
    push!(d, (a=4,) => (b="d",))
    @test d == Columns(Columns((a=[1,2,3,4],)) => Columns((b=["a","b","c","d"],)))
    e = vcat(d, d)
    append!(d, d)
    @test d == Columns(Columns((a=[1,2,3,4,1,2,3,4],)) => Columns((b=["a","b","c","d","a","b","c","d"],)))
    @test d == e
    empty!(d)
    @test d == c[Int64[]]
    @test c != Columns((a=[1,2,3], b=["a","b","c"]))
    x = Columns([1], [1.0], WeakRefStrings.StringArray(["a"]))
    @test IndexedTables.arrayof(eltype(x)) == typeof(x)
    @test IndexedTables.arrayof(WeakRefString{UInt8}) == WeakRefStrings.StringArray{WeakRefString{UInt8},1}
    @test typeof(similar(c, 10)) == typeof(similar(typeof(c), 10)) == typeof(c)
    @test length(similar(c, 10)) == 10
    @test issorted(c)
    @test sortperm(c) == [1,2,3]
    permute!(c, [2,3, 1])
    @test c == Columns(Columns((a=[2,3,1],)) => Columns((b=["b","c","a"],)))
    f = Columns(Columns([1, 1, 2, 2]) => ["b", "a", "c", "d"])
    @test IndexedTables._strip_pair(f) == Columns([1, 1, 2, 2], ["b", "a", "c", "d"])
    @test sortperm(f) == [2, 1, 3, 4]
    @test sort(f) == Columns(Columns([1, 1, 2, 2]) => ["a", "b", "c", "d"])
    @test !issorted(f)
#end

Random.seed!(123)
A = NDSparse(rand(1:3,10), rand('A':'F',10), map(UInt8,rand(1:3,10)), collect(1:10), randn(10))
B = NDSparse(map(UInt8,rand(1:3,10)), rand('A':'F',10), rand(1:3,10), randn(10))
C = NDSparse(map(UInt8,rand(1:3,10)), rand(1:3,10), rand(1:3,10), randn(10))

let a = NDSparse([12,21,32], [52,41,34], [11,53,150]), b = NDSparse([12,23,32], [52,43,34], [56,13,10])
    @test eltype(a) == Int
    @test sum(a) == 214

    c = similar(a)
    @test typeof(c) == typeof(a)
    @test length(c.index) == 0

    c = copy(a)
    @test typeof(c) == typeof(a)
    @test length(c.index) == length(a.index)
    empty!(c)
    @test length(c.index) == 0

    c = convertdim(convertdim(a, 1, Dict(12=>10, 21=>20, 32=>20)), 2, Dict(52=>50, 34=>20, 41=>20), -)
    @test c[20,20] == 97

    c = map(+, a, b)
    @test length(c.index) == 2
    @test sum(map(-, c, c)) == 0

    @test map(iseven, a) == NDSparse([12,21,32], [52,41,34], [false,false,true])
end


    idx = Columns(p=[1,2], q=[3,4])
    t = NDSparse(idx, Columns(a=[5,6],b=[7,8]))
    t1 = NDSparse(Columns(p=[1,2,3]), Columns(c=[4,5,6]))
    t2 = NDSparse(Columns(q=[2,3]), Columns(c=[4,5]))

    # scalar output
    @test broadcast(==, t, t) == NDSparse(idx, Bool[1,1])
    @test broadcast((x,y)->x.a+y.c, t, t1) == NDSparse(idx, [9,11])
    @test broadcast((x,y)->y.a+x.c, t1, t) == NDSparse(idx, [9,11])
    @test broadcast((x,y)->x.a+y.c, t, t2) == NDSparse(idx[1:1], [10])

    # Tuple output
    b1 = broadcast((x,y)->(x.a, y.c), t, t1)
    @test isa(b1.data, Columns)
    @test b1 == NDSparse(idx, Columns([5,6], [4,5]))

    b2 = broadcast((x,y)->(m=x.a, n=y.c), t, t1)
    @test b2 == NDSparse(idx, Columns(m=[5,6], n=[4,5]))
    @test isa(b2.data, Columns)
    @test fieldnames(eltype(b2.data)) == (:m, :n)

    S = sprand(10,10,.1)
    v = rand(10)
    nd = convert(NDSparse, S)
    ndv = convert(NDSparse,v)
    @test broadcast(*, nd, ndv) == convert(NDSparse, S .* v)
    # test matching dimensions by name
    ndt0 = convert(NDSparse, sparse(S .* (v')))
    ndt = NDSparse(Columns(a=ndt0.index.columns[1], b=ndt0.index.columns[2]), ndt0.data, presorted=true)
    @test broadcast(*,
                    NDSparse(Columns(a=nd.index.columns[1], b=nd.index.columns[2]), nd.data),
                    NDSparse(Columns(b=ndv.index.columns[1]), ndv.data)) == ndt

let a = rand(10), b = rand(10), c = rand(10)
    @test NDSparse(a, b, c) == NDSparse(a, b, c)
    c2 = copy(c)
    c2[1] += 1
    @test NDSparse(a, b, c) != NDSparse(a, b, c2)
    b2 = copy(b)
    b2[1] += 1
    @test NDSparse(a, b, c) != NDSparse(a, b2, c)
end

let a = rand(10), b = rand(10), c = rand(10), d = rand(10)
    local nd = NDSparse(a,b,c,d)
    @test permutedims(nd,[3,1,2]) == NDSparse(c,a,b,d)
    @test_throws ArgumentError permutedims(nd, [1,2])
    @test_throws ArgumentError permutedims(nd, [1,3])
    @test_throws ArgumentError permutedims(nd, [1,2,2])
end

let r=1:5, s=1:2:5
    A = NDSparse([r;], [r;], [r;])
    @test A[s, :] == NDSparse([s;], [s;], [s;])
    @test_throws ErrorException A[s, :, :]
end

 a = NDSparse([1,2,2,2], [1,2,3,4], [10,9,8,7])
    @test a[1,1] == 10
    @test a[2,3] == 8
    #@test_throws ErrorException a[2]
    @test a[2,:] == NDSparse([2,3,4], [9,8,7])
    @test a[:,1] == NDSparse([1], [10])
    @test collect(where(a, 2, :)) == [9,8,7]
    @test collect(Base.pairs(a)) == [(1,1)=>10, (2,2)=>9, (2,3)=>8, (2,4)=>7]
    @test first(Base.pairs(a[:, 3])) == ((2,)=>8)

    update!(x->x+10, a, 2, :)
    @test a == NDSparse([1,2,2,2], [1,2,3,4], [10,19,18,17])

    a[2,2:3] = 77
    @test a == NDSparse([1,2,2,2], [1,2,3,4], [10,77,77,17])

let a = NDSparse([1,2,2,2], [1,2,3,4], zeros(4))
    a2 = copy(a); a3 = copy(a)
    #a[2,:] = 1
    #@test a == NDSparse([1,2,2,2], [1,2,3,4], Float64[0,1,1,1])
    a2[2,[2,3]] = 1
    @test a2 == NDSparse([1,2,2,2], [1,2,3,4], Float64[0,1,1,0])
    a3[2,[2,3]] = [8,9]
    @test a3 == NDSparse([1,2,2,2], [1,2,3,4], Float64[0,8,9,0])
end

# issue #15
let a = NDSparse([1,2,3,4], [1,2,3,4], [1,2,3,4])
    a[5,5] = 5
    a[5,5] = 6
    @test a[5,5] == 6
end

let a = NDSparse([1,2,2,3,4,5], [1,2,2,3,4,5], [1,2,20,3,4,5], agg=+)
    @test a == NDSparse([1,2,3,4,5], [1,2,3,4,5], [1,22,3,4,5])
end

let a = rand(5,5,5)
    for dims in ([2,3], [1], [2])
        r = squeeze(reducedim(+, a, dims), dims=(dims...,))
        asnd = convert(NDSparse,a)
        b = reducedim(+, asnd, dims)
        bv = reducedim_vec(sum, asnd, dims)
        c = convert(NDSparse, r)
        @test b.index == c.index == bv.index
        @test b.data ≈ c.data
        @test bv.data ≈ c.data
    end
    @test_throws ArgumentError reducedim(+, convert(NDSparse,a), [1,2,3])
end

for a in (rand(2,2), rand(3,5))
    nd = convert(NDSparse, a)
    @test nd == convert(NDSparse, sparse(a))
    for (I,d) in zip(nd.index, nd.data)
        @test a[I...] == d
    end
end

_colnames(x::NDSparse) = keys(x.index.columns)

@test _colnames(NDSparse(ones(2),ones(2),ones(2),names=[:a,:b])) == (:a, :b)
@test _colnames(NDSparse(Columns(x=ones(2),y=ones(2)), ones(2))) == (:x, :y)

x = NDSparse(Columns(x = [1,2,3], y = [4,5,6], z = [7,8,9]), [10,11,12])
    names = (:x, :y, :z)
    @test _colnames(x) == names
    @test _colnames(filter(a->a==11, x)) == names
    @test _colnames(selectkeys(x, (:z, :x))) == (:z, :x)
    @test _colnames(selectkeys(x, (:y,))) == (:y,)
    @test _colnames(filter((:x=>a->a>1, :z=>a->a>7), x, )) == names
    @test _colnames(x[1:2, 4:5, 8:9]) == names
    @test convertdim(x, :y, a->0) == NDSparse(Columns(x=[1,2,3], y=[0,0,0], z=[7,8,9]), [10,11,12])
    @test convertdim(x, :y, a->0, name=:yy) == NDSparse(Columns(x=[1,2,3], yy=[0,0,0], z=[7,8,9]), [10,11,12])

# test showing

@test repr(ndsparse(Columns([1]), Columns(()))) == """
1-d NDSparse with 1 values (0-tuples):
1 │
──┼
1 │ """

@test repr(table()) == """
Table with 0 rows, 0 columns:

"""

@test repr(NDSparse([1,2,3],[3,2,1],Float64[4,5,6])) == """
2-d NDSparse with 3 values (Float64):
1  2 │
─────┼────
1  3 │ 4.0
2  2 │ 5.0
3  1 │ 6.0"""

@test repr(NDSparse(Columns(a=[1,2,3],test=[3,2,1]),Float64[4,5,6])) == """
2-d NDSparse with 3 values (Float64):
a  test │
────────┼────
1  3    │ 4.0
2  2    │ 5.0
3  1    │ 6.0"""

@test repr(NDSparse(Columns(a=[1,2,3],test=[3,2,1]),Columns(x=Float64[4,5,6],y=[9,8,7]))) == """
2-d NDSparse with 3 values (2 field named tuples):
a  test │ x    y
────────┼───────
1  3    │ 4.0  9
2  2    │ 5.0  8
3  1    │ 6.0  7"""

@test repr(NDSparse([1,2,3],[3,2,1],Columns(x=Float64[4,5,6],y=[9,8,7]))) == """
2-d NDSparse with 3 values (2 field named tuples):
1  2 │ x    y
─────┼───────
1  3 │ 4.0  9
2  2 │ 5.0  8
3  1 │ 6.0  7"""

@test repr(NDSparse([1:19;],ones(Int,19))) == """
1-d NDSparse with 19 values (Int64):
1  │
───┼──
1  │ 1
2  │ 1
3  │ 1
4  │ 1
5  │ 1
6  │ 1
7  │ 1
8  │ 1
9  │ 1
   ⋮
12 │ 1
13 │ 1
14 │ 1
15 │ 1
16 │ 1
17 │ 1
18 │ 1
19 │ 1"""

function foo(n, data=ones(Int, 1))
    t=IndexedTables.namedtuple((Symbol("x$i") for i=1:n)...)
    NDSparse(Columns(t([ones(Int, 1) for i=1:n]...)), data)
end

#@test repr(foo(18)) == "18-d NDSparse with 1 values (Int64):\n    \e[4mDimensions\n\e[24m\e[1m#   \e[22m\e[1mcolname  \e[22m\e[1mtype\e[22m\n──────────────────\n1   x1       Int64\n2   x2       Int64\n3   x3       Int64\n4   x4       Int64\n5   x5       Int64\n6   x6       Int64\n7   x7       Int64\n8   x8       Int64\n9   x9       Int64\n10  x10      Int64\n11  x11      Int64\n12  x12      Int64\n13  x13      Int64\n14  x14      Int64\n15  x15      Int64\n16  x16      Int64\n17  x17      Int64\n18  x18      Int64\n    \e[4mValues\n\e[24mInt64"

#@test repr(foo(17, Columns(x=ones(Int, 1), y=ones(Int, 1)))) == "17-d NDSparse with 1 values (2 field named tuples):\n    \e[4mDimensions\n\e[24m\e[1m#   \e[22m\e[1mcolname  \e[22m\e[1mtype\e[22m\n──────────────────\n1   x1       Int64\n2   x2       Int64\n3   x3       Int64\n4   x4       Int64\n5   x5       Int64\n6   x6       Int64\n7   x7       Int64\n8   x8       Int64\n9   x9       Int64\n10  x10      Int64\n11  x11      Int64\n12  x12      Int64\n13  x13      Int64\n14  x14      Int64\n15  x15      Int64\n16  x16      Int64\n17  x17      Int64\n    \e[4mValues\n\e[24m\e[1m#   \e[22m\e[1mcolname  \e[22m\e[1mtype\e[22m\n──────────────────\n18  x        Int64\n19  y        Int64"
let x = Columns([6,5,4,3,2,2,1],[4,4,4,4,4,4,4],[1,2,3,4,5,6,7])
    @test issorted(x[sortperm(x)])
end

let x = NDSparse([1,2],[3,4],[:a,:b],[3,5])
    @test x[1,:,:a] == NDSparse([3],[3])
end

# issue #42
using Base.Dates
let hitemps = NDSparse([fill("New York",3); fill("Boston",3)],
                           repmat(Date(2016,7,6):Date(2016,7,8), 2),
                           [91,89,91,95,83,76])
    @test hitemps[:, Date(2016,7,8)] == NDSparse(["New York", "Boston"],
                                                     [91,76])
end

    cs = Columns([1], [2])
    t = table(cs)
    @test t.pkey == Int[]
    @test t.columns == [(1,2)]
    @test column(t.columns,1) !== cs.columns[1]
    t = table(cs, copy=false)
    @test column(t.columns,1) === cs.columns[1]
    t = table(cs, copy=false, pkey=[1])
    @test column(t.columns,1) === cs.columns[1]
    cs = Columns([2, 1], [3,4])
    t = table(cs, copy=false, pkey=[1])
    @test t.pkey == Int[1]
    cs = Columns([2, 1], [3,4])
    t = table(cs, copy=false, pkey=[1])
    @test column(t.columns,1) === cs.columns[1]
    @test t.pkey == Int[1]
    @test t.columns == [(1,4), (2,3)]

    cs = Columns(x=[2, 1], y=[3,4])
    t = table(cs, copy=false, pkey=:x)
    @test column(t.columns,1) === cs.columns.x
    @test t.pkey == Int[1]
    @test t.columns == [(x=1,y=4), (x=2,y=3)]

    cs = Columns([2, 1], [3,4])
    t = table(cs, presorted=true, pkey=[1])
    @test t.pkey == Int[1]
    @test t.columns == [(2,3), (1,4)]

    a = table([1, 2, 3], [4, 5, 6])
    b = table([1, 2, 3], [4, 5, 6], names=[:x, :y])
    @test table(([1, 2, 3], [4, 5, 6])) == a
    @test table((x = [1, 2, 3], y = [4, 5, 6])) == b
    @test table(Columns([1, 2, 3], [4, 5, 6])) == a
    @test table(Columns(x=[1, 2, 3], y=[4, 5, 6])) == b
    @test b == table(b)
    b = table([2, 3, 1], [4, 5, 6], names=[:x, :y], pkey=:x)
    b = table([2, 1, 2, 1], [2, 3, 1, 3], [4, 5, 6, 7], names=[:x, :y, :z], pkey=(:x, :y))
    t = table([1, 2], [3, 4])
    @test pkeynames(t) == ()
    t = table([1, 2], [3, 4], pkey=1)
    @test pkeynames(t) == (1,)
    t = table([2, 1], [1, 3], [4, 5], names=[:x, :y, :z], pkey=(1, 2))
    @test pkeys(t) == Columns((x = [1, 2], y = [3, 1]))
    @test pkeys(a) == Columns((Base.OneTo(3),))
    a = table(["a", "b"], [3, 4], pkey=1)
    @test pkeys(a) == Columns((["a", "b"],))
    t = table([2, 1], [1, 3], [4, 5], names=[:x, :y, :z], pkey=(1, 2))
    @test excludecols(t, (:x,)) == (2, 3)
    @test excludecols(t, Not(2, 3)) == (2, 3)
    @test excludecols(t, (2,)) == (1, 3)
    @test excludecols(t, pkeynames(t)) == (3,)
    @test excludecols([1, 2, 3], (1,)) == ()
    @test convert(NextTable, Columns(x=[1, 2], y=[3, 4]), Columns(z=[1, 2]), presorted=true) == table([1, 2], [3, 4], [1, 2], names=Symbol[:x, :y, :z])
    @test colnames([1, 2, 3]) == (1,)
    @test colnames(Columns([1, 2, 3], [3, 4, 5])) == (1, 2)
    @test colnames(table([1, 2, 3], [3, 4, 5])) == (1, 2)
    @test colnames(Columns(x=[1, 2, 3], y=[3, 4, 5])) == (:x, :y)
    @test colnames(table([1, 2, 3], [3, 4, 5], names=[:x, :y])) == (:x, :y)
    @test colnames(ndsparse(Columns(x=[1, 2, 3]), Columns(y=[3, 4, 5]))) == (:x, :y)
    @test colnames(ndsparse(Columns(x=[1, 2, 3]), [3, 4, 5])) == (:x, 2)
    @test colnames(ndsparse(Columns(x=[1, 2, 3]), [3, 4, 5])) == (:x, 2)
    @test colnames(ndsparse(Columns([1, 2, 3], [4, 5, 6]), Columns(x=[6, 7, 8]))) == (1, 2, :x)
    @test colnames(ndsparse(Columns(x=[1, 2, 3]), Columns([3, 4, 5], [6, 7, 8]))) == (:x, 2, 3)

    x = ndsparse(["a", "b"], [3, 4])
    @test (keytype(x), eltype(x)) == (Tuple{String}, Int64)
    x = ndsparse((date = Date.(2014:2017),), [4:7;])
    @test x[Date("2015-01-01")] == 5
    @test (keytype(x), eltype(x)) == (Tuple{Date}, Int64)
    x = ndsparse((["a", "b"], [3, 4]), [5, 6])
    @test (keytype(x), eltype(x)) == (Tuple{String,Int64}, Int64)
    @test x["a", 3] == 5
    x = ndsparse((["a", "b"], [3, 4]), ([5, 6], [7.0, 8.0]))
    x = ndsparse((x = ["a", "a", "b"], y = [3, 4, 4]), (p = [5, 6, 7], q = [8.0, 9.0, 10.0]))
    @test (keytype(x), eltype(x)) == (Tuple{String,Int64}, NamedTuple{(:p,:q), Tuple{Int64,Float64}})
    @test x["a", :] == ndsparse((y = [3, 4],), Columns((p = [5, 6], q = [8.0, 9.0])))

    x = ndsparse([1, 2], [3, 4])
    @test pkeynames(x) == (1,)

    a = Columns([1,2,1],["foo","bar","baz"])
    b = Columns([2,1,1],["bar","baz","foo"])
    c = Columns([1,1,2],["foo","baz","bar"])
    @test a != b
    @test a != c
    @test b != c
    sort!(a)
    @test sort(b) == a
    sort!(b); sort!(c)
    @test a == b == c
    @test size(a) == size(b) == size(c) == (3,)
    @test eltype(a) == Tuple{Int,String}
    @test length(similar(a)) == 3
    aa = map(tuple, columns(a)...)
    @test isa(convert(Columns, aa), Columns)
    @test convert(Columns, aa) == a
    bb = map((x,y)->(x=x,y=y), columns(a)...)
    @test isa(convert(Columns, bb), Columns)
    @test convert(Columns, bb) == Columns(x=column(a,1), y=column(a, 2))

    #78
    @test_throws ArgumentError map(x->throw(ArgumentError("x")), a)
    @inferred Columns((c=[1],))
    @inferred Columns([1])
    @test_throws ErrorException @inferred Columns(c=[1]) # bad
    #@inferred NDSparse(Columns(c=[1]), [1])
    #@inferred NDSparse(Columns([1]), [1])
    c = Columns([1,1,1,2,2], [1,2,4,3,5])
    d = Columns([1,1,2,2,2], [1,3,1,4,5])
    e = Columns([1,1,1], sort([rand(),0.5,rand()]))
    f = Columns([1,1,1], sort([rand(),0.5,rand()]))
    @test merge(NDSparse(c,ones(5)),NDSparse(d,ones(5))).index == Columns([1,1,1,1,2,2,2,2],[1,2,3,4,1,3,4,5])
    @test eltype(merge(NDSparse(c,Columns(ones(Int, 5))),NDSparse(d,Columns(ones(Float64, 5)))).data) == Tuple{Float64}
    @test eltype(merge(NDSparse(c,Columns(x=ones(Int, 5))),NDSparse(d,Columns(x=ones(Float64, 5)))).data) == typeof((x=0.,))
    @test length(merge(NDSparse(e,ones(3)),NDSparse(f,ones(3)))) == 5
    @test vcat(Columns(x=[1]), Columns(x=[1.0])) == Columns(x=[1,1.0])
    @test vcat(Columns(x=PooledArray(["x"])), Columns(x=["y"])) == Columns(x=["x", "y"])

    @test summary(c) == "5-element Columns{Tuple{Int64,Int64}}"


@testset "Getindex" begin
    cs = Columns(x=[1.2, 3.4], y=[3,4])
    t = table(cs, copy=false, pkey=:x)

    @test t[1] == (x=1.2, y=3)
    @test t[[true, false]] == t[[1]]
    @test t[[1,2]].columns == t.columns
    @test_throws ArgumentError t[[2,1]]

    s = table(cs)
    @test s[[2,1]] == table(rows(s)[[2,1]])
end

@testset "view & range" begin
    @test table(1:10) == table(collect(1:10))
    t = table(1:10, copy=false)
    @test columns(t, 1) == 1:10
    v = collect(1:10)
    t = view(table(v), 1:2)
    @test columns(t, 1) == view(v, 1:2)
    @test view(table(1:2), [true, false]) == view(table(1:2), [1])
    @test_throws ArgumentError view(table(1:2, pkey = 1), [2,1])
end

@testset "sortpermby" begin
    cs = Columns(x=[1,1,2,1,2], y=[1,2,2,1,2], z=[7,6,5,4,3])
    t = table(cs, copy=false, pkey=[:x, :y])
    # x=[1,1,1,2,2], y=[1,1,2,2,2], z=[7,4,6,5,3]
    @test column(t, :z) == [7,4,6,5,3]
    @test issorted(rows(t, (:x,:y)))
    @test sortpermby(t, (:y, :z), cache=true) == [2,1,5,4,3]
    @test t.perms[1].perm == [2,1,5,4,3]
    perms = [primaryperm(t); t.perms]

    @test sortpermby(t, (:y, :x)) == [2,1,3,5,4]
    @test length(t.perms) == 1

    # fully known
    @test best_perm_estimate(perms, [1,2]) == (2, Base.OneTo(5))
    @test best_perm_estimate(perms, [2,3]) == (2, [2, 1, 5, 4, 3])

    # first column known
    @test best_perm_estimate(perms, [1,3]) == (1, Base.OneTo(5))
    @test best_perm_estimate(perms, [2,1]) == (1, [2, 1, 5, 4, 3])

    # nothing known
    @test best_perm_estimate(perms, [3,1]) == (0, nothing)
end

@testset "sort" begin
    t = table(collect(1:10), collect(10:-1:1), names = [:x, :y])
    @test columns(sort(t, rev = true), :x) == collect(10:-1:1)
    @test columns(sort(t, :y), :y) == collect(1:10)
    sort!(t)
    @test columns(t, :x) == collect(1:10)
    sort!(t, :y)
    @test columns(t, :y) == collect(1:10)
end

    t = table([2, 1], [1, 3], [4, 5], names=[:x, :y, :z], pkey=(1, 2))
    @test reindex(t, (:y, :z)) == table([1, 3], [4, 5], [2, 1], names=Symbol[:y, :z, :x])
    @test reindex(t, Not(:x)) == reindex(t, (:y, :z))
    @test reindex(t, Not(:x), r"x") == reindex(t, (:y, :z), (:x,))
    @test pkeynames(t) == (:x, :y)
    @test reindex(t, (:w => [4, 5], :z)) == table([4, 5], [5, 4], [1, 2], [3, 1], names=Symbol[:w, :z, :x, :y])
    @test pkeynames(t) == (:x, :y)

    t = table([1, 2], [3, 4], names=[:x, :y])
    @test columns(t) == (x = [1, 2], y = [3, 4])
    @test columns(t, :x) == [1, 2]
    @test columns(t, (:x,)) == (x = [1, 2],)
    @test columns(t, (:y, :x => (-))) == (y = [3, 4], x = [-1, -2])
    t = table([1, 2], [3, 4], names=[:x, :y])
    @test rows(t) == Columns((x = [1, 2], y = [3, 4]))
    @test rows(t, :x) == [1, 2]
    @test rows(t, (:x,)) == Columns((x = [1, 2],))
    @test rows(t, (:y, :x => (-))) == Columns((y = [3, 4], x = [-1, -2]))

    x = NDSparse(Columns(a=[1,1], b=[1,2]), Columns(c=[3,4]))
    y = NDSparse(Columns(a=[1,1], b=[1,2]), [3,4])

    @test column(x, :a) == [1,1]
    @test column(x, [5,6]) == [5,6]
    @test column(x, :b) == [1,2]
    @test column(x, :c) == [3,4]
    @test column(x, 3) == [3,4]
    @test column(y, 3) == [3,4]

    @test columns(x, :a) == [1,1]
    @test columns(x, (:a,:c)) == (a=[1,1], c=[3,4])
    @test columns(y, (1, 3)) == ([1,1], [3,4])

    @test rows(x) == [(a=1,b=1,c=3), (a=1,b=2,c=4)]
    @test rows(x, :b) == [1, 2]
    @test rows(x, (:b, :c)) == [(b=1,c=3), (b=2,c=4)]
    @test rows(x, (:c, :b => -)) == [(c=3, b=-1),(c=4, b=-2)]
    @test rows(x, (:c, :x => [1,2])) == [(c=3, x=1),(c=4, x=2)]
    @test rows(x, (:c, [1,2])) == [(3,1), (4,2)]

    @test keys(x) == [(a=1,b=1), (a=1,b=2)]
    @test keys(x, :a) == [1, 1]

    @test values(x) == [(c=3,), (c=4,)]
    @test values(x,1) == [3,4]
    @test values(y) == [3, 4]
    @test values(y,1) == [3,4]

    @test collect(Base.pairs(x)) == [(a=1,b=1)=>(c=3,), (a=1,b=2)=>(c=4,)]
    @test collect(Base.pairs(y)) == [(a=1,b=1)=>3, (a=1,b=2)=>4]

@testset "column manipulation" begin
    t = table([1, 2], [3, 4], names=[:x, :y])
    @test setcol(t, 2, [5, 6]) == table([1, 2], [5, 6], names=Symbol[:x, :y])
    @test setcol(t, 2 => [5, 6]) == setcol(t, 2, [5, 6])
    @test setcol(t, 2 => [5, 6], 1 => [7, 12]) == table([7, 12], [5, 6], names=Symbol[:x, :y]) ==
        setcol(t, (2 => [5, 6], 1 => [7, 12]))
    @test setcol(t, :x, :x => (x->1 / x)) == table([1.0, 0.5], [3, 4], names=Symbol[:x, :y])
    t = table([0.01, 0.05], [1, 2], [3, 4], names=[:t, :x, :y], pkey=:t)
    t2 = setcol(t, :t, [0.1, 0.05])
    @test t2 == table([0.05, 0.1], [2,1], [4,3], names=[:t,:x,:y])
    t = table([0.01, 0.05], [2, 1], [3, 4], names=[:t, :x, :y], pkey=:t)
    @test pushcol(t, :z, [1 // 2, 3 // 4]) == table([0.01, 0.05], [2, 1], [3, 4], [1//2, 3//4], names=Symbol[:t, :x, :y, :z])
    @test pushcol(t, :z => [1 // 2, 3 // 4]) == pushcol(t, :z, [1 // 2, 3 // 4])
    @test pushcol(t, :z => [1 // 2, 3 // 4], :w => [0, 1]) ==
        table([0.01, 0.05], [2, 1], [3, 4], [1//2, 3//4], [0, 1], names=Symbol[:t, :x, :y, :z, :w]) ==
        pushcol(t, (:z => [1 // 2, 3 // 4], :w => [0, 1]))
    t = table([0.01, 0.05], [2, 1], [3, 4], names=[:t, :x, :y], pkey=(:t,:x))
    @test popcol(t, :t) == table([1, 2], [4,3], names=Symbol[:x, :y])
    @test popcol(t) == table([0.01, 0.05], [2, 1], names=Symbol[:t, :x])
    @test popcol(t, :x, :y) == table([0.01, 0.05], names=Symbol[:t]) == popcol(t, (:x, :y))
    @test pushcol(t, :z, [1 // 2, 3 // 4]) == table([0.01, 0.05], [2, 1], [3, 4], [1//2, 3//4], names=Symbol[:t, :x, :y, :z])

    # 99
    @test popcol(t, :x).pkey == [1]

    # "Copy-on write"
    t = table([1,2,3], [4,5,6], names=[:x,:y], pkey=:x)
    tcopy = copy(t)
    @test column(pushcol(t, :z, [7,8,9]), :x) === column(t, :x)
    @test t == tcopy

    @test column(setcol(t, :y, [7,8,9]), :x) === column(t, :x)
    @test t == tcopy

    # seting or popping an index column causes copy
    t2 = setcol(t, :x, [9,8,7])
    @test column(t2, :y) !== column(t, :y)
    @test t == tcopy
    @test t2 == table([7,8,9], [6,5,4], names=[:x, :y])

    t2 = popcol(t, :x)
    @test column(t2, :y) !== column(t, :y)
    @test t == tcopy
    @test t2 == table([4,5,6], names=[:y])

    t = table([0.01, 0.05], [2, 1], [3, 4], names=[:t, :x, :y], pkey=:t)
    @test insertcol(t, 2, :w, [0, 1]) == table([0.01, 0.05], [0, 1], [2, 1], [3, 4], names=Symbol[:t, :w, :x, :y])
    t = table([0.01, 0.05], [2, 1], [3, 4], names=[:t, :x, :y], pkey=:t)
    @test insertcolafter(t, :t, :w, [0, 1]) == table([0.01, 0.05], [0, 1], [2, 1], [3, 4], names=Symbol[:t, :w, :x, :y])
    t = table([0.01, 0.05], [2, 1], [3, 4], names=[:t, :x, :y], pkey=:t)
    @test insertcolbefore(t, :x, :w, [0, 1]) == table([0.01, 0.05], [0, 1], [2, 1], [3, 4], names=Symbol[:t, :w, :x, :y])
    t = table([0.01, 0.05], [2, 1], names=[:t, :x])
    @test renamecol(t, :t, :time) == table([0.01, 0.05], [2, 1], names=Symbol[:time, :x])
    @test_throws ErrorException renamecol(t, :tt, :time)
    @test renamecol(t, :t => :time) == renamecol(t, :t, :time)
    @test renamecol(t, :t => :time, :x => :position) ==
        table([0.01, 0.05], [2, 1], names=Symbol[:time, :position]) ==
        renamecol(t, (:t => :time, :x => :position))
end

@testset "map" begin
    x = ndsparse((t = [0.01, 0.05],), (x = [1, 2], y = [3, 4]))
    manh = map((row->row.x + row.y), x)
    vx = map((row->row.x / row.t), x, select=(:t, :x))
    polar = map((p->(r = hypot(p.x + p.y), θ = atan2(p.y, p.x))), x)
    @test map(sin, polar, select=:θ) == ndsparse((t = [0.01, 0.05],), [0.9486832980505138, 0.8944271909999159])

    t = table([0.01, 0.05], [1, 2], [3, 4], names=[:t, :x, :y])
    manh = map((row->row.x + row.y), t)
    polar = map((p->(r = hypot(p.x + p.y), θ = atan2(p.y, p.x))), t)
    vx = map((row->row.x / row.t), t, select=(:t, :x))
    @test map(sin, polar, select=:θ) == sin.(column(polar, :θ))
    t = NDSparse([1,2,3], Columns(x=[4,5,6]))
    @test isa(map(x->x.x, t).data, Vector)
    @test map(x->x.x, t).data == [4,5,6]

    t1 = map(x->(x=x.x,y=x.x^2), t)
    @test isa(t1.data, Columns)
    @test fieldnames(eltype(t1.data)) == (:x,:y)

    t2 = map(x->(x.x,x.x^2), t)
    @test isa(t2.data, Columns)
    @test isa(t2.data.columns, Tuple{Vector{Int}, Vector{Int}})

    t3 = map(x->ntuple(identity, x.x), t)
    @test isa(t3.data, Vector)
    @test eltype(t3.data) == Tuple

    y = [1, 1//2, "x"]
    function foo(x)
        tuple(x.x, y[x.x-3])
    end
    t4 = map(foo, t)
    @test isa(t4.data, Columns)
    @test eltype(t4.data) <: Tuple{Int, Any}

    t5 = table([1,2], ["a", "b"], names = [:x, :y])
    s = [:x, :y]
    @test map(i -> Tuple(getfield(i, j) for j in s), t5) == table([1,2], ["a", "b"])
    @test map(i -> (i.x => i.y), t5) == table([1,2], ["a","b"], pkey=1)
    @test map(i -> ((a = i.x-1,)=>(b=i.y,)), t5) == table([0,1], ["a","b"], pkey=:a, names=[:a,:b])

    @test map(t -> (1,2), table(Int[])) == table(Int[], Int[])
end

    l = table([1, 1, 2, 2], [1, 2, 1, 2], [1, 2, 3, 4], names=[:a, :b, :c], pkey=(:a, :b))
    r = table([0, 1, 1, 3], [1, 1, 2, 2], [1, 2, 3, 4], names=[:a, :b, :d], pkey=(:a, :b))
    @test join(l, r) == table([1, 1], [1, 2], [1, 2], [2, 3], names=Symbol[:a, :b, :c, :d])
    @test isequal(join(l, r, how=:left), table([1, 1, 2, 2], [1, 2, 1, 2], [1, 2, 3, 4], [2, 3,missing, missing], names=Symbol[:a, :b, :c, :d]))
    @test isequal(join(l, r, how=:outer), table([0, 1, 1, 2, 2, 3], [1, 1, 2, 1, 2, 2], [missing, 1, 2, 3, 4, missing], [1, 2, 3, missing, missing, 4], names=Symbol[:a, :b, :c, :d]))
    a = table([1],[2], names=[:x,:y])
    b = table([1],[3], names=[:a,:b])
    @test join(a, b, lkey=:x,rkey=:a) == table([1],[2],[3], names=[:x,:y,:b]) # issue JuliaDB.jl#105
    @test join(a, b, lkey=Not(:y), rkey = Not(:b)) == join(a, b, lkey=:x,rkey=:a)
    @test join(l, r, how=:anti) == table([2, 2], [1, 2], [3, 4], names=Symbol[:a, :b, :c])
    l1 = table([1, 2, 2, 3], [1, 2, 3, 4], names=[:x, :y])
    r1 = table([2, 2, 3, 3], [5, 6, 7, 8], names=[:x, :z])
    @test join(l1, r1, lkey=:x, rkey=:x) == table([2, 2, 2, 2, 3, 3], [2, 2, 3, 3, 4, 4], [5, 6, 5, 6, 7, 8], names=Symbol[:x, :y, :z])
    @test isequal(join(l, r, lkey=:a, rkey=:a, lselect=:b, rselect=:d, how=:outer), table([0, 1, 1, 1, 1, 2, 2, 3], [missing, 1, 1, 2, 2, 1, 2, missing], [1, 2, 3, 2, 3, missing, missing, 4], names=Symbol[:a, :b, :d]))


    t = table(["a","b","c","a"], [1,2,3,4]); t1 = table(["a","b"], [1,2])
    @test isequal(leftjoin(t,t1,lkey=1,rkey=1), table(["a","a","b","c"], [1,4,2,3], [1,1,2,missing]))

    t1 = table([1,2,3,4], [5,6,7,8], pkey=[1])
    t2 = table([0,3,4,5], [5,6,7,8], pkey=[1])
    t3 = table([0,3,4,4], [5,6,7,8], pkey=[1])
    t4 = table([1,3,4,4], [5,6,7,8], pkey=[1])
    @test naturaljoin(+, t1, t2, lselect=2, rselect=2) == table([3,4], [13, 15])
    @test naturaljoin(t1, t2, lselect=2, rselect=2) == table([3,4],[7,8],[6,7])
    @test naturaljoin(t1, t2) == table([3,4],[7,8],[6,7])
    @test naturaljoin(+, t1, t3, lselect=2, rselect=2) == table([3,4,4], [13, 15, 16])
    @test naturaljoin(+, t3, t4, lselect=2, rselect=2) == table([3,4,4,4,4], [12, 14,15,15,16])

    a = NDSparse([12,21,32], [52,41,34], [11,53,150])
    b = NDSparse([12,23,32], [52,43,34], [56,13,10])
    c = naturaljoin(+, a, b)
    @test c[12,52] == 67
    @test c[32,34] == 160
    @test length(c.index) == 2
    @test naturaljoin(a, b) == NDSparse([12,32], [52,34], Columns([11,150], [56,10]))

    c = NDSparse([12,32], [52,34], Columns([0,1], [2,3]))
    @test naturaljoin(a, c) == NDSparse([12,32], [52,34], Columns([11,150], [0,1], [2,3]))
    @test naturaljoin(c, a) == NDSparse([12,32], [52,34], Columns([0,1], [2,3], [11,150]))

    @test isequal(
              leftjoin(t1, t2, lselect=2, rselect=2),
              table([1,2,3,4], [5,6,7,8], [missing, missing, 6, 7]))

    # null instead of missing row
    @test isequal(leftjoin(+, t1, t2, lselect=2, rselect=2), table([1,2,3,4], [missing, missing, 13, 15]))

    @test isequal(leftjoin(t1, t2), table([1,2,3,4], [5,6,7,8],[missing, missing,6,7]))
    @test isequal(leftjoin(+, t1, t3, lselect=2, rselect=2), table([1,2,3,4,4],[missing,missing,13,15,16]))
    @test isequal(leftjoin(+, t3, t4, lselect=2, rselect=2), table([0,3,4,4,4,4], [missing, 12, 14,15,15,16]))

    @test isequal(leftjoin(NDSparse([1,1,1,2], [2,3,4,4], [5,6,7,8]),
                   NDSparse([1,1,3],   [2,4,4],   [9,10,12])),
                  NDSparse([1,1,1,2], [2,3,4,4], Columns([5, 6, 7, 8], [9, missing, 10, missing])))

    @test isequal(
                  leftjoin(NDSparse([1,1,1,2], [2,3,4,4], [5,6,7,8]),
                   NDSparse([1,1,2],   [2,4,4],   [9,10,12])),
                  NDSparse([1,1,1,2], [2,3,4,4], Columns([5, 6, 7, 8], [9, missing, 10, 12])))


    @test isequal(outerjoin(t1, t2, lselect=2, rselect=2), table([0,1,2,3,4,5], [missing, 5,6,7,8,missing], [5,missing,missing,6,7,8]))

    #showl instead of missing row
    @test isequal(outerjoin(+, t1, t2, lselect=2, rselect=2), table([0,1,2,3,4,5], [missing, missing, missing, 13, 15, missing]))

    @test isequal(outerjoin(t1, t2), table([0,1,2,3,4,5], [missing, 5,6,7,8,missing], [5,missing,missing,6,7,8]))
    @test isequal(outerjoin(+, t1, t3, lselect=2, rselect=2), table([0,1,2,3,4,4],[missing,missing,missing,13,15,16]))
    @test isequal(outerjoin(+, t3, t4, lselect=2, rselect=2), table([0,1,3,4,4,4,4], [missing, missing, 12,14,15,15,16]))

@testset "groupjoin" begin
    l = table([1, 1, 1, 2], [1, 2, 2, 1], [1, 2, 3, 4], names=[:a, :b, :c], pkey=(:a, :b))
    r = table([0, 1, 1, 2], [1, 2, 2, 1], [1, 2, 3, 4], names=[:a, :b, :d], pkey=(:a, :b))
    @test groupjoin(l, r) == table([1, 2], [2, 1], [Columns((c = [2, 2, 3, 3], d = [2, 3, 2, 3])), Columns((c = [4], d = [4]))], names=Symbol[:a, :b, :groups])
    @test groupjoin(l, r, how=:left) == table([1, 1, 2], [1, 2, 1], [Columns((c = [], d = [])), Columns((c = [2, 2, 3, 3], d = [2, 3, 2, 3])), Columns((c = [4], d = [4]))], names=Symbol[:a, :b, :groups])
    @test groupjoin(l, r, how=:outer) == table([0, 1, 1, 2], [1, 1, 2, 1], [Columns((c = [], d = [])), Columns((c = [], d = [])), Columns((c = [2, 2, 3, 3], d = [2, 3, 2, 3])), Columns((c = [4], d = [4]))], names=Symbol[:a, :b, :groups])
    @test groupjoin(l, r, lkey=:a, rkey=:a, lselect=:c, rselect=:d, how=:outer) == table([0, 1, 2], [Columns((c = [], d = [])), Columns((c = [1, 1, 2, 2, 3, 3], d = [2, 3, 2, 3, 2, 3])), Columns((c = [4], d = [4]))], names=Symbol[:a, :groups])
    t = table([0,1,2,2], [0,1,2,3])
    t2 = table([1,2,2,3],[4,5,6,7])
    @test outergroupjoin(t, t2, lkey=1, rkey=1) == table([0,1,2,3], [[],[(1,4)], [(2,5), (2,6), (3,5), (3,6)], []])
    @test outergroupjoin(-,t, t2, lkey=1, rkey=1, lselect=2,rselect=2, init_group=()->0, accumulate=min) == table([0,1,2,3], [0, -3, -4, 0])
end

@testset "reducedim" begin
    x = ndsparse((x = [1, 1, 1, 2, 2, 2], y = [1, 2, 2, 1, 2, 2], z = [1, 1, 2, 1, 1, 2]), [1, 2, 3, 4, 5, 6])
    @test reducedim(+, x, 1) == ndsparse((y = [1, 2, 2], z = [1, 1, 2]), [5, 7, 9])
    @test reducedim(+, x, (1, 3)) == ndsparse((y = [1, 2],), [5, 16])
end

@testset "select" begin
    tbl = table([0.01, 0.05], [2, 1], [3, 4], names=[:t, :x, :y], pkey=:t)
    @test select(tbl, 2) == [2, 1]
    @test select(tbl, :t) == [0.01, 0.05]
    @test select(tbl, :t => (t->1 / t)) == [100.0, 20.0]
    @test select(tbl, [3, 4]) == [3, 4]
    @test select(tbl, (2, 1)) == table([2, 1], [0.01, 0.05], names=Symbol[:x, :t])
    vx = select(tbl, (:x, :t) => (p->p.x / p.t))
    @test select(tbl, (:x, :t => (-))) == table([1, 2], [-0.05, -0.01], names=Symbol[:x, :t])
    @test select(tbl, (:x, :t, [3, 4])) == table([2, 1], [0.01, 0.05], [3, 4], names=[1, 2, 3])
    @test select(tbl, (:x, :t, :z => [3, 4])) == table([2, 1], [0.01, 0.05], [3, 4], names=Symbol[:x, :t, :z])
    @test select(tbl, (:x, :t, :minust => (:t => (-)))) == table([2, 1], [0.01, 0.05], [-0.01, -0.05], names=Symbol[:x, :t, :minust])
    @test select(tbl, (:x, :t, :vx => ((:x, :t) => (p->p.x / p.t)))) == table([2, 1], [0.01, 0.05], [200.0, 20.0], names=Symbol[:x, :t, :vx])

    a = ndsparse(([1,1,2,2], [1,2,1,2]), [6,7,8,9])
    @test selectkeys(a, 1, agg=+) == ndsparse([1,2], [13,17])
    @test selectkeys(a, 2, agg=+) == ndsparse([1,2], [14,16])
end

@testset "specialselector" begin
    t = table([1, 2, 3], ["a", "b", "c"], [4, 5, 6], names = [:x, :y, :z], pkey = :x)

    @test select(t, Keys()) == select(t, (:x,))
    @test select(t, (Keys(), :y)) == select(t, ((:x,), :y))
    @test select(t, Not(Keys())) == select(t, Not(:x)) == select(t, (:y, :z))
    @test select(t, Not(Keys(), :y)) == select(t, Not(:x, :y)) == select(t, (:z,))
    @test select(t, All(Keys(), :y)) == select(t, (:x, :y))
    @test select(t, All()) == t
    @test select(t, Between(:x, :z)) == select(t, (:x, :y, :z))
    @test select(t, i -> i == :y) == select(t, (:y,))
    @test select(t, r"x|z") == select(t, (:x, :z))

    @test rows(t, Keys()) == rows(t, (:x,))
    @test rows(t, (Keys(), :y)) == rows(t, ((:x,), :y))
    @test rows(t, Not(Keys())) == rows(t, Not(:x)) == rows(t, (:y, :z))
    @test rows(t, Not(Keys(), :y)) == rows(t, Not(:x, :y)) == rows(t, (:z,))
    @test rows(t, All(Keys(), :y)) == rows(t, (:x, :y))
    @test rows(t, All()) == rows(t)
    @test rows(t, Between(:x, :z)) == rows(t, (:x, :y, :z))
    @test rows(t, i -> i == :y) == rows(t, (:y,))
    @test rows(t, r"x|z") == rows(t, (:x, :z))

    @test columns(t, Keys()) == columns(t, (:x,))
    @test columns(t, (Keys(), :y)) == columns(t, ((:x,), :y))
    @test columns(t, Not(Keys())) == columns(t, Not(:x)) == columns(t, (:y, :z))
    @test columns(t, Not(Keys(), :y)) == columns(t, Not(:x, :y)) == columns(t, (:z,))
    @test columns(t, All(Keys(), :y)) == columns(t, (:x, :y))
    @test columns(t, All()) == columns(t)
    @test columns(t, Between(:x, :z)) == columns(t, (:x, :y, :z))
    @test columns(t, i -> i == :y) == columns(t, (:y,))
    @test columns(t, r"x|z") == columns(t, (:x, :z))

    @test hascolumns(t, 1)
    @test !hascolumns(t, 10)
    @test hascolumns(t, :x)
    @test !hascolumns(t, :xx)
    @test !hascolumns(t, (:xx, :y))
    @test hascolumns(t, Keys())
    @test hascolumns(t, (Keys(), :y))
    @test hascolumns(t, Not(Keys()))
    @test !hascolumns(t, Not(Keys(), :xx))
    @test hascolumns(t, All(Keys(), :y))
    @test hascolumns(t, All())
    @test hascolumns(t, Between(:x, :z))
    @test !hascolumns(t, Between(:x, :xx))
    @test hascolumns(t, i -> i == :y)
    @test hascolumns(t, r"x|z")
end

    t = table([0.1, 0.5, missing, 0.7], [2, missing, 4, 5], [missing, 6, missing, 7], names=[:t, :x, :y])
    @test dropna(t) == table([0.7], [5], [7], names=Symbol[:t, :x, :y])
    @test isequal(dropna(t, :y), table([0.5, 0.7], [missing, 5], [6, 7], names=Symbol[:t, :x, :y]))
    t1 = dropna(t, (:t, :x))
    @test typeof(column(dropna(t, :x), :x)) == Array{Int64,1}

@testset "filter" begin
    t = table(["a", "b", "c"], [0.01, 0.05, 0.07], [2, 1, 0], names=[:n, :t, :x])
    @test filter((p->p.x / p.t < 100), t) == table(["b", "c"], [0.05, 0.07], [1, 0], names=Symbol[:n, :t, :x])
    x = ndsparse((n = ["a", "b", "c"], t = [0.01, 0.05, 0.07]), [2, 1, 0])
    @test filter((y->y < 2), x) == ndsparse((n = ["b", "c"], t = [0.05, 0.07]), [1, 0])
    @test filter(iseven, t, select=:x) == table(["a", "c"], [0.01, 0.07], [2, 0], names=Symbol[:n, :t, :x])
    @test filter((p->p.x / p.t < 100), t, select=(:x, :t)) == table(["b", "c"], [0.05, 0.07], [1, 0], names=Symbol[:n, :t, :x])
    @test filter((p->p[2] / p[1] < 100), x, select=(:t, 3)) == ndsparse((n = ["b", "c"], t = [0.05, 0.07]), [1, 0])
    @test filter((:x => iseven, :t => (a->a > 0.01)), t) == table(["c"], [0.07], [0], names=Symbol[:n, :t, :x])
    @test filter((3 => iseven, :t => (a->a > 0.01)), x) == ndsparse((n = ["c"], t = [0.07]), [0])

end

@testset "asofjoin" begin
    x = ndsparse((["ko", "ko", "xrx", "xrx"], Date.(["2017-11-11", "2017-11-12", "2017-11-11", "2017-11-12"])), [1, 2, 3, 4])
    y = ndsparse((["ko", "ko", "xrx", "xrx"], Date.(["2017-11-12", "2017-11-13", "2017-11-10", "2017-11-13"])), [5, 6, 7, 8])
    @test asofjoin(x, y) == ndsparse((String["ko", "ko", "xrx", "xrx"], Date.(["2017-11-11", "2017-11-12", "2017-11-11", "2017-11-12"])), [1, 5, 7, 7])
    @test asofjoin(NDSparse([:msft,:ibm,:ge], [1,3,4], [100,200,150]),
                   NDSparse([:ibm,:msft,:msft,:ibm], [0,0,0,2], [100,99,101,98])) ==
                       NDSparse([:msft,:ibm,:ge], [1,3,4], [101, 98, 150])

    @test asofjoin(NDSparse([:AAPL, :IBM, :MSFT], [45, 512, 454], [63, 93, 54]),
                   NDSparse([:AAPL, :MSFT, :AAPL], [547,250,34], [88,77,30])) ==
                       NDSparse([:AAPL, :MSFT, :IBM], [45, 454, 512], [30, 77, 93])

    @test asofjoin(NDSparse([:aapl,:ibm,:msft,:msft],[1,1,1,3],[4,5,6,7]),
                   NDSparse([:aapl,:ibm,:msft],[0,0,0],[8,9,10])) ==
                       NDSparse([:aapl,:ibm,:msft,:msft],[1,1,1,3],[8,9,10,10])

end

@testset "merge" begin
    a = table([1, 3, 5], [1, 2, 3], names=[:x, :y], pkey=:x)
    b = table([2, 3, 4], [1, 2, 3], names=[:x, :y], pkey=:x)
    @test merge(a, b) == table([1, 2, 3, 3, 4, 5], [1, 1, 2, 2, 3, 3], names=Symbol[:x, :y])
    c = merge(a, select(b, (:y, :x)))
    @test merge(a, b) == c
    @test c.pkey == [1]
    d = reindex(b, :y)
    e = merge(a, d)
    @test Set(e) == Set(c)
    @test e.pkey == []
    a = ndsparse([1, 3, 5], [1, 2, 3])
    b = ndsparse([2, 3, 4], [1, 2, 3])
    @test merge(a, b) == ndsparse(([1, 2, 3, 4, 5],), [1, 1, 2, 3, 3])
    @test merge(a, b, agg=+) == ndsparse(([1, 2, 3, 4, 5],), [1, 1, 4, 3, 3])

    # merge optimization for pooled arrays
    x = begin
        x = [randstring(5) for idx in 1:128];
        for idx in 1:5
            x = vcat(x, x)
        end
        PooledArray(x)
    end;
    a = table(x, names=[:x]);
    b = table([randstring(5) for idx in 1:64], names=[:x]);
    c = merge(a, b);
    d = merge(b, a);

    @test isa(select(a, :x), PooledArray)
    @test !isa(select(b, :x), PooledArray)
    @test isa(select(c, :x), PooledArray)
    @test isa(select(d, :x), PooledArray)
end

@testset "broadcast" begin
    a = ndsparse(([1, 1, 2, 2], [1, 2, 1, 2]), [1, 2, 3, 4])
    b = ndsparse([1, 2], [1 / 1, 1 / 2])
    @test broadcast(*, a, b) == ndsparse(([1, 1, 2, 2], [1, 2, 1, 2]), [1.0, 2.0, 1.5, 2.0])
    #@test a .* b == ndsparse(([1, 1, 2, 2], [1, 2, 1, 2]), [1.0, 2.0, 1.5, 2.0])
    @test broadcast(*, a, b, dimmap=(0, 1)) == ndsparse(([1, 1, 2, 2], [1, 2, 1, 2]), [1.0, 1.0, 3.0, 2.0])
end
using OnlineStats

    t = table([0.1, 0.5, 0.75], [0, 1, 2], names=[:t, :x])
    @test reduce(+, t, select=:t) == 1.35
    @test reduce(+, 1.0, t, select = :t) == 2.35
    @test reduce(((a, b)->(t = a.t + b.t, x = a.x + b.x)), t) == (t = 1.35, x = 3)
    @test value(reduce(Mean(), t, select=:t)) == 0.45
    y = reduce((min, max), t, select=:x)
    @test y.max == 2
    @test y.min == 0
    y = reduce((sum = (+), prod = (*)), t, select=:x)
    x = select(t, :x)
    @test y == (sum = sum(x), prod = prod(x))
    y = reduce((Mean(), Variance()), t, select=:t)
    @test value(y.Mean) == 0.45
    @test value(y.Variance) == 0.10749999999999998
    @test reduce((xsum = (:x => (+)), negtsum = ((:t => (-)) => (+))), t) == (xsum = 3, negtsum = -1.35)

@testset "groupreduce" begin
    a = table([1, 1, 2], [2, 3, 3], [4, 5, 2], pkey=[1,2])
    b = table(Columns(a=[1, 1, 2], b=[3, 2, 2], c=[4, 5, 2]), pkey=(1,2))

    @test groupreduce(min, a, select=3) == a
    @test groupreduce(min, b, select=3) == renamecol(b, :c, :min)
    @test_throws ArgumentError groupreduce(+, b, [:x, :y]) # issue JuliaDB.jl#100
    t = table([1, 1, 1, 2, 2, 2], [1, 1, 2, 2, 1, 1], [1, 2, 3, 4, 5, 6], names=[:x, :y, :z], pkey=(:x, :y))
    @test groupreduce(+, t, :x, select=:z) == table([1, 2], [6, 15], names=Symbol[:x, :+])
    @test groupreduce(((x, y)->if x isa Int
                           (y = x + y,)
                    else
                           (y = x.y + y,)
                    end), t, :x, select=:z) == table([1, 2], [6, 15], names=Symbol[:x, :y])
    @test groupreduce(:y => (+), t, :x, select=:z) == table([1, 2], [6, 15], names=Symbol[:x, :y])
    t = table([1, 1, 1, 2, 2, 2], [1, 1, 2, 2, 1, 1], [1, 2, 3, 4, 5, 6], names=[:x, :y, :z])
    @test groupreduce(+, t, :x, select=:z) == table([1, 2], [6, 15], names=Symbol[:x, :+])
    @test groupreduce(+, t, (:x, :y), select=:z) == table([1, 1, 2, 2], [1, 2, 1, 2], [3, 3, 11, 4], names=Symbol[:x, :y, :+])
    @test groupreduce((+, min, max), t, (:x, :y), select=:z) == table([1, 1, 2, 2], [1, 2, 1, 2], [3, 3, 11, 4], [1, 3, 5, 4], [2, 3, 6, 4], names=Symbol[:x, :y, :+, :min, :max])
    @test groupreduce((+, min, max), t, All(:x, :y), select=:z) == groupreduce((+, min, max), t, (:x, :y), select=:z)
    @test groupreduce((zsum = (+), zmin = min, zmax = max), t, (:x, :y), select=:z) == table([1, 1, 2, 2], [1, 2, 1, 2], [3, 3, 11, 4], [1, 3, 5, 4], [2, 3, 6, 4], names=Symbol[:x, :y, :zsum, :zmin, :zmax])
    @test groupreduce((xsum = :z => +, negysum = (:y => -) => +), t, :x) == table([1, 2], [6, 15], [-4, -4], names=Symbol[:x, :xsum, :negysum])
    t = NDSparse([1, 1, 1, 1, 2, 2],
                     [2, 2, 2, 3, 3, 3],
                     [1, 4, 3, 5, 2, 0], presorted=true)
end

@testset "groupby" begin
    x = Columns(a=[1, 1, 1, 1, 1, 1],
                b=[2, 2, 2, 3, 3, 3],
                c=[1, 4, 3, 5, 2, 0])

    a = table(x, pkey=[1,2], presorted=true)
    @test groupby(maximum, a, select=3) == table(Columns(a=[1, 1], b=[2, 3], maximum=[4, 5]))
    @test groupby(identity, a, Keys()) == groupby(identity, a)

    @test groupby((maximum, minimum), a, select=3) ==
                table(Columns(a=[1, 1], b=[2, 3],
                                  maximum=[4, 5], minimum=[1, 0]))

    @test groupby((max=maximum, min=minimum), a, select=3) ==
                table(Columns(a=[1, 1], b=[2, 3],
                                  max=[4, 5], min=[1, 0]))
    t = table([1, 1, 1, 2, 2, 2], [1, 1, 2, 2, 1, 1], [1, 2, 3, 4, 5, 6], names=[:x, :y, :z])
    @test groupby(mean, t, :x, select=:z) == table([1, 2], [2.0, 5.0], names=Symbol[:x, :mean])
    @test groupby(identity, t, (:x, :y), select=:z) == table([1, 1, 2, 2], [1, 2, 1, 2], [[1, 2], [3], [5, 6], [4]], names=Symbol[:x, :y, :identity])
    @test groupby(mean, t, (:x, :y), select=:z) == table([1, 1, 2, 2], [1, 2, 1, 2], [1.5, 3.0, 5.5, 4.0], names=Symbol[:x, :y, :mean])
    @test groupby((mean, std, var), t, :y, select=:z) == table([1, 2], [3.5, 3.5], [2.3804761428476167, 0.7071067811865476], [5.666666666666667, 0.5], names=Symbol[:y, :mean, :std, :var])
    @test groupby((q25 = (z->quantile(z, 0.25)), q50 = median, q75 = (z->quantile(z, 0.75))), t, :y, select=:z) == table([1, 2], [1.75, 3.25], [3.5, 3.5], [5.25, 3.75], names=Symbol[:y, :q25, :q50, :q75])
    @test groupby((xmean = (:z => mean), ystd = ((:y => (-)) => std)), t, :x) == table([1, 2], [2.0, 5.0], [0.5773502691896257, 0.5773502691896257], names=Symbol[:x, :xmean, :ystd])
    @test groupby((ncols = length∘colnames,), t, :x) == table([1, 2], [2, 2], names = [:x, :ncols], pkey = :x)
    func1 = (key, dd) -> key.x + length(dd)
    @test groupby((:s => func1, ), t, :x, usekey = true) == table([1, 2], [4, 5], names = [:x, :s], pkey = :x)
    func2 = (key, dd) -> key.x - length(dd)
    @test groupby((:s => func1, :d => func2), t, :x, usekey = true) == table([1, 2], [4, 5], [-2, -1], names = [:x, :s, :d], pkey = :x)
    @test groupby(:s => func1, t, :x, usekey = true) == table([1, 2], [4, 5], names = [:x, :s], pkey = :x)
    s(key, dd) = func1(key, dd)
    #@test groupby(s, t, :x, usekey = true) == groupby((:s => func1, ), t, :x, usekey = true)
    s2(key, dd) = length(dd)
    #@test groupby(s2, t, usekey = true) == (s2 = 6,)

    @test groupby(maximum,
                  NDSparse([1, 1, 1, 1, 1, 1],
                               [2, 2, 2, 3, 3, 3],
                               [1, 4, 3, 5, 2, 0], presorted=true)) ==
                  NDSparse([1, 1], [2, 3], [4, 5])

    @test groupby(maximum,
                  NDSparse([1, 1, 1, 1, 1, 1],
                               [2, 2, 2, 3, 3, 3],
                               [1, 4, 3, 5, 2, 0], presorted=true), select=(2,3)) ==
                  NDSparse([1, 1], [2, 3], [(2,4), (3,5)])

    @test groupby((maximum, minimum),
                  NDSparse([1, 1, 1, 1, 1, 1],
                               [2, 2, 2, 3, 3, 3],
                               [1, 4, 3, 5, 2, 0], presorted=true)) ==
                  NDSparse([1, 1], [2, 3], Columns(maximum=[4, 5], minimum=[1, 0]))

    @test groupby((maxv = maximum, minv = minimum), NDSparse([1, 1, 1, 1, 1, 1],
                                     [2, 2, 2, 3, 3, 3],
                                     [1, 4, 3, 5, 2, 0], presorted=true),) ==
                        NDSparse([1, 1], [2, 3], Columns(maxv=[4, 5], minv=[1, 0]))
end

    a = table([1,3,5], [2,2,2], names = [:x, :y])
    @test summarize((mean, std), a) ==
        (x_mean = 3.0, y_mean = 2.0, x_std = 2.0, y_std = 0.0)
    @test summarize((mean, std), a, select = :x) == (mean = 3.0, std = 2.0)
    @test summarize((m = mean, s = std), a) ==
        (x_m = 3.0, y_m = 2.0, x_s = 2.0, y_s = 0.0)
    b = table(["a","a","b","b"], [1,3,5,7], [2,2,2,2], names = [:x, :y, :z], pkey = :x)
    @test summarize(mean, b) ==
        table(["a","b"], [2.0,6.0], [2.0,2.0], names = [:x, :y, :z], pkey = :x)
    @test summarize((mean, std), a, stack = true) ==
        table([:x, :y], [3.0, 2.0], [2.0, 0.0], names = [:variable, :mean, :std])
    @test summarize(mean, a, stack = true) ==
        table([:x, :y], [3.0, 2.0], names = [:variable, :mean])
    @test summarize(mean, b, stack = true) ==
        table(["a","a","b","b"], [:y,:z,:y,:z], [2.0,2.0,6.0,2.0], names = [:x, :variable, :mean], pkey = :x)
    @test summarize((mean, sum), b, stack = true) ==
        table(["a","a","b","b"], [:y,:z,:y,:z], [2.0,2.0,6.0,2.0], [4,4,12,4],
        names = [:x, :variable, :mean, :sum], pkey = :x)

@testset "reshape" begin
    t = table(1:4, [1, 4, 9, 16], [1, 8, 27, 64], names = [:x, :xsquare, :xcube], pkey = :x)
    tsparse = IndexedTables._convert(NDSparse, t)
    long = stack(t; variable = :var, value = :val)
    longsparse = stack(tsparse; variable = :var, value = :val)
    @test long == table([1, 1, 2, 2, 3, 3, 4, 4],
                        [:xsquare, :xcube, :xsquare, :xcube, :xsquare, :xcube, :xsquare, :xcube],
                        [1, 1, 4, 8, 9, 27, 16, 64];
                        names = [:x, :var, :val], pkey = :x)
    @test longsparse == IndexedTables._convert(NDSparse, long)
    @test unstack(long; variable = :var, value = :val) == t
    @test unstack(longsparse; variable = :var, value = :val) == tsparse
    t1 = table([1, 1, 1, 2, 2], [:x, :x, :y, :x, :y], [1, 2, 3, 4, 5], names = [:x, :variable, :value])
    @test_throws Exception unstack(t1, :x)
    long2 = table([1, 1, 2, 2, 3, 3, 4, 4],
                  [2, 3, 2, 3, 2, 3, 2, 3],
                  [1, 1, 4, 8, 9, 27, 16, 64];
                  names = [:x, :var, :val], pkey = :x)
    res = table(1:4, [1, 4, 9, 16], [1, 8, 27, 64], names = [:x, Symbol(2), Symbol(3)], pkey = :x)
    @test unstack(long2; variable = :var, value = :val) == res
end

@testset "select" begin
    a = table([12,21,32], [52,41,34], [11,53,150], pkey=[1,2])
    b = table([12,23,32], [52,43,34], [56,13,10], pkey=[1,2])

    c = filter((1=>x->x<30, 2=>x->x>40), a)
    @test rows(c) == [(12,52,11), (21,41,53)]
    @test c.pkey == [1,2]

    c = select(a, (1, 2))
    @test c == table(column(a, 1), column(a, 2))
    @test c.pkey == [1,2]
    @test convertdim(NDSparse([1, 1, 1, 1, 1, 1],
                                  [0, 1, 2, 3, 4, 5],
                                  [1, 4, 3, 5, 2, 0], presorted=true), 2, x->div(x,3), vecagg=maximum) ==
                        NDSparse([1, 1], [0, 1], [4, 5])
end

@testset "conversions" begin
    A = rand(3,3)
    B = rand(3,3)
    C = rand(3,3)
    nA = convert(NDSparse, A)
    nB = convert(NDSparse, B)
    nB.index.columns[1][:] += 3
    @test merge(nA,nB) == convert(NDSparse, vcat(A,B))
    nC = convert(NDSparse, C)
    nC.index.columns[1][:] += 6
    @test merge(nA,nB,nC) == merge(nA,nC,nB) == convert(NDSparse, vcat(A,B,C))
    merge!(nA,nB)
    @test nA == convert(NDSparse, vcat(A,B))

    t1 = NDSparse(Columns(a=[1,1,2,2], b=[1,2,1,2]), [1,2,3,4])
    t2 = NDSparse(Columns(a=[0,1,2,3], b=[1,2,1,2]), [1,2,3,4])
    @test merge(t1, t2, agg=+) == NDSparse(Columns(a=[0,1,1,2,2,3], b=[1,1,2,1,2,2]), [1,1,4,6,4,4])
    @test merge(t1, t2, agg=nothing) == NDSparse(Columns(a=[0,1,1,1,2,2,2,3], b=[1,1,2,2,1,1,2,2]), [1,1,2,2,3,3,4,4])

    S = spdiagm(1:5)
    nd = convert(NDSparse, S)
    @test sum(S) == sum(nd) == sum(convert(NDSparse, full(S)))

    @test sum(broadcast(+, 10, nd)) == (sum(nd) + 10*nnz(S))
    @test sum(broadcast(+, nd, 10)) == (sum(nd) + 10*nnz(S))
    @test sum(broadcast(+, nd, nd)) == 2*(sum(nd))

    nd[1:5,1:5] = 2
    @test nd == convert(NDSparse, spdiagm(fill(2, 5)))

    a = [1,2,3]
    b = ["a","b","c"]
    v = Columns(Pair(a, b))
    @test convert(NDSparse, a, b) == convert(NDSparse, v) == ndsparse(v) == ndsparse(a, b)
end

@testset "mapslices" begin
    # scalar
    x=NDSparse(Columns(a=[1,1,1,2,2],b=PooledArray(["a","b","c","a","b"])),[1,2,3,4,5])
    t = mapslices(y->sum(y), x, (1,))
    @test t == NDSparse(Columns(b=["a","b","c"]), [5,7,3])

    A = [1]
    # shouldn't mutate input
    mapslices(x, [:a]) do slice
        NDSparse(Columns(A), A)
    end
    @test A == [1]

    # scalar
    r = Ref(0)
    t = mapslices(x, [:a]) do slice
        r[] += 1
        n = length(slice)
        NDSparse(Columns(c=[1:n;]), [r[] for i=1:n])
    end
    @test t == NDSparse(Columns(b=["a","a","b","b","c"], c=[1,2,1,2,1]), [1,1,2,2,3])

    # dedup names
    x=NDSparse(Columns(a=[1],b=[1]),Columns(c=[1]))
    t = mapslices(x,[:b]) do slice
            NDSparse(Columns(a=[2], c=[2]),
                         Columns(d=[1]))
    end
    @test t==NDSparse(Columns(a_1=[1], a_2=[2], c=[2]), Columns(d=[1]))

    # signleton slices
    x=NDSparse(Columns([1,2]),Columns([1,2]))
    @test_throws ErrorException mapslices(x,()) do slice
        true
    end
    t = mapslices(x,()) do slice
        @test slice == NDSparse(Columns([1]), Columns([1])) || slice == NDSparse(Columns([2]), Columns([2]))
        NDSparse(Columns([1]), ([1]))
    end
    @test t == NDSparse(Columns([1,2], [1,1]), [1,1])

    x = NDSparse([1,1,1,2,2,2,3,3],[1,2,3,4,5,6,7,8],rand(8));
    y = mapslices(t -> (1, 2), x, 2)
    @test isa(y.data, Columns)
end

@testset "flatten" begin
    x = table([1,2], [[3,4], [5,6]], names=[:x, :y])
    @test flatten(x, 2) == table([1,1,2,2], [3,4,5,6], names=[:x,:y])
    @test flatten(x, 2) == flatten(x)

    x = table([1,2], [table([3,4],[5,6], names=[:a,:b]), table([7,8], [9,10], names=[:a,:b])], names=[:x, :y]);
    @test flatten(x, :y) == table([1,1,2,2], [3,4,7,8], [5,6,9,10], names=[:x,:a, :b])

    t = table([1,1,2,2], [3,4,5,6], names=[:x,:y])
    @test groupby((:normy => x->Iterators.repeated(mean(x), length(x)),),
                  t, :x, select=:y, flatten=true) == table([1,1,2,2], [3.5,3.5,5.5,5.5], names=[:x, :normy])
    t=table([1,1,1,2,2,2], [1,1,2,1,1,2], [1,2,3,4,5,6], names=[:x,:y,:z], pkey=[1,2]);
    @test groupby(identity, t, (:x, :y), select=:z, flatten = true) == renamecol(t, :z, :identity)
    @test groupby(identity, t, (:x, :y), select=:z, flatten = true).pkey == [1,2]
    # If return type is non iterable, return the same as non flattened
    @test groupby(i -> (y = :y,), t, :x, flatten=true) == groupby(i -> (y = :y,), t, :x, flatten=false)
end

@testset "ColDict" begin
    t = table([1], names=[:x1])
    d = ColDict(t)
    d[:x2] = [2]
    d[:x3] = :x2 => -
    @test d[] == table([1], [2], [-2], names=[:x1,:x2,:x3])
end

@testset "shared data setindex!" begin
    x = ndsparse(([1,2], [3,4]), [5,6])
    reinterpret(UInt8, columns(x)[1]) # set isshared flag
    x[3,4] = 7
    flush!(x)
    @test x == ndsparse(([1,2,3],[3,4,4]), [5,6,7])
end
