module IndexedTables

using Compat
using NamedTuples, PooledArrays

import Base:
    show, eltype, length, getindex, setindex!, ndims, map, convert, keys, values,
    ==, broadcast, empty!, copy, similar, sum, merge, merge!, mapslices,
    permutedims, reducedim, serialize, deserialize

export IndexedTable, flush!, aggregate!, aggregate_vec, where, pairs, convertdim, columns, column,
    update!, aggregate, reducedim_vec, dimlabels, withkeys, withvalues, as

const Tup = Union{Tuple,NamedTuple}
const DimName = Union{Int,Symbol}

include("utils.jl")
include("columns.jl")

immutable IndexedTable{T, D<:Tuple, C<:Tup, V<:AbstractVector}
    index::Columns{D,C}
    data::V

    index_buffer::Columns{D,C}
    data_buffer::V
end

Base.@deprecate_binding NDSparse IndexedTable

# optional, non-exported name
const Table = IndexedTable

"""
`IndexedTable(indices::Columns, data::AbstractVector; kwargs...)`

Construct an IndexedTable array with the given indices and data. Each vector in `indices` represents the index values for one dimension. On construction, the indices and data are sorted in lexicographic order of the indices.

Keyword arguments:

* `agg::Function`: If `indices` contains duplicate entries, the corresponding data items are reduced using this 2-argument function.
* `presorted::Bool`: If true, the indices are assumed to already be sorted and no sorting is done.
* `copy::Bool`: If true, the storage for the new array will not be shared with the passed indices and data. If false (the default), the passed arrays will be copied only if necessary for sorting. The only way to guarantee sharing of data is to pass `presorted=true`.
"""
function IndexedTable{T,D,C}(I::Columns{D,C}, d::AbstractVector{T}; agg=nothing, presorted=false, copy=false)
    length(I) == length(d) || error("index and data must have the same number of elements")
    # ensure index is a `Columns` that generates tuples
    dt = D
    if eltype(I) <: NamedTuple
        dt = eltypes(typeof((I.columns...,)))
        I = Columns{dt,C}(I.columns)
    end
    if !presorted && !issorted(I)
        p = sortperm(I)
        I = I[p]
        d = d[p]
    elseif copy
        if agg !== nothing
            I, d = aggregate_to(agg, I, d)
            agg = nothing
        else
            I = Base.copy(I)
            d = Base.copy(d)
        end
    end
    nd = IndexedTable{T,dt,C,typeof(d)}(I, d, similar(I,0), similar(d,0))
    agg===nothing || aggregate!(agg, nd)
    return nd
end

"""
`IndexedTable(columns...; names=Symbol[...], kwargs...)`

Construct an IndexedTable array from columns. The last argument is the data column, and the rest are index columns. The `names` keyword argument optionally specifies names for the index columns (dimensions).
"""
function IndexedTable(columns...; names=nothing, rest...)
    keys, data = columns[1:end-1], columns[end]
    IndexedTable(Columns(keys..., names=names), data; rest...)
end

similar(t::IndexedTable) = IndexedTable(similar(t.index, 0), similar(t.data, 0))

function copy(t::IndexedTable)
    flush!(t)
    IndexedTable(copy(t.index), copy(t.data), presorted=true)
end

function (==)(a::IndexedTable, b::IndexedTable)
    flush!(a); flush!(b)
    return a.index == b.index && a.data == b.data
end

function empty!(t::IndexedTable)
    empty!(t.index)
    empty!(t.data)
    empty!(t.index_buffer)
    empty!(t.data_buffer)
    return t
end

ndims(t::IndexedTable) = length(t.index.columns)
length(t::IndexedTable) = (flush!(t);length(t.index))
eltype{T,D,C,V}(::Type{IndexedTable{T,D,C,V}}) = T
dimlabels{T,D,C,V}(::Type{IndexedTable{T,D,C,V}}) = fieldnames(C)
@inline keys(t::IndexedTable) = t.index
@inline values(t::IndexedTable) = t.data
@inline keys(tbl::IndexedTable, col) = getfield(tbl.index.columns, col)
@inline values(tbl::IndexedTable, col) = getfield(tbl.data.columns, col)

firstkey(t::IndexedTable) = first(keys(t))
lastkey(t::IndexedTable) = last(keys(t))

function withvalues(f, tbl::IndexedTable)
    IndexedTable(tbl.index, f(tbl.data))
end

function withkeys(f, tbl::IndexedTable)
    IndexedTable(f(tbl.index), tbl.data)
end

"""
`dimlabels(t::IndexedTable)`

Returns an array of integers or symbols giving the labels for the dimensions of `t`.
`ndims(t) == length(dimlabels(t))`.
"""
dimlabels(t::IndexedTable) = dimlabels(typeof(t))

start(a::IndexedTable) = start(a.data)
next(a::IndexedTable, st) = next(a.data, st)
done(a::IndexedTable, st) = done(a.data, st)

function permutedims(t::IndexedTable, p::AbstractVector)
    if !(length(p) == ndims(t) && isperm(p))
        throw(ArgumentError("argument to permutedims must be a valid permutation"))
    end
    flush!(t)
    IndexedTable(Columns(t.index.columns[p]), t.data, copy=true)
end

# showing

if isless(Base.VERSION, v"0.5.0-")
writemime(io::IO, m::MIME"text/plain", t::IndexedTable) = show(io, t)
end

function show{T,D<:Tuple}(io::IO, t::IndexedTable{T,D})
    flush!(t)
    n = length(t)
    n == 0 && (return print(io, "empty table $D => $T"))
    rows = n > 20 ? [1:min(n,10); (n-9):n] : [1:n;]
    nc = length(t.index.columns)
    reprs  = [ sprint(io->showcompact(io,t.index.columns[j][i])) for i in rows, j in 1:nc ]
    if isa(t.data, Columns)
        dreprs = [ sprint(io->showcompact(io,t.data[i][j])) for i in rows, j in 1:nfields(eltype(t.data)) ]
    else
        dreprs = [ sprint(io->showcompact(io,t.data[i])) for i in rows ]
    end
    ndc = size(dreprs,2)
    inames = isa(t.index.columns, NamedTuple) ? map(string,keys(t.index.columns)) : fill("", nc)
    dnames = eltype(t.data) <: NamedTuple ? map(string,fieldnames(eltype(t.data))) : fill("", ndc)
    widths  = [ max(strwidth(inames[c]), maximum(map(strwidth, reprs[:,c]))) for c in 1:nc ]
    dwidths = [ max(strwidth(dnames[c]), maximum(map(strwidth, dreprs[:,c]))) for c in 1:ndc ]
    if isa(t.index.columns, NamedTuple) || (isa(t.data, Columns) && isa(t.data.columns, NamedTuple))
        for c in 1:nc
            print(io, rpad(inames[c], widths[c]+(c==nc ? 1 : 2), " "))
        end
        print(io, "│ ")
        for c in 1:ndc
            print(io, c==ndc ? dnames[c] : rpad(dnames[c], dwidths[c]+2, " "))
        end
        println(io)
        print(io, "─"^(sum(widths)+2*nc-1), "┼", "─"^(sum(dwidths)+2*ndc-1))
    else
        print(io, "─"^(sum(widths)+2*nc-1), "┬", "─"^(sum(dwidths)+2*ndc-1))
    end
    for r in 1:size(reprs,1)
        println(io)
        for c in 1:nc
            print(io, rpad(reprs[r,c], widths[c]+(c==nc ? 1 : 2), " "))
        end
        print(io, "│ ")
        for c in 1:ndc
            print(io, c==ndc ? dreprs[r,c] : rpad(dreprs[r,c], dwidths[c]+2, " "))
        end
        if n > 20 && r == 10
            println(io)
            print(io, " "^(sum(widths)+2*nc-1))
            print(io, "⋮")
        end
    end
end

@compat abstract type SerializedIndexedTable end

function serialize(s::AbstractSerializer, x::IndexedTable)
    flush!(x)
    Base.Serializer.serialize_type(s, SerializedIndexedTable)
    serialize(s, x.index)
    serialize(s, x.data)
end

function deserialize(s::AbstractSerializer, ::Type{SerializedIndexedTable})
    I = deserialize(s)
    d = deserialize(s)
    IndexedTable(I, d, presorted=true)
end

# map and convert

map(f, x::IndexedTable) = IndexedTable(copy(x.index), map(f, x.data), presorted=true)

# lift projection on arrays of structs
map{T,D<:Tuple,C<:Tup,V<:Columns}(p::Proj, x::IndexedTable{T,D,C,V}) =
    IndexedTable(x.index, p(x.data.columns), presorted=true)

(p::Proj)(x::IndexedTable) = map(p, x)

"""
`columns(x::IndexedTable, names...)`

Given an IndexedTable array with multiple data columns (its data vector is a `Columns` object), return a
new array with the specified subset of data columns. Data is shared with the original array.
"""
columns(x::IndexedTable, which...) = IndexedTable(x.index, Columns(x.data.columns[[which...]]), presorted=true)

columns(x::IndexedTable, which) = IndexedTable(x.index, x.data.columns[which], presorted=true)

column(x::IndexedTable, which) = columns(x, which)

# IndexedTable uses lex order, Base arrays use colex order, so we need to
# reorder the data. transpose and permutedims are used for this.
convert(::Type{IndexedTable}, m::SparseMatrixCSC) = IndexedTable(findnz(m.')[[2,1,3]]..., presorted=true)

function convert{T}(::Type{IndexedTable}, a::AbstractArray{T})
    n = length(a)
    nd = ndims(a)
    a = permutedims(a, [nd:-1:1;])
    data = reshape(a, (n,))
    idxs = [ Vector{Int}(n) for i = 1:nd ]
    i = 1
    for I in CartesianRange(size(a))
        for j = 1:nd
            idxs[j][i] = I[j]
        end
        i += 1
    end
    IndexedTable(Columns(reverse(idxs)...), data, presorted=true)
end

# getindex and setindex!
include("indexing.jl")

# joins
include("join.jl")

# query and aggregate
include("query.jl")

end # module
