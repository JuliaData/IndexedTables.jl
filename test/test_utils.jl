let a = NDSparse([12,21,32], [52,41,34], [11,53,150]), b = NDSparse([12,23,32], [52,43,34], [56,13,10])
    p = vec(collect(IndexedTables.product(a, b)))
    @test p == [(11,56), (11,13), (11,10), (53,56), (53,13), (53,10), (150,56), (150,13), (150,10)]

    p = vec(collect(IndexedTables.product(a, b, a)))
    @test p == [(11,56,11),(11,56,53),(11,56,150),(11,13,11),(11,13,53),(11,13,150),(11,10,11),(11,10,53),(11,10,150),
                (53,56,11),(53,56,53),(53,56,150),(53,13,11),(53,13,53),(53,13,150),(53,10,11),(53,10,53),(53,10,150),
                (150,56,11),(150,56,53),(150,56,150),(150,13,11),(150,13,53),(150,13,150),(150,10,11),(150,10,53),(150,10,150)]
end

let a = [1:10;]
    @test IndexedTables._sizehint!(1:10, 20) == 1:10
    @test IndexedTables._sizehint!(a, 20) === a
end

@test Columns([1,2], [3,4]) == Columns([1,2], [3.0,4.0])
@test Columns([1,2], [3,4]) != Columns([1,2], [3.0,4.1])
@test Columns([1,2], [3,4]) != Columns(a=[1,2], b=[3,4])

function roundtrips(x)
    b = IOBuffer()
    serialize(b, x)
    seekstart(b)
    return deserialize(b) == x
end

@test roundtrips(Columns(rand(5), rand(5)))
@test roundtrips(Columns(c1 = rand(5), c2 = rand(5)))
@test roundtrips(convert(NDSparse, rand(3,3)))
@test roundtrips(NDSparse(Columns(y=rand(3), x=rand(3)), rand(3)))

let x = rand(3), y = rand(3), v = rand(3), w = rand(3)
    @test vcat(Columns(x,y), Columns(v,w)) == Columns(vcat(x,v), vcat(y,w))
    @test vcat(Columns(x=x,y=y), Columns(x=v,y=w)) == Columns(x=vcat(x,v), y=vcat(y,w))
end

import IndexedTables: _promote_op

let
    f = x -> 1/x
    @test _promote_op(f, Int) == Float64

    f = x -> (x,1/x)
    @test _promote_op(f, Int) == Tuple{Int, Float64}

    foo(i) = [1, 1//2, "x"][i]
    f = x -> (x,foo(x))
    @test _promote_op(f, Int) == Tuple{Int, Any}

    bar(i) = Union{Int, String}[1, "x"][i]
    g = x -> (x,bar(x))
    @test _promote_op(g, Int) == Tuple{Int, Any}

    h = x -> rand(Bool) ? (x=1,) : (y=2,)
    @test _promote_op(h, Int) <: NamedTuple

    #101
    s = (1,)
    @test _promote_op(i -> Tuple(getfield(i, j) for j in s), Tuple{Int}) == Any

    # 97
    x = ndsparse((t=[0.01, 0.05],), (x=[1,2], y=[3,4],))
    @test map(p->(r = sum(p),), x).data == Columns([4,6], names=[:r])
end
