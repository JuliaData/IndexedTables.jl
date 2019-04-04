abstract type AbstractNDSparse end

mutable struct NDSparse{T, D<:Tuple, C<:Columns, V<:AbstractVector} <: AbstractNDSparse
    index::C
    data::V
    _table::IndexedTable

    index_buffer::C
    data_buffer::V
end

function IndexedTable(nds::NDSparse; kwargs...)
    convert(IndexedTable, nds.index, nds.data; kwargs...)
end

convert(::Type{IndexedTable}, nd::NDSparse) = IndexedTable(nd)


"""
    ndsparse(keys, values; kw...)

Construct an NDSparse array with the given `keys` and `values` columns. On construction,
the keys and data are sorted in lexicographic order of the `keys`.

# Keyword Argument Options:

- `agg = nothing` -- Function to aggregate values with duplicate keys.
- `presorted = false` -- Are the key columns already sorted?
- `copy = true` -- Should the columns in `keys` and `values` be copied?
- `chunks = nothing` -- Provide an integer to distribute data into `chunks` chunks.
    - A good choice is `nworkers()` (after `using Distributed`)
    - See also: [`distribute`](@ref)

# Examples:

    x = ndsparse(["a","b"], [3,4])
    keys(x)
    values(x)
    x["a"]

    # Dimensions are named if constructed with a named tuple of columns
    x = ndsparse((index = 1:10,), rand(10))
    x[1]

    # Multiple dimensions by passing a (named) tuple of columns
    x = ndsparse((x = 1:10, y = 1:2:20), rand(10))
    x[1, 1]

    # Value columns can also have names via named tuples
    x = ndsparse(1:10, (x=rand(10), y=rand(10)))
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
            iter = igroupreduce(agg, I, d, Base.OneTo(length(I)))
            I, d = collect_columns(iter) |> columns
            agg = nothing
        else
            I = copyto!(similar(I), I)
            d = copyto!(similar(d), d)
        end
    end
    stripnames(x) = isa(x, Columns) ? rows(astuple(columns(x))) : rows((x,))
    _table = convert(IndexedTable, I, stripnames(d); presorted=true, copy=false)
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
    convert(NDSparse, columns(c).first, columns(c).second; kwargs...)

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

    x = ndsparse([1,2],[3,4])
    pkeynames(x)

    x = ndsparse((x=1:10, y=1:2:20), rand(10))
    pkeynames(x)
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
    ndsparse(Columns(keys, names=names), data; rest...)
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

ndims(t::NDSparse) = length(fieldarrays(t.index))
length(t::NDSparse) = (flush!(t);length(t.index))
eltype(::Type{NDSparse{T,D,C,V}}) where {T,D,C,V} = T
Base.keytype(::Type{NDSparse{T,D,C,V}}) where {T,D,C,V} = D
Base.keytype(x::NDSparse) = keytype(typeof(x))
dimlabels(::Type{NDSparse{T,D,C,V}}) where {T,D,C,V} = fieldnames(eltype(C))

# Generic ndsparse constructor that also works with distributed
# arrays in JuliaDB

# Keys and Values iterators

keys(t::NDSparse) = t.index
"""
`keys(x::NDSparse[, select::Selection])`

Get the keys of an `NDSparse` object. Same as [`rows`](@ref) but acts only on the index columns of the `NDSparse`.
"""
keys(t::NDSparse, which...) = rows(keys(t), which...)

# works for both IndexedTable and NDSparse
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
    NDSparse(Columns(columns(t.index)[p]), t.data, copy=true)
end

# showing
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
@noinline convert(T::Type{NDSparse}, c::Columns{<:Pair}; kwargs...) = convert(T, columns(c).first, columns(c).second; kwargs...)

# map and convert

"""
    map(f, x::NDSparse; select = values(x))

Apply `f` to every value of `select` selected from `x` (see [`select`](@ref)).

Apply `f` to every data value in `x`. `select` selects fields
passed to `f`. By default, the data values are selected.

If the return value of `f` is a tuple or named tuple the result will contain many data columns.

# Examples

    x = ndsparse((t=[0.01, 0.05],), (x=[1,2], y=[3,4]))

    polar = map(row -> (r = hypot(row.x, row.y), θ = atan(row.y, row.x)), x)

    back2x = map(row -> (x = row.r * cos(row.θ), y = row.r * sin(row.θ)), polar)
"""
function map(f, x::NDSparse; select=x.data)
    ndsparse(copy(x.index), map_rows(f, rows(x, select)), presorted=true, copy=false)
end

# """
# `columns(x::NDSparse, names...)`
#
# Given an NDSparse array with multiple data columns (its data vector is a `Columns` object), return a
# new array with the specified subset of data columns. Data is shared with the original array.
# """
# columns(x::NDSparse, which...) = NDSparse(x.index, Columns(columns(x.data)[[which...]]), presorted=true)

#columns(x::NDSparse, which) = NDSparse(x.index, columns(x.data)[which], presorted=true)

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
    NDSparse(Columns(Tuple(Iterators.reverse(idxs))), data, presorted=true)
end

# aggregation

"""
    aggregate!(f::Function, arr::NDSparse)

Combine adjacent rows with equal indices using the given 2-argument reduction function,
in place.
"""
function aggregate!(f, x::NDSparse)
    idxs, data = x.index, x.data
    n = length(idxs)
    newlen = 0
    for ii in GroupPerm(pool(idxs), Base.OneTo(n))
        newlen += 1
        if newlen != last(ii)
            copyrow!(idxs, newlen, last(ii))
            @inbounds data[newlen] = reduce(f, data[i] for i in ii)
        end
    end
    resize!(idxs, newlen)
    resize!(data, newlen)
    x
end

function subtable(x::NDSparse, idx; presorted=true)
    ndsparse(keys(x)[idx], values(x)[idx], presorted=presorted, copy=false)
end
