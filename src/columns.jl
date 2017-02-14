# a type that stores an array of tuples as a tuple of arrays

import Base:
    linearindexing, push!, size, sort, sort!, permute!, issorted, sortperm,
    summary, resize!, vcat, serialize, deserialize, append!, copy!

export Columns

immutable Columns{D<:Tup, C<:Tup} <: AbstractVector{D}
    columns::C

    function Columns(c)
        length(c) > 0 || error("must have at least one column")
        n = length(c[1])
        for i = 2:length(c)
            length(c[i]) == n || error("all columns must have same length")
        end
        new(c)
    end
end

@generated function _named_columns(cols::Tuple, names::Tuple)
    name_syms = [n.parameters[1] for n in names.parameters]
    eltypes = map(eltype, cols.parameters)
    coltypes = cols.parameters
    quote
        dt = @NT($(name_syms...)){$(eltypes...)}
        ct = @NT($(name_syms...)){$(coltypes...)}
        Columns{dt,ct}(ct($cols...))
    end
end

function Columns(cols::AbstractVector...; names::Union{Vector{Symbol},Tuple{Vararg{Symbol}},Void}=nothing)
    if isa(names, Void)
        Columns{eltypes(typeof(cols)),typeof(cols)}(cols)
    else
        _named_columns(cols, map(x->Val{x}(), (names...)))
    end
end

Columns(; pairs...) = Columns(map(x->x[2],pairs)..., names=Symbol[x[1] for x in pairs])

Columns(c::Tuple) = Columns{eltypes(typeof(c)),typeof(c)}(c)
Columns(c::NamedTuple) = Columns(c..., names=fieldnames(c))

eltype{D,C}(::Type{Columns{D,C}}) = D
length(c::Columns) = length(c.columns[1])
ndims(c::Columns) = 1
size(c::Columns) = (length(c),)
linearindexing{T<:Columns}(::Type{T}) = Base.LinearFast()
summary{D<:Tuple}(c::Columns{D}) = "Columns{$D}"

empty!(c::Columns) = (foreach(empty!, c.columns); c)
similar{D,C}(c::Columns{D,C}) = empty!(Columns{D,C}(map(similar, c.columns)))
similar{D,C}(c::Columns{D,C}, n::Integer) = Columns{D,C}(map(a->similar(a,n), c.columns))
copy{D,C}(c::Columns{D,C}) = Columns{D,C}(map(copy, c.columns))

getindex{D<:Tuple}(c::Columns{D}, i::Integer) = ith_all(i, c.columns)
getindex{D<:NamedTuple}(c::Columns{D}, i::Integer) = D(ith_all(i, c.columns)...)

getindex{D,C}(c::Columns{D,C}, p::AbstractVector) = Columns{D,C}(map(c->c[p], c.columns))

@inline setindex!(I::Columns, r::Tup, i::Integer) = (foreach((c,v)->(c[i]=v), I.columns, r); I)

@inline push!(I::Columns, r::Tup) = (foreach(push!, I.columns, r); I)

append!(I::Columns, J::Columns) = (foreach(append!, I.columns, J.columns); I)

copy!(I::Columns, J::Columns) = (foreach(copy!, I.columns, J.columns); I)

resize!(I::Columns, n::Int) = (foreach(c->resize!(c,n), I.columns); I)

_sizehint!(c::Columns, n::Integer) = (foreach(c->_sizehint!(c,n), c.columns); c)

function ==(x::Columns, y::Columns)
    nc = length(x.columns)
    length(y.columns) == nc || return false
    fieldnames(x.columns) == fieldnames(y.columns) || return false
    n = length(x)
    length(y) == n || return false
    for i in 1:nc
        x.columns[i] == y.columns[i] || return false
    end
    return true
end

function sortperm(c::Columns)
    x = c.columns[1]
    p = sortperm_fast(x)
    for i = 2:length(c.columns)
        y = c.columns[i]
        if isa(y, PooledArray)
            y = y.refs
        end
        if !refine_perm!(p, x, y)
            break
        end
        x = y
    end
    return p
end

issorted(c::Columns) = issorted(1:length(c), lt=(x,y)->rowless(c, x, y))

# assuming x[p] is sorted, sort p by vector y within regions where x[p] is constant
function refine_perm!(p, x, y)
    temp = similar(p, 0)
    order = Base.Order.By(j->(@inbounds k=y[j]; k))
    i = 1
    n = length(x)
    changed = false
    while i < n
        i1 = i+1
        @inbounds while i1 <= n && x[p[i1]] == x[p[i]]
            i1 += 1
        end
        i1 -= 1
        if i1 > i
            changed = true
            sort_sub_by!(p, i, i1, y, order, temp)
        end
        i = i1+1
    end
    return changed
end

function permute!(c::Columns, p::AbstractVector)
    for v in c.columns
        copy!(v, v[p])
    end
    return c
end
sort!(c::Columns) = permute!(c, sortperm(c))
sort(c::Columns) = c[sortperm(c)]

map(p::Proj, c::Columns) = p(c.columns)
(p::Proj)(c::Columns) = p(c.columns)

vcat{D<:Tup,C<:Tuple}(c::Columns{D,C}, cs::Columns{D,C}...) = Columns{D,C}((map(vcat, map(x->x.columns, (c,cs...))...)...,))
vcat{D<:Tup,C<:NamedTuple}(c::Columns{D,C}, cs::Columns{D,C}...) = Columns{D,C}(C(map(vcat, map(x->x.columns, (c,cs...))...)...,))

function vcat{D<:Tup}(c::Columns{D}, cs::Columns{D}...)
    cols = (map(vcat, map(x->x.columns, (c,cs...))...)...,)
    Columns{D,typeof(cols)}(cols)
end

vcat(c::Columns, cs::Columns...) = Columns(map(vcat, map(x->x.columns, (c,cs...))...)...)

function serialize(s::AbstractSerializer, c::Columns)
    Base.Serializer.serialize_type(s, Columns)
    serialize(s, eltype(c) <: NamedTuple)
    serialize(s, isa(c.columns, NamedTuple))
    serialize(s, fieldnames(c.columns))
    for col in c.columns
        serialize(s, col)
    end
end

function deserialize(s::AbstractSerializer, ::Type{Columns})
    Dnamed = deserialize(s)
    Cnamed = deserialize(s)
    fn = deserialize(s)
    cols = Any[ deserialize(s) for i = 1:length(fn) ]
    if Cnamed
        c = Columns(cols..., names = fn)
        if !Dnamed
            dt = eltypes(typeof((c.columns...,)))
            c = Columns{dt,typeof(c.columns)}(c.columns)
        end
    else
        c = Columns(cols...)
    end
    return c
end

# fused indexing operations
# these can be implemented for custom vector types like PooledVector where
# you can get big speedups by doing indexing and an operation in one step.

@inline cmpelts(a, i, j) = (@inbounds x=cmp(a[i], a[j]); x)
@inline copyelt!(a, i, j) = (@inbounds a[i] = a[j])

@inline cmpelts(a::PooledArray, i, j) = (x=cmp(a.refs[i],a.refs[j]); x)
@inline copyelt!(a::PooledArray, i, j) = (a.refs[i] = a.refs[j])

# row operations

copyrow!(I::Columns, i, src) = foreach(c->copyelt!(c, i, src), I.columns)

@generated function rowless{D,C}(c::Columns{D,C}, i, j)
    N = length(C.parameters)
    ex = :(cmpelts(getfield(c.columns,$N), i, j) < 0)
    for n in N-1:-1:1
        ex = quote
            let d = cmpelts(getfield(c.columns,$n), i, j)
                (d == 0) ? ($ex) : (d < 0)
            end
        end
    end
    ex
end

@generated function roweq{D,C}(c::Columns{D,C}, i, j)
    N = length(C.parameters)
    ex = :(cmpelts(getfield(c.columns,1), i, j) == 0)
    for n in 2:N
        ex = :(($ex) && (cmpelts(getfield(c.columns,$n), i, j)==0))
    end
    ex
end

# uses number of columns from `d`, assuming `c` has more or equal
# dimensions, for broadcast joins.
@generated function rowcmp{D}(c::Columns, i, d::Columns{D}, j)
    N = length(D.parameters)
    ex = :(cmp(getfield(c.columns,$N)[i], getfield(d.columns,$N)[j]))
    for n in N-1:-1:1
        ex = quote
            let k = cmp(getfield(c.columns,$n)[i], getfield(d.columns,$n)[j])
                (k == 0) ? ($ex) : k
            end
        end
    end
    ex
end

# test that the row on the right is "as of" the row on the left, i.e.
# all columns are equal except left >= right in last column.
# Could be generalized to some number of trailing columns, but I don't
# know whether that has applications.
@generated function row_asof{D,C}(c::Columns{D,C}, i, d::Columns{D,C}, j)
    N = length(C.parameters)
    if N == 1
        ex = :(!isless(getfield(c.columns,1)[i], getfield(d.columns,1)[j]))
    else
        ex = :(isequal(getfield(c.columns,1)[i], getfield(d.columns,1)[j]))
    end
    for n in 2:N
        if N == n
            ex = :(($ex) && !isless(getfield(c.columns,$n)[i], getfield(d.columns,$n)[j]))
        else
            ex = :(($ex) && isequal(getfield(c.columns,$n)[i], getfield(d.columns,$n)[j]))
        end
    end
    ex
end
