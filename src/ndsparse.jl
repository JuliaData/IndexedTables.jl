export AbstractNDSparse, NDSparse, ndsparse
using SparseArrays

abstract type AbstractNDSparse end

mutable struct NDSparse{T, D<:Tuple, C<:Columns, V<:AbstractVector} <: AbstractNDSparse
    index::C
    data::V
    _table::NextTable

    index_buffer::C
    data_buffer::V
end

function NextTable(nds::NDSparse; kwargs...)
    convert(NextTable, nds.index, nds.data; kwargs...)
end

convert(::Type{NextTable}, nd::NDSparse) = NextTable(nd)

Base.@deprecate_binding IndexedTable NDSparse

# optional, non-exported name
Base.@deprecate_binding Table NDSparse


"""
`ndsparse(indices, data; agg, presorted, copy, chunks)`

Construct an NDSparse array with the given indices and data. Each vector in `indices` represents the index values for one dimension. On construction, the indices and data are sorted in lexicographic order of the indices.

# Arguments:

* `agg::Function`: If `indices` contains duplicate entries, the corresponding data items are reduced using this 2-argument function.
* `presorted::Bool`: If true, the indices are assumed to already be sorted and no sorting is done.
* `copy::Bool`: If true, the storage for the new array will not be shared with the passed indices and data. If false (the default), the passed arrays will be copied only if necessary for sorting. The only way to guarantee sharing of data is to pass `presorted=true`.
* `chunks::Integer`: distribute the table into `chunks` (Integer) chunks (a safe bet is nworkers()). Not distributed by default. See [Distributed](@distributed) docs.

# Examples:

1-dimensional NDSparse can be constructed with a single array as index.
```jldoctest ndsparse
julia> x = ndsparse(["a","b"],[3,4])
1-d NDSparse with 2 values (Int64):
1   │
────┼──
"a" │ 3
"b" │ 4

julia> keytype(x), eltype(x)
(Tuple{String}, Int64)

```

A dimension will be named if constructed with a named tuple of columns as index.
```jldoctest ndsparse
julia> x = ndsparse(@NT(date=Date.(2014:2017)), [4:7;])
1-d NDSparse with 4 values (Int64):
date       │
───────────┼──
2014-01-01 │ 4
2015-01-01 │ 5
2016-01-01 │ 6
2017-01-01 │ 7

```

```jldoctest ndsparse
julia> x[Date("2015-01-01")]
5

julia> keytype(x), eltype(x)
(Tuple{Date}, Int64)

```

Multi-dimensional `NDSparse` can be constructed by passing a tuple of index columns:

```jldoctest ndsparse
julia> x = ndsparse((["a","b"],[3,4]), [5,6])
2-d NDSparse with 2 values (Int64):
1    2 │
───────┼──
"a"  3 │ 5
"b"  4 │ 6

julia> keytype(x), eltype(x)
(Tuple{String,Int64}, Int64)

julia> x["a", 3]
5
```

The data itself can also contain tuples (these are stored in columnar format, just like in `table`.)

```jldoctest ndsparse
julia> x = ndsparse((["a","b"],[3,4]), ([5,6], [7.,8.]))
2-d NDSparse with 2 values (2-tuples):
1    2 │ 3  4
───────┼───────
"a"  3 │ 5  7.0
"b"  4 │ 6  8.0

julia> x = ndsparse(@NT(x=["a","a","b"],y=[3,4,4]),
                    @NT(p=[5,6,7], q=[8.,9.,10.]))
2-d NDSparse with 3 values (2 field named tuples):
x    y │ p  q
───────┼────────
"a"  3 │ 5  8.0
"a"  4 │ 6  9.0
"b"  4 │ 7  10.0

julia> keytype(x), eltype(x)
(Tuple{String,Int64}, NamedTuples._NT_p_q{Int64,Float64})

julia> x["a", :]
2-d NDSparse with 2 values (2 field named tuples):
x    y │ p  q
───────┼───────
"a"  3 │ 5  8.0
"a"  4 │ 6  9.0

```

Passing a `chunks` option to `ndsparse`, or constructing with a distributed array will cause the result to be distributed. Use `distribute` function to distribute an array.

```jldoctest ndsparse
julia> x = ndsparse(@NT(date=Date.(2014:2017)), [4:7.;], chunks=2)
1-d Distributed NDSparse with 4 values (Float64) in 2 chunks:
date       │
───────────┼────
2014-01-01 │ 4.0
2015-01-01 │ 5.0
2016-01-01 │ 6.0
2017-01-01 │ 7.0

julia> x = ndsparse(@NT(date=Date.(2014:2017)), distribute([4:7.0;], 2))
1-d Distributed NDSparse with 4 values (Float64) in 2 chunks:
date       │
───────────┼────
2014-01-01 │ 4.0
2015-01-01 │ 5.0
2016-01-01 │ 6.0
2017-01-01 │ 7.0
```

Distribution is done to match the first distributed column from left to right. Specify `chunks` to override this.
"""
function ndsparse end

function ndsparse(I::Tup, d::Union{Tup, AbstractVector};
                  chunks=nothing, kwargs...)
    if chunks !== nothing
        impl = Val{:distributed}()
    else
        impl = _impl(astuple(I)...)
        if impl === Val{:serial}()
            impl = isa(d, Tup) ?
                _impl(impl, astuple(d)...) : _impl(d)
        end
    end
    ndsparse(impl, I, d; chunks=chunks, kwargs...)
end

function ndsparse(::Val{:serial}, ks::Tup, vs::Union{Tup, AbstractVector};
                  agg=nothing, presorted=false,
                  chunks=nothing, copy=true)

    I = rows(ks)
    d = vs isa Tup ? Columns(vs) : vs

   #if !isempty(filter(x->!isa(x, Int),
   #                   intersect(colnames(I), colnames(d))))
   #    error("All column names, including index and data columns, must be distinct")
   #end
    if !isconcretetype(eltype(d)) || fieldcount(eltype(d)) !== 0
        length(I) == length(d) ||
            error("index and data must have the same number of elements")
    end

    if !presorted && !issorted(I)
        p = sortperm(I)
        I = I[p]
        d = d[p]
    elseif copy
        if agg !== nothing
            iter = GroupReduce(agg, I, d, Base.OneTo(length(I)))
            I, d = collect_columns(iter).columns
            agg = nothing
        else
            I = Base.copy(I)
            d = Base.copy(d)
        end
    end
    stripnames(x) = isa(x, Columns) ? rows(astuple(columns(x))) : rows((x,))
    _table = convert(NextTable, I, stripnames(d); presorted=true, copy=false)
    nd = NDSparse{eltype(d),astuple(eltype(I)),typeof(I),typeof(d)}(
        I, d, _table, similar(I,0), similar(d,0)
    )
    agg===nothing || aggregate!(agg, nd)
    return nd
end

function ndsparse(x::AbstractVector, y; kwargs...)
    ndsparse((x,), y; kwargs...)
end

function ndsparse(x::Tup, y::Columns; kwargs...)
    ndsparse(x, columns(y); kwargs...)
end

function ndsparse(x::Columns, y::AbstractVector; kwargs...)
    ndsparse(columns(x), y; kwargs...)
end

ndsparse(c::Columns{<:Pair}; kwargs...) =
    convert(NDSparse, c.columns.first, c.columns.second; kwargs...)

# backwards compat
NDSparse(idx::Columns, data; kwargs...) = ndsparse(idx, data; kwargs...)

# Easy constructor to create a derivative table
function ndsparse(t::NDSparse; presorted=true, copy=false)
    ndsparse(keys(t), values(t), presorted=presorted, copy=copy)
end

# TableLike API
Base.@pure function colnames(t::NDSparse)
    dnames = colnames(t.data)
    if all(x->isa(x, Integer), dnames)
        dnames = map(x->x+ncols(t.index), dnames)
    end
    (colnames(t.index)..., dnames...,)
end

columns(nd::NDSparse) = concat_tup(columns(nd.index), columns(nd.data))

# IndexedTableLike API

permcache(t::NDSparse) = permcache(t._table)
cacheperm!(t::NDSparse, p) = cacheperm!(t._table, p)

"""
    pkeynames(t::NDSparse)

Names of the primary key columns in `t`.

# Example

```jldoctest

julia> x = ndsparse([1,2],[3,4])
1-d NDSparse with 2 values (Int64):
1 │
──┼──
1 │ 3
2 │ 4

julia> pkeynames(x)
(1,)

```
"""
pkeynames(t::NDSparse) = (dimlabels(t)...,)

# For an NDSparse, valuenames is either a tuple of fieldnames or a
# single name for scalar values
function valuenames(t::NDSparse)
    if isa(values(t), Columns)
        T = eltype(values(t))
        ((ndims(t) .+ (1:fieldcount(eltype(values(t)))))...,)
    else
        ndims(t) + 1
    end
end


"""
`NDSparse(columns...; names=Symbol[...], kwargs...)`

Construct an NDSparse array from columns. The last argument is the data column, and the rest are index columns. The `names` keyword argument optionally specifies names for the index columns (dimensions).
"""
function NDSparse(columns...; names=nothing, rest...)
    keys, data = columns[1:end-1], columns[end]
    ndsparse(Columns(keys..., names=names), data; rest...)
end

similar(t::NDSparse) = NDSparse(similar(t.index, 0), similar(t.data, 0))

function copy(t::NDSparse)
    flush!(t)
    NDSparse(copy(t.index), copy(t.data), presorted=true)
end

function (==)(a::NDSparse, b::NDSparse)
    flush!(a); flush!(b)
    return a.index == b.index && a.data == b.data
end

function Base.isequal(a::NDSparse, b::NDSparse)
    flush!(a); flush!(b)
    return isequal(keys(a), keys(b)) && isequal(values(a), values(b))
end

function empty!(t::NDSparse)
    empty!(t.index)
    empty!(t.data)
    empty!(t.index_buffer)
    empty!(t.data_buffer)
    return t
end

_convert(::Type{<:Tuple}, tup::Tuple) = tup
_convert(::Type{T}, tup::Tuple) where {T<:NamedTuple} = T(tup)
convertkey(t::NDSparse{V,K,I}, tup::Tuple) where {V,K,I} = _convert(eltype(I), tup)

ndims(t::NDSparse) = length(t.index.columns)
length(t::NDSparse) = (flush!(t);length(t.index))
eltype(::Type{NDSparse{T,D,C,V}}) where {T,D,C,V} = T
Base.keytype(::Type{NDSparse{T,D,C,V}}) where {T,D,C,V} = D
Base.keytype(x::NDSparse) = keytype(typeof(x))
dimlabels(::Type{NDSparse{T,D,C,V}}) where {T,D,C,V} = fieldnames(eltype(C))

# Generic ndsparse constructor that also works with distributed
# arrays in JuliaDB

Base.@deprecate itable(x, y) ndsparse(x, y)

# Keys and Values iterators

keys(t::NDSparse) = t.index
"""
`keys(x::NDSparse[, select::Selection])`

Get the keys of an `NDSparse` object. Same as [`rows`](@ref) but acts only on the index columns of the `NDSparse`.
"""
keys(t::NDSparse, which...) = rows(keys(t), which...)

# works for both NextTable and NDSparse
pkeys(t::NDSparse, which...) = keys(t, which...)

values(t::NDSparse) = t.data
"""
`values(x::NDSparse[, select::Selection])`

Get the values of an `NDSparse` object. Same as [`rows`](@ref) but acts only on the value columns of the `NDSparse`.
"""
function values(t::NDSparse, which...)
    if values(t) isa Columns
        rows(values(t), which...)
    else
        if which[1] != 1
            error("column $which not found")
        end
        values(t)
    end
end

## Some array-like API

"""
`dimlabels(t::NDSparse)`

Returns an array of integers or symbols giving the labels for the dimensions of `t`.
`ndims(t) == length(dimlabels(t))`.
"""
dimlabels(t::NDSparse) = dimlabels(typeof(t))

iterate(a::NDSparse) = iterate(a.data)
iterate(a::NDSparse, st) = iterate(a.data, st)

function permutedims(t::NDSparse, p::AbstractVector)
    if !(length(p) == ndims(t) && isperm(p))
        throw(ArgumentError("argument to permutedims must be a valid permutation"))
    end
    flush!(t)
    NDSparse(Columns(t.index.columns[p]), t.data, copy=true)
end

# showing

import Base.show
function show(io::IO, t::NDSparse{T,D}) where {T,D}
    flush!(t)
    if !(values(t) isa Columns)
        cnames = colnames(keys(t))
        eltypeheader = "$(eltype(t))"
    else
        cnames = colnames(t)
        nf = fieldcount(eltype(t))
        if eltype(t) <: NamedTuple
            eltypeheader = "$(nf) field named tuples"
        else
            eltypeheader = "$(nf)-tuples"
        end
    end
    header = "$(ndims(t))-d NDSparse with $(length(t)) values (" * eltypeheader * "):"
    showtable(io, t; header=header,
              cnames=cnames, divider=length(columns(keys(t))))
end

function showmeta(io, t::NDSparse, cnames)
    nc = length(columns(t))
    nidx = length(columns(keys(t)))
    nkeys = length(columns(values(t)))

    print(io,"    ")
    printstyled(io, "Dimensions", color=:underline)
    metat = Columns(([1:nidx;], [Text(get(cnames, i, "<noname>")) for i in 1:nidx],
                     eltype.([columns(keys(t))...])))
    showtable(io, metat, cnames=["#", "colname", "type"], cstyle=fill(:bold, nc), full=true)
    print(io,"\n    ")
    printstyled(io, "Values", color=:underline)
    if isa(values(t), Columns)
        metat = Columns(([nidx+1:nkeys+nidx;], [Text(get(cnames, i, "<noname>")) for i in nidx+1:nkeys+nidx],
                         eltype.(Any[columns(values(t))...])))
        showtable(io, metat, cnames=["#", "colname", "type"], cstyle=fill(:bold, nc), full=true)
    else
        show(io, eltype(values(t)))
    end
end

@noinline convert(::Type{NDSparse}, @nospecialize(ks), @nospecialize(vs); kwargs...) = ndsparse(ks, vs; kwargs...)
@noinline convert(T::Type{NDSparse}, c::Columns{<:Pair}; kwargs...) = convert(T, c.columns.first, c.columns.second; kwargs...)

# map and convert

"""
    map(f, x::NDSparse; select)

Apply `f` to every data value in `x`. `select` selects fields
passed to `f`. By default, the data values are selected.

If the return value of `f` is a tuple or named tuple the result
will contain many data columns.

# Examples

```jldoctest
julia> x = ndsparse(@NT(t=[0.01, 0.05]), @NT(x=[1,2], y=[3,4]))
1-d NDSparse with 2 values (2 field named tuples):
t    │ x  y
─────┼─────
0.01 │ 1  3
0.05 │ 2  4

julia> manh = map(row->row.x + row.y, x)
1-d NDSparse with 2 values (Int64):
t    │
─────┼──
0.01 │ 4
0.05 │ 6

julia> vx = map(row->row.x/row.t, x, select=(:t,:x))
1-d NDSparse with 2 values (Float64):
t    │
─────┼──────
0.01 │ 100.0
0.05 │ 40.0

julia> polar = map(p->@NT(r=hypot(p.x + p.y), θ=atan2(p.y, p.x)), x)
1-d NDSparse with 2 values (2 field named tuples):
t    │ r    θ
─────┼─────────────
0.01 │ 4.0  1.24905
0.05 │ 6.0  1.10715

julia> map(sin, polar, select=:θ)
1-d NDSparse with 2 values (Float64):
t    │
─────┼─────────
0.01 │ 0.948683
0.05 │ 0.894427

```
"""
function map(f, x::NDSparse; select=x.data)
    ndsparse(copy(x.index), map_rows(f, rows(x, select)),
             presorted=true, copy=false)
end

# """
# `columns(x::NDSparse, names...)`
#
# Given an NDSparse array with multiple data columns (its data vector is a `Columns` object), return a
# new array with the specified subset of data columns. Data is shared with the original array.
# """
# columns(x::NDSparse, which...) = NDSparse(x.index, Columns(x.data.columns[[which...]]), presorted=true)

#columns(x::NDSparse, which) = NDSparse(x.index, x.data.columns[which], presorted=true)

#column(x::NDSparse, which) = columns(x, which)

# NDSparse uses lex order, Base arrays use colex order, so we need to
# reorder the data. transpose and permutedims are used for this.
function convert(::Type{NDSparse}, m::SparseMatrixCSC)
    A = transpose(m)
    nzidx = findall(!iszero, A)
    I,J,V = getindex.(nzidx, 1), getindex.(nzidx, 2), A[nzidx]
    NDSparse(J, I, V, presorted=true)
end

# special method to allow selection on
# ndsparse with repeating names in keys and values
function column(x::NDSparse, which::Integer)
    @assert which > 0
    if which <= ndims(x)
        keys(x, which)
    else
        values(x, which-ndims(x))
    end
end

function convert(::Type{NDSparse}, a::AbstractArray{T}) where T
    n = length(a)
    nd = ndims(a)
    a = permutedims(a, [nd:-1:1;])
    data = reshape(a, (n,))
    idxs = [ Vector{Int}(undef, n) for i = 1:nd ]
    i = 1
    for I in CartesianIndices(size(a))
        for j = 1:nd
            idxs[j][i] = I[j]
        end
        i += 1
    end
    NDSparse(Columns(reverse(idxs)...), data, presorted=true)
end

# aggregation

"""
`aggregate!(f::Function, arr::NDSparse)`

Combine adjacent rows with equal indices using the given 2-argument reduction function,
in place.
"""
function aggregate!(f, x::NDSparse)
    idxs, data = x.index, x.data
    n = length(idxs)
    newlen = 0
    i1 = 1
    while i1 <= n
        val = data[i1]
        i = i1+1
        while i <= n && roweq(idxs, i, i1)
            val = f(val, data[i])
            i += 1
        end
        newlen += 1
        if newlen != i1
            copyrow!(idxs, newlen, i1)
        end
        data[newlen] = val
        i1 = i
    end
    resize!(idxs, newlen)
    resize!(data, newlen)
    x
end

function subtable(x::NDSparse, idx; presorted=true)
    ndsparse(keys(x)[idx], values(x)[idx], presorted=presorted, copy=false)
end
