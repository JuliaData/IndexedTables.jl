module NDSparseData

import Base:
    show, summary, eltype, length, sortperm, issorted, permute!, sort!,
    getindex, setindex!, ndims, eachindex, size, union, intersect, map, convert,
    linearindexing, ==, broadcast, broadcast!, empty!, copy, similar, sum, merge,
    permutedims

export NDSparse, Indexes, WithDefault, flush!, merge, intersect, aggregate!,
    convertdim

include("utils.jl")

immutable Indexes{D<:Tuple, C<:Tuple} <: AbstractVector{D}
    columns::C
end
Indexes(columns::AbstractVector...) =
    Indexes{eltypes(typeof(columns)),typeof(columns)}(columns)

eltype{D,C}(::Type{Indexes{D,C}}) = D
dimensions{D,C}(::Type{Indexes{D,C}}) = D
length(c::Indexes) = length(c.columns[1])
ndims(c::Indexes) = length(c.columns)
size(c::Indexes) = (length(c),)
linearindexing{T<:Indexes}(::Type{T}) = Base.LinearFast()
summary{D<:Tuple}(c::Indexes{D}) = "Indexes{$D}"

empty!(c::Indexes) = (map(empty!, c.columns); c)
similar(c::Indexes) = empty!(Indexes(map(similar, c.columns)...))
copy(c::Indexes) = Indexes(map(copy, c.columns)...)

@inline ith_all(i, ::Tuple{}) = ()
@inline ith_all(i, as) = (as[1][i], ith_all(i, tail(as))...)

row(c::Indexes, i) = ith_all(i, c.columns)
getindex(c::Indexes, i) = row(c, i)

@inline cmpelts(a, i, j) = (@inbounds x=cmp(a[i], a[j]); x)

@generated function rowless{D,C}(c::Indexes{D,C}, i, j)
    N = length(C.parameters)
    ex = :(cmpelts(c.columns[$N], i, j) < 0)
    for n in N-1:-1:1
        ex = quote
            let d = cmpelts(c.columns[$n], i, j)
                (d == 0) ? ($ex) : (d < 0)
            end
        end
    end
    ex
end

function ==(x::Indexes, y::Indexes)
    ndims(x) == ndims(y) || return false
    n = length(x)
    length(y) == n || return false
    for i in 1:n
        row(x,i) == row(y,i) || return false
    end
    return true
end

sortperm(c::Indexes) = sort!([1:length(c);], lt=(x,y)->rowless(c, x, y), alg=MergeSort)
issorted(c::Indexes) = issorted(1:length(c), lt=(x,y)->rowless(c, x, y))

function permute!(c::Indexes, p::AbstractVector)
    for v in c.columns
        permute!(v, p)
    end
    return c
end
sort!(c::Indexes) = permute!(c, sortperm(c))

immutable NDSparse{T, D<:Tuple, C<:Tuple, V<:AbstractVector}
    indexes::Indexes{D,C}
    data::V
    default::T

    index_buffer::Indexes{D,C}
    data_buffer::V
end

NDSparse(i::Indexes, d::AbstractVector, dflt) =
    NDSparse(i, d, dflt, Indexes(map(c->similar(c, 0), i.columns)...), similar(d, 0))

similar(t::NDSparse) =
    NDSparse(similar(t.indexes), empty!(similar(t.data)), copy(t.default))

function copy(t::NDSparse)
    flush!(t)
    NDSparse(copy(t.indexes), copy(t.data), copy(t.default))
end

function (==)(a::NDSparse, b::NDSparse)
    flush!(a); flush!(b)
    return a.indexes == b.indexes && a.data == b.data
end

function empty!(t::NDSparse)
    empty!(t.indexes)
    empty!(t.data)
    empty!(t.index_buffer)
    empty!(t.data_buffer)
    return t
end

if isless(Base.VERSION, v"0.5.0-")
writemime(io::IO, m::MIME"text/plain", t::NDSparse) = show(io, t)
end
showarray(io::IO, t::NDSparse) = show(io, t)

function show{T,D<:Tuple}(io::IO, t::NDSparse{T,D})
    flush!(t)
    print(io, "NDSparse{$T,$D}:")
    n = length(t.indexes)
    for i in 1:min(n,10)
        println(io)
        print(io, " $(row(t.indexes, i)) => $(t.data[i])")
    end
    if n > 20
        println(); print(" ⋮")
        for i in (n-9):n
            println(io)
            print(io, " $(row(t.indexes, i)) => $(t.data[i])")
        end
    end
end

immutable WithDefault{T}
    data::Vector{T}
    default::T
end

function NDSparse(columns...)
    keys = columns[1:end-1]
    data = columns[end]
    if isa(data, WithDefault)
        dflt = data.default
        data = data.data
    else
        dflt = zero(eltype(data))
    end
    n = length(data)
    for col in keys
        length(col) == n || error("all columns must have same length")
    end
    indexes = Indexes(keys...)
    if !issorted(indexes)
        p = sortperm(indexes)
        permute!(indexes, p)
        permute!(data, p)
    end
    NDSparse(indexes, data, dflt)
end

ndims(t::NDSparse) = ndims(t.indexes)
dimensions(t::NDSparse) = dimensions(t.indexes)
length(t::NDSparse) = (flush!(t);length(t.indexes))
eltype{T,D,C}(::Type{NDSparse{T,D,C}}) = T

start(a::NDSparse) = start(a.data)
next(a::NDSparse, st) = next(a.data, st)
done(a::NDSparse, st) = done(a.data, st)

function sort!(t::NDSparse)
    p = sortperm(t.indexes)
    permute!(t.indexes, p)
    permute!(t.data, p)
    return t
end

function permutedims(t::NDSparse, p::AbstractVector)
    flush!(t)
    cols = t.indexes.columns[p]
    inew = Indexes(cols...)
    ip = sortperm(inew)
    NDSparse(Indexes(map(c->c[ip], cols)...), t.data[ip], t.default)
end

# getindex

getindex(t::NDSparse, idxs...) = (flush!(t); _getindex(t, idxs))

_getindex{T,D<:Tuple}(t::NDSparse{T,D}, idxs::D) = _getindex_scalar(t, idxs)
_getindex(t::NDSparse, idxs::Tuple{Vararg{Real}}) = _getindex_scalar(t, idxs)

function _getindex_scalar(t, idxs)
    i = searchsorted(t.indexes, idxs)
    length(i) != 1 && return t.default
    t.data[first(i)]
end

_in(x, y) = in(x, y)
_in(x, ::Colon) = true
_in(x, v::AbstractVector) = (idx=searchsortedfirst(v, x); idx<=length(v) && v[idx]==x)
_in(x, v::AbstractString) = x == v
_in(x, v::Dimension) = x == v

import Base: tail
# test whether row r is within product(idxs...)
#row_in(r::Tuple{}, idxs) = true
row_in(r, idxs) = row_in(r[1], idxs[1], tail(r), tail(idxs))
@inline row_in(r1, i1, rr, ri) = _in(r1,i1) & row_in(rr[1], ri[1], tail(rr), tail(ri))
@inline row_in(r1, i1, rr::Tuple{}, ri) = _in(r1,i1)

function countunique(C)
    seen = Set{eltype(C)}()
    for x in C
        push!(seen, x)
    end
    length(seen)
end

length_estimate(col, idx::AbstractArray) = length(idx)
length_estimate(col, idx) = 1
length_estimate(col, idx::Colon) = 1
function length_estimate(col, idx::Interval)
    count = 0
    for i = 1:length(col)
        x = col[i]
        if i>1 && isless(x,col[i-1])
            break
        end
        if x in idx
            count += 1
        end
    end
    return max(1,count)
end

# TODO: `countunique` gives a better size estimate but takes quite a while
#    countunique(t.indexes.columns[n])
idxlen(t::NDSparse, n::Integer, i1, irest...) =
    length_estimate(t.indexes.columns[n],i1) * idxlen(t, n+1, irest...)
idxlen(t::NDSparse, n::Integer) = 1
idxlen(t::NDSparse, idxs) = idxlen(t, 1, idxs...)

range_estimate(col, idx) = 1:length(col)
range_estimate(col, idx::AbstractArray) = searchsortedfirst(col,first(idx)):searchsortedlast(col,last(idx))

pushrow!(I::Indexes, r) = _pushrow!(I.columns[1], r[1], tail(I.columns), tail(r))
@inline _pushrow!(c1, r1, cr, rr) = (push!(c1, r1); _pushrow!(cr[1], rr[1], tail(cr), tail(rr)))
@inline _pushrow!(c1, r1, cr::Tuple{}, rr) = push!(c1, r1)

# sizehint, making sure to return first argument
_sizehint!{T}(a::Array{T,1}, n::Integer) = (sizehint!(a, n); a)
_sizehint!(a::AbstractArray, sz::Integer) = a

function _getindex(t::NDSparse, idxs)
    I = t.indexes
    if length(idxs) != length(I.columns)
        error("wrong number of indexes")
    end
    for idx in idxs
        isa(idx, AbstractVector) && (issorted(idx) || error("indexes must be sorted for ranged/vector indexing"))
    end
    out = convert(Vector{Int32}, range_estimate(I.columns[1], idxs[1]))
    filter!(i->row_in(I[i], idxs), out)
    NDSparse(Indexes(map(x->x[out], I.columns)...), t.data[out], t.default)
end

# setindex!

setindex!(t::NDSparse, rhs, idxs...) = _setindex!(t, rhs, idxs)

_setindex!{T,D}(t::NDSparse{T,D}, rhs::AbstractArray, idxs::D) = _setindex_scalar!(t, rhs, idxs)
_setindex!(t::NDSparse, rhs::AbstractArray, idxs::Tuple{Vararg{Real}}) = _setindex_scalar!(t, rhs, idxs)
_setindex!{T,D}(t::NDSparse{T,D}, rhs, idxs::D) = _setindex_scalar!(t, rhs, idxs)
#_setindex!(t::NDSparse, rhs, idxs::Tuple{Vararg{Real}}) = _setindex_scalar!(t, rhs, idxs)

function _setindex_scalar!(t, rhs, idxs)
    pushrow!(t.index_buffer, idxs)
    push!(t.data_buffer, rhs)
    t
end

_setindex!(t::NDSparse, rhs::NDSparse, idxs::Tuple{Vararg{Real}}) = _setindex!(t, rhs.data, idxs)
_setindex!(t::NDSparse, rhs::NDSparse, idxs) = _setindex!(t, rhs.data, idxs)

@inline function fixi(t::NDSparse, n::Int, i1::Colon, irest...)
    u = unique(t.indexes.columns[n])
    (n==1 ? u : sort(u), fixi(t, n+1, irest...)...)
end

fixi(t::NDSparse, n::Int, i1, irest...) = (i1, fixi(t, n+1, irest...)...)
fixi(t::NDSparse, n::Int) = ()
fixi(t::NDSparse, idxs) = fixi(t, 1, idxs...)

_setindex!{T,D}(t::NDSparse{T,D}, rhs::AbstractArray, idxs) =
    _setindex_array_range!(t, rhs, fixi(t, idxs))

function _setindex_array_range!{T,D}(t::NDSparse{T,D}, rhs::AbstractArray, idxs)
    # TODO performance
    for (x,I) in zip(rhs,product(idxs...))
        _setindex!(t, x, convert(D, I))
    end
end

function _setindex!{T,D}(t::NDSparse{T,D}, rhs, idxs)
    # TODO performance
    for I in product(idxs...)
        _setindex!(t, rhs, convert(D, I))
    end
end

# sort and merge data from accumulation buffer
function flush!(t::NDSparse)
    if !isempty(t.data_buffer)
        # 1. sort the buffer
        p = sortperm(t.index_buffer)
        permute!(t.index_buffer, p)
        permute!(t.data_buffer, p)

        # 2. merge to a new copy
        new = _merge(t, NDSparse(t.index_buffer, t.data_buffer, t.default))

        # 3. resize and copy data into t
        for i = 1:length(t.indexes.columns)
            resize!(t.indexes.columns[i], length(new.indexes.columns[i]))
            copy!(t.indexes.columns[i], new.indexes.columns[i])
        end
        resize!(t.data, length(new.data))
        copy!(t.data, new.data)

        # 4. clear buffer
        for c in t.index_buffer.columns; empty!(c); end
        empty!(t.data_buffer)
    end
    nothing
end

function union{D}(I::Indexes{D}, J::Indexes{D})
    lI, lJ = length(I), length(J)
    guess = max(lI, lJ)
    K = Indexes(map(c->_sizehint!(similar(c,0),guess), I.columns)...)::typeof(I)
    i = j = 1
    while true
        if i <= lI && j <= lJ
            ri, rj = I[i], J[j]
            c = cmp(ri, rj)
            if c == 0
                pushrow!(K, ri)
                i += 1
                j += 1
            elseif c < 0
                pushrow!(K, ri)
                i += 1
            else
                pushrow!(K, rj)
                j += 1
            end
        elseif i <= lI
            pushrow!(K, I[i])
            i += 1
        elseif j <= lJ
            pushrow!(K, J[j])
            j += 1
        else
            break
        end
    end
    return K
end

function intersect{D}(I::Indexes{D}, J::Indexes{D})
    lI, lJ = length(I), length(J)
    guess = min(lI, lJ)
    K = Indexes(map(c->_sizehint!(similar(c,0),guess), I.columns)...)::typeof(I)
    i = j = 1
    while i <= lI && j <= lJ
        ri, rj = I[i], J[j]
        c = cmp(ri, rj)
        if c == 0
            pushrow!(K, ri)
            i += 1
            j += 1
        elseif c < 0
            i += 1
        else
            j += 1
        end
    end
    return K
end

# assign y into x out-of-place
merge{T,S,D}(x::NDSparse{T,D}, y::NDSparse{S,D}) = (flush!(x);flush!(y); _merge(x, y))
# merge without flush!
function _merge{T,S,D}(x::NDSparse{T,D}, y::NDSparse{S,D})
    K = union(x.indexes, y.indexes)
    n = length(K)
    lx, ly = length(x.indexes), length(y.indexes)
    dflt = x.default
    data = similar(x.data, n)
    i = j = 1
    for k = 1:n
        r = K[k]
        if j <= ly && r == y.indexes[j]
            data[k] = y.data[j]
            j += 1
            if i <= lx && r == x.indexes[i]
                i += 1
            end
        elseif i <= lx
            data[k] = x.data[i]
            i += 1
        end
    end
    NDSparse(K, data, dflt)
end

function map{T,S,D}(f, x::NDSparse{T,D}, y::NDSparse{S,D})
    flush!(x); flush!(y)
    K = union(x.indexes, y.indexes)
    n = length(K)
    lx, ly = length(x.indexes), length(y.indexes)
    dflt = f(x.default, y.default)
    data = Vector{typeof(dflt)}(n)
    i = j = 1
    for k = 1:n
        r = K[k]
        xval, yval = x.default, y.default
        if i <= lx && r == x.indexes[i]
            xval = x.data[i]
            i += 1
        end
        if j <= ly && r == y.indexes[j]
            yval = y.data[j]
            j += 1
        end
        data[k] = f(xval, yval)
    end
    NDSparse(K, data, dflt)
end

map(f, x::NDSparse) = NDSparse(x.indexes, map(f, x.data), f(x.default))

tslice(t::Tuple, I) = ntuple(i->t[I[i]], length(I))

function match_indices(A::NDSparse, B::NDSparse)
    Ap = typeof(A).parameters[2].parameters
    Bp = typeof(B).parameters[2].parameters
    matches = zeros(Int, length(Ap))
    J = IntSet(1:length(Bp))
    for i = 1:length(Ap)
        for j in J
            if Ap[i] == Bp[j]
                matches[i] = j
                delete!(J, j)
                break
            end
        end
    end
    isempty(J) || error("unmatched source indices: $(collect(J))")
    tuple(matches...)
end

function broadcast!(f::Function, A::NDSparse, B::NDSparse, C::NDSparse)
    A.default == f(B.default, C.default) ||
        error("destination default value doesn't match")
    flush!(A); flush!(B); flush!(C)
    B_inds = match_indices(A, B)
    C_inds = match_indices(A, C)
    all(i->B_inds[i] > 0 || C_inds[i] > 0, 1:ndims(A)) ||
        error("some destination indices are uncovered")
    common = filter(i->B_inds[i] > 0 && C_inds[i] > 0, 1:ndims(A))
    B_common = tslice(B_inds, common)
    C_common = tslice(C_inds, common)
    B_perm = sortperm(Indexes(B.indexes.columns[[B_common...]]...))
    C_perm = sortperm(Indexes(C.indexes.columns[[C_common...]]...))
    empty!(A)
    m, n = length(B_perm), length(C_perm)
    jlo = klo = 1
    while jlo <= m && klo <= n
        b_common = tslice(B.indexes[B_perm[jlo]], B_common)
        c_common = tslice(C.indexes[C_perm[klo]], C_common)
        x = cmp(b_common, c_common)
        x < 0 && (jlo += 1; continue)
        x > 0 && (klo += 1; continue)
        jhi, khi = jlo + 1, klo + 1
        while jhi <= m && tslice(B.indexes[B_perm[jhi]], B_common) == b_common
            jhi += 1
        end
        while khi <= n && tslice(C.indexes[C_perm[khi]], C_common) == c_common
            khi += 1
        end
        for ji = jlo:jhi-1
            j = B_perm[ji]
            b_row = B.indexes[j]
            for ki = klo:khi-1
                k = C_perm[ki]
                c_row = C.indexes[k]
                vals = ntuple(ndims(A)) do i
                    B_inds[i] > 0 ? b_row[B_inds[i]] : c_row[C_inds[i]]
                end
                pushrow!(A.indexes, vals)
                push!(A.data, f(B.data[j], C.data[k]))
            end
        end
        jlo, klo = jhi, khi
    end
    sort!(A)
end

# TODO: allow B to subsume columns of A as well?

broadcast(f::Function, A::NDSparse, B::NDSparse) = broadcast!(f, similar(A), A, B)

broadcast(f::Function, x::NDSparse, y) = NDSparse(x.indexes, broadcast(f, x.data, y), f(x.default, y))
broadcast(f::Function, y, x::NDSparse) = NDSparse(x.indexes, broadcast(f, y, x.data), f(y, x.default))

convert(::Type{NDSparse}, m::SparseMatrixCSC) = NDSparse(findnz(m)[[2,1,3]]...)

function convert{T}(::Type{NDSparse}, a::AbstractArray{T}; default::T = zero(eltype(a)))
    n = 0
    for x in a; if x!=default; n+=1; end; end
    data = Vector{T}(n)
    nd = ndims(a)
    idxs = [ Vector{Int}(n) for i = 1:nd ]
    i = 1
    for I in CartesianRange(size(a))
        val = a[I]
        if val != default
            for j = 1:nd
                idxs[j][i] = I[j]
            end
            data[i] = val
            i += 1
        end
    end
    NDSparse(Indexes(reverse(idxs)...), data, default)
end

# combine adjacent rows with equal indexes using the given function
function aggregate!(f, x::NDSparse)
    idxs, data = x.indexes, x.data
    n = length(idxs)
    newlen = 1
    current = idxs[newlen]
    for i = 2:n
        if idxs[i] == current
            data[newlen] = f(data[newlen], data[i])
        else
            newlen += 1
            if newlen != i
                data[newlen] = data[i]
                for c in idxs.columns
                    c[newlen] = c[i]
                end
            end
            current = idxs[newlen]
        end
    end
    resize!(data, newlen)
    for c in idxs.columns
        resize!(c, newlen)
    end
    x
end

# convert dimension `d` of `x` using the given translation function.
# if the relation is many-to-one, aggregate with function `agg`
function convertdim(x::NDSparse, d::Int, xlat, agg=+)
    cols = x.indexes.columns
    d2 = map(xlat, cols[d])
    x2 = NDSparse(map(copy,cols[1:d-1])..., d2, map(copy,cols[d+1:end])..., copy(x.data))
    aggregate!(agg, x2)
end

convertdim(x::NDSparse, d::Int, xlat::Dict, agg=+) = convertdim(x, d, i->xlat[i], agg)

sum(x::NDSparse) = sum(x.data)

include("query.jl")

end # module
