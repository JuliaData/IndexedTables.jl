module IndexedTables

using NamedTuples, PooledArrays

import Base:
    show, eltype, length, getindex, setindex!, ndims, map, convert,
    ==, broadcast, empty!, copy, similar, sum, merge, merge!,
    permutedims, reducedim, serialize, deserialize

export NDSparse, flush!, aggregate!, aggregate_vec, where, pairs, convertdim, columns, column,
    update!, aggregate, reducedim_vec

const Tup = Union{Tuple,NamedTuple}
const DimName = Union{Int,Symbol}

include("utils.jl")
include("columns.jl")

immutable NDSparse{T, D<:Tuple, C<:Tup, V<:AbstractVector}
    index::Columns{D,C}
    data::V

    index_buffer::Columns{D,C}
    data_buffer::V
end

"""
`NDSparse(indices::Columns, data::AbstractVector; kwargs...)`

Construct an NDSparse array with the given indices and data. Each vector in `indices` represents the index values for one dimension. On construction, the indices and data are sorted in lexicographic order of the indices.

Keyword arguments:

* `agg::Function`: If `indices` contains duplicate entries, the corresponding data items are reduced using this 2-argument function.
* `presorted::Bool`: If true, the indices are assumed to already be sorted and no sorting is done.
* `copy::Bool`: If true, the storage for the new array will not be shared with the passed indices and data. If false (the default), the passed arrays will be copied only if necessary for sorting. The only way to guarantee sharing of data is to pass `presorted=true`.
"""
function NDSparse{T<:AbstractVector, D,C}(I::Columns{D,C}, d::T; agg=nothing, presorted=false, copy=false)
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
    nd = NDSparse{eltype(T),dt,C,typeof(d)}(I, d, similar(I,0), similar(d,0))
    agg===nothing || aggregate!(agg, nd)
    return nd
end

"""
`NDSparse(columns...; names=Symbol[...], kwargs...)`

Construct an NDSparse array from columns. The last argument is the data column, and the rest are index columns. The `names` keyword argument optionally specifies names for the index columns (dimensions).
"""
function NDSparse(columns...; names=nothing, rest...)
    keys, data = columns[1:end-1], columns[end]
    keycols = Columns(keys..., names=names)
    @show typeof(keycols) typeof(data)
    @show rest
    NDSparse(keycols, data; rest...)
end

similar(t::NDSparse) = NDSparse(similar(t.index), empty!(similar(t.data)))

function copy(t::NDSparse)
    flush!(t)
    NDSparse(copy(t.index), copy(t.data), presorted=true)
end

function (==)(a::NDSparse, b::NDSparse)
    flush!(a); flush!(b)
    return a.index == b.index && a.data == b.data
end

function empty!(t::NDSparse)
    empty!(t.index)
    empty!(t.data)
    empty!(t.index_buffer)
    empty!(t.data_buffer)
    return t
end

ndims(t::NDSparse) = length(t.index.columns)
length(t::NDSparse) = (flush!(t);length(t.index))
eltype{T,D,C,V}(::Type{NDSparse{T,D,C,V}}) = T

start(a::NDSparse) = start(a.data)
next(a::NDSparse, st) = next(a.data, st)
done(a::NDSparse, st) = done(a.data, st)

function permutedims(t::NDSparse, p::AbstractVector)
    if !(length(p) == ndims(t) && isperm(p))
        throw(ArgumentError("argument to permutedims must be a valid permutation"))
    end
    flush!(t)
    NDSparse(Columns(t.index.columns[p]), t.data, copy=true)
end

# showing

if isless(Base.VERSION, v"0.5.0-")
writemime(io::IO, m::MIME"text/plain", t::NDSparse) = show(io, t)
end

function show{T,D<:Tuple}(io::IO, t::NDSparse{T,D})
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

function serialize(s::AbstractSerializer, x::NDSparse)
    flush!(x)
    Base.Serializer.serialize_type(s, NDSparse)
    serialize(s, x.index)
    serialize(s, x.data)
end

function deserialize(s::AbstractSerializer, ::Type{NDSparse})
    I = deserialize(s)
    d = deserialize(s)
    NDSparse(I, d, presorted=true)
end

# map and convert

map(f, x::NDSparse) = NDSparse(copy(x.index), map(f, x.data), presorted=true)

# lift projection on arrays of structs
map{T,D<:Tuple,C<:Tup,V<:Columns}(p::Proj, x::NDSparse{T,D,C,V}) =
    NDSparse(x.index, p(x.data), presorted=true)

(p::Proj)(x::NDSparse) = map(p, x)

"""
`columns(x::NDSparse, names...)`

Given an NDSparse array with multiple data columns (its data vector is a `Columns` object), return a
new array with the specified subset of data columns. Data is shared with the original array.
"""
columns(x::NDSparse, which...) = NDSparse(x.index, Columns(x.data.columns[[which...]]), presorted=true)

columns(x::NDSparse, which) = NDSparse(x.index, x.data.columns[which], presorted=true)

column(x::NDSparse, which) = columns(x, which)

# NDSparse uses lex order, Base arrays use colex order, so we need to
# reorder the data. transpose and permutedims are used for this.
convert(::Type{NDSparse}, m::SparseMatrixCSC) = NDSparse(findnz(m.')[[2,1,3]]..., presorted=true)

function convert{T}(::Type{NDSparse}, a::AbstractArray{T})
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
    NDSparse(Columns(reverse(idxs)...), data, presorted=true)
end

# getindex and setindex!
include("indexing.jl")

# joins
include("join.jl")

# query and aggregate
include("query.jl")

end # module
