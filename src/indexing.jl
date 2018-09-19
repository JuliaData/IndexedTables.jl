# getindex

getindex(t::NDSparse, idxs...) = (flush!(t); _getindex(t, idxs))

_getindex(t::NDSparse{T,D}, idxs::D) where {T,D<:Tuple} = _getindex_scalar(t, idxs)
_getindex(t::NDSparse, idxs::Tuple{Vararg{Real}}) = _getindex_scalar(t, idxs)

function _getindex_scalar(t, idxs)
    i = searchsorted(t.index, convertkey(t, idxs))
    length(i) != 1 && throw(KeyError(idxs))
    t.data[first(i)]
end

# branch instead of diagonal dispatch to avoid ambiguities
_in(x, y) = isa(x,typeof(y)) ? isequal(x, y) : in(x, y)
_in(x, ::Colon) = true
_in(x, v::AbstractVector) = (idx=searchsortedfirst(v, x); idx<=length(v) && v[idx]==x)
_in(x, v::AbstractString) = x == v
_in(x, v::Symbol) = x === v
_in(x, v::Number) = isequal(x, v)

import Base: tail
# test whether row r is within product(idxs...)
@inline row_in(cs, r::Integer, idxs) = _row_in(cs[1], r, idxs[1], tail(cs), tail(idxs))
@inline _row_in(c1, r, i1, rI, ri) = _in(c1[r],i1) & _row_in(rI[1], r, ri[1], tail(rI), tail(ri))
@inline _row_in(c1, r, i1, rI::Tuple{}, ri) = _in(c1[r],i1)

range_estimate(col, idx) = 1:length(col)
range_estimate(col::AbstractVector{T}, idx::T) where {T} = searchsortedfirst(col, idx):searchsortedlast(col,idx)
range_estimate(col, idx::AbstractArray) = searchsortedfirst(col,first(idx)):searchsortedlast(col,last(idx))
range_estimate(col::Columns, idx::AbstractArray) = searchsortedfirst(col,first(idx)):searchsortedlast(col,last(idx))

const _fwd = Base.Order.ForwardOrdering()

range_estimate(col, idx, lo, hi) = 1:length(col)
range_estimate(col::AbstractVector{T}, idx::T, lo, hi) where {T} =
    searchsortedfirst(col, idx, lo, hi, _fwd):searchsortedlast(col, idx, lo, hi, _fwd)
range_estimate(col, idx::AbstractArray, lo, hi) =
    searchsortedfirst(col, first(idx), lo, hi, _fwd):searchsortedlast(col, last(idx), lo, hi, _fwd)

isconstrange(col, idx) = false
isconstrange(col::AbstractVector{T}, idx::T) where {T} = true
isconstrange(col, idx::AbstractArray) = isequal(first(idx), last(idx))

function range_estimate(I::Columns, idxs)
    r = range_estimate(I.columns[1], idxs[1])
    i = 1; n = length(idxs)
    while i < n && isconstrange(I.columns[i], idxs[i])
        i += 1
        r = intersect(r, range_estimate(I.columns[i], idxs[i], first(r), last(r)))
    end
    return r
end

function _getindex(t::NDSparse, idxs)
    I = t.index
    cs = astuple(I.columns)
    if fieldcount(typeof(idxs)) !== fieldcount(typeof(I.columns))
        error("wrong number of indices")
    end
    for idx in idxs
        isa(idx, AbstractVector) && (issorted(idx) || error("indices must be sorted for ranged/vector indexing"))
    end
    out = convert(Vector{Int32}, range_estimate(I, idxs))
    filter!(i->row_in(cs, i, idxs), out)
    keepdims = filter(i->eltype(columns(t.index)[i]) != typeof(idxs[i]), 1:length(idxs))
    NDSparse(Columns(map(x->x[out], getsubfields(I.columns, keepdims))), t.data[out], presorted=true)
end

# iterators over indices - lazy getindex

"""
`where(arr::NDSparse, indices...)`

Returns an iterator over data items where the given indices match. Accepts the
same index arguments as `getindex`.
"""
function where(d::NDSparse, idxs::Vararg{Any,N}) where N
    I = d.index
    cs = astuple(I.columns)
    data = d.data
    rng = range_estimate(I, idxs)
    (data[i] for i in Iterators.Filter(r->row_in(cs, r, idxs), rng))
end

"""
`update!(f::Function, arr::NDSparse, indices...)`

Replace data values `x` with `f(x)` at each location that matches the given
indices.
"""
function update!(f::Union{Function,Type}, d::NDSparse, idxs::Vararg{Any,N}) where N
    I = d.index
    cs = astuple(I.columns)
    data = d.data
    rng = range_estimate(I, idxs)
    for r in rng
        if row_in(cs, r, idxs)
            data[r] = f(data[r])
        end
    end
    d
end

pairs(d::NDSparse) = (d.index[i]=>d.data[i] for i in 1:length(d))

"""
`pairs(arr::NDSparse, indices...)`

Similar to `where`, but returns an iterator giving `index=>value` pairs.
`index` will be a tuple.
"""
function pairs(d::NDSparse, idxs::Vararg{Any,N}) where N
    I = d.index
    cs = astuple(I.columns)
    data = d.data
    rng = range_estimate(I, idxs)
    (I[i]=>data[i] for i in Compat.Iterators.Filter(r->row_in(cs, r, idxs), rng))
end

# setindex!

setindex!(t::NDSparse, rhs, idxs...) = _setindex!(t, rhs, idxs)

# assigning to an explicit set of indices --- equivalent to merge!

setindex!(t::NDSparse, rhs, I::Columns) = setindex!(t, fill(rhs, length(I)), I) # TODO avoid `fill`

setindex!(t::NDSparse, rhs::AbstractVector, I::Columns) = merge!(t, NDSparse(I, rhs, copy=false))

# assigning a single item

_setindex!(t::NDSparse{T,D}, rhs::AbstractArray, idxs::D) where {T,D} = _setindex_scalar!(t, rhs, idxs)
_setindex!(t::NDSparse, rhs::AbstractArray, idxs::Tuple{Vararg{Real}}) = _setindex_scalar!(t, rhs, idxs)
_setindex!(t::NDSparse{T,D}, rhs, idxs::D) where {T,D} = _setindex_scalar!(t, rhs, idxs)
#_setindex!(t::NDSparse, rhs, idxs::Tuple{Vararg{Real}}) = _setindex_scalar!(t, rhs, idxs)

function _setindex_scalar!(t, rhs, idxs)
    push!(t.index_buffer, idxs)
    push!(t.data_buffer, rhs)
    t
end

# vector assignment: works like a left join

_setindex!(t::NDSparse, rhs::NDSparse, idxs::Tuple{Vararg{Real}}) = _setindex!(t, rhs.data, idxs)
_setindex!(t::NDSparse, rhs::NDSparse, idxs) = _setindex!(t, rhs.data, idxs)

function _setindex!(d::NDSparse{T,D}, rhs::AbstractArray, idxs) where {T,D}
    for idx in idxs
        isa(idx, AbstractVector) && (issorted(idx) || error("indices must be sorted for ranged/vector indexing"))
    end
    flush!(d)
    I = d.index
    data = d.data
    ll = length(I)
    p = product(idxs...)
    elem = iterate(p)
    elem === nothing && return d
    R, s = elem
    i = j = 1
    L = I[i]
    while i <= ll
        c = cmp(L, R)
        if c < 0
            i += 1
            L = I[i]
        elseif c == 0
            data[i] = rhs[j]
            i += 1
            L = I[i]
            j += 1
            elem = iterate(p, s)
            elem === nothing && break
            R, s = elem
        else
            j += 1
            elem = iterate(p, s)
            elem === nothing && break
            R, s = elem
        end
    end
    return d
end

# broadcast assignment of a single value into all matching locations

function _setindex!(d::NDSparse{T,D}, rhs, idxs) where {T,D}
    for idx in idxs
        isa(idx, AbstractVector) && (issorted(idx) || error("indices must be sorted for ranged/vector indexing"))
    end
    flush!(d)
    I = d.index
    cs = astuple(I.columns)
    data = d.data
    rng = range_estimate(I, idxs)
    for r in rng
        if row_in(cs, r, idxs)
            data[r] = rhs
        end
    end
    d
end

"""
`flush!(arr::NDSparse)`

Commit queued assignment operations, by sorting and merging the internal temporary buffer.
"""
function flush!(t::NDSparse)
    if !isempty(t.data_buffer)
        # 1. form sorted array of temp values, preferring values added later (`right`)
        temp = NDSparse(t.index_buffer, t.data_buffer, copy=false, agg=right)

        if any(isshared, _cols_tuple(keys(t)))
            t.index = copy(keys(t))
        end
        if any(isshared, _cols_tuple(values(t)))
            t.data = copy(values(t))
        end

        # 2. merge in
        _merge!(t, temp, right)

        # 3. clear buffer
        empty!(t.index_buffer)
        empty!(t.data_buffer)
    end
    nothing
end
