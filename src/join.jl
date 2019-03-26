# Missing
nullrow(t::Type{<:Tuple}, ::Type{Missing}) = Tuple(map(x->missing, fieldtypes(t)))
nullrow(t::Type{<:NamedTuple}, ::Type{Missing}) = t(Tuple(map(x->missing, fieldtypes(t))))

# DataValue
nullrow(::Type{T}, ::Type{DataValue}) where {T <: Tuple} = Tuple(fieldtype(T, i)() for i = 1:fieldcount(T))
function nullrow(::Type{NamedTuple{names, T}}, ::Type{DataValue}) where {names, T}
    NamedTuple{names, T}(Tuple(fieldtype(T, i)() for i = 1:fieldcount(T)))
end

nullrow(T, M) = missing_instance(M)

nullrowtype(::Type{T}, ::Type{S}) where {T<:Tup, S} = map_params(t -> type2missingtype(t, S), T)
nullrowtype(::Type{T}, ::Type{S}) where {T, S} = type2missingtype(T, S)

nullablerows(s::Columns{C}, ::Type{S}) where {C, S} = Columns{nullrowtype(C, S)}(fieldarrays(s))
nullablerows(s::AbstractVector, ::Type{S}) where {S} = vec_missing(s, S)

function init_key_left_right(key::AbstractVector{K}, ldata::AbstractVector{L}, rdata::AbstractVector{R}) where {K, L, R}
    similar(arrayof(K), 0), similar(arrayof(L), 0), similar(arrayof(R), 0)
end

_reduce(f, iter, ::Nothing) = reduce(f, iter)
_reduce(f, iter, init_group) = reduce(f, iter, init = init_group())
_reduce(::Nothing, iter, ::Nothing) = collect_columns(iter)
_reduce(::Nothing, iter, init_group) = collect_columns(iter)

# In a plain non group join with f === concat_tup, we avoid creating large structs and prefer to do things in place
# In every step of the iteration, instead of just iterating we push the values to init
function _join!(init, ::Val{typ}, ::Val{grp}, f, iter::GroupJoinPerm, ldata::AbstractVector{L}, rdata::AbstractVector{R};
    missingtype=Missing, init_group=nothing, accumulate=nothing) where {typ, grp, L, R}

    lkey, rkey = parent(iter.left), parent(iter.right)
    lperm, rperm = sortperm(iter.left), sortperm(iter.right)
    lnullable = grp === false && typ === :outer
    rnullable = grp === false && typ !== :inner

    filter_func = if typ === :anti
        ((lidxs, ridxs),) -> !isempty(lidxs) && isempty(ridxs)
    elseif typ === :inner
        ((lidxs, ridxs),) -> !isempty(lidxs) && !isempty(ridxs)
    elseif typ === :left
        ((lidxs, _),) -> !isempty(lidxs)
    elseif typ === :outer
        _ -> true
    end

    function getkeyiter((lidxs, ridxs))
        key = isempty(lidxs) ? rkey[rperm[ridxs[1]]] : lkey[lperm[lidxs[1]]]
        liter = lnullable && isempty(lidxs) ? (nullrow(L, missingtype),) : (ldata[lperm[i]] for i in lidxs)
        riter = rnullable && isempty(ridxs) ? (nullrow(R, missingtype),) : (rdata[rperm[i]] for i in ridxs)
        if init === nothing
            joint_iter = (f(l, r) for (r, l) in Iterators.product(riter, liter))
            res = grp ? _reduce(accumulate, joint_iter, init_group) : joint_iter
            return key => res
        else
            Base.foreach(Iterators.product(riter, liter)) do (r, l)
                push!(init[1], key)
                push!(init[2], l)
                push!(init[3], r)
            end
            return
        end
    end
    filtered_iter = Iterators.filter(filter_func, iter)
    if init !== nothing
        Base.foreach(getkeyiter, filtered_iter)
        key, left, right = init
        data = Columns(concat_tup(columns(left), columns(right)))
        return Columns(key => data)
    else
        pair_iter = (getkeyiter(idxs) for idxs in filtered_iter)
        return grp === true ? collect_columns(pair_iter) : collect_columns_flattened(pair_iter)
    end
end

"""
    join(left, right; kw...)
    join(f, left, right; kw...)

Join tables `left` and `right`.

If a function `f(leftrow, rightrow)` is provided, the returned table will have a single
output column.  See the Examples below.

If the same key occurs multiple times in either table, each `left` row will get matched
with each `right` row, resulting in `n_occurrences_left * n_occurrences_right` output rows.

# Options (keyword arguments)

- `how = :inner`
    - Join method to use. Described below.
- `lkey = pkeys(left)`
    - Fields from `left` to match on (see [`pkeys`](@ref)).
- `rkey = pkeys(right)`
    - Fields from `right` to match on.
- `lselect = Not(lkey)`
    - Output columns from `left` (see [`Not`](@ref))
- `rselect = Not(rkey)`
    - Output columns from `right`.
- `missingtype = Missing`
    - Type of missing values that can be created through `:left` and `:outer` joins.
    - Other supported option is `DataValue`.

## Join methods (`how = :inner`)

- `:inner` -- rows with matching keys in both tables
- `:left` -- all rows from `left`, plus matched rows from `right` (missing values can occur)
- `:outer` -- all rows from both tables (missing values can occur)
- `:anti` -- rows in `left` WITHOUT matching keys in `right`

# Examples

    a = table((x = 1:10,   y = rand(10)), pkey = :x)
    b = table((x = 1:2:20, z = rand(10)), pkey = :x)

    join(a, b; how = :inner)
    join(a, b; how = :left)
    join(a, b; how = :outer)
    join(a, b; how = :anti)

    join((l, r) -> l.y + r.z, a, b)
"""
function Base.join(f, left::Dataset, right::Dataset;
                   how=:inner, group=false,
                   lkey=pkeynames(left), rkey=pkeynames(right),
                   lselect=isa(left, NDSparse) ?
                       valuenames(left) : excludecols(left, lkey),
                   rselect=isa(right, NDSparse) ?
                       valuenames(right) : excludecols(right, rkey),
                   name = nothing,
                   cache=true,
                   missingtype=Missing,
                   init_group=nothing,
                   accumulate=nothing)

    if !(how in [:inner, :left, :outer, :anti])
        error("Invalid how: supported join types are :inner, :left, :outer, and :anti")
    end
    lkey = lowerselection(left, lkey)
    rkey = lowerselection(right, rkey)

    if !isa(lkey, Tuple)
        lkey = (lkey,)
    end

    if !isa(rkey, Tuple)
        rkey = (rkey,)
    end

    lperm, lkey = sortpermby(left, lkey; cache=cache, return_keys=true)
    rperm, rkey = sortpermby(right, rkey; cache=cache, return_keys=true)

    lselect = lowerselection(left, lselect)
    rselect = lowerselection(right, rselect)
    if f === concat_tup
        if !isa(lselect, Tuple)
            lselect = (lselect,)
        end

        if !isa(rselect, Tuple)
            rselect = (rselect,)
        end
    end

    ldata = rows(left, lselect)
    rdata = rows(right, rselect)

    if !group
        (how == :outer) && (ldata = nullablerows(ldata, missingtype))
        (how == :inner) || (rdata = nullablerows(rdata, missingtype))
    end

    KT = map_params(promote_type, eltype(lkey), eltype(rkey))
    lkey = Columns{KT}(fieldarrays(lkey))
    rkey = Columns{KT}(fieldarrays(rkey))
    join_iter = GroupJoinPerm(GroupPerm(lkey, lperm), GroupPerm(rkey, rperm))
    init = !group && f === concat_tup ? init_key_left_right(lkey, ldata, rdata) : nothing
    typ, grp = Val{how}(), Val{group}()
    res = _join!(init, typ, grp, f, join_iter, ldata, rdata;
        missingtype=missingtype, init_group=init_group, accumulate=accumulate)
    isempty(res) && return res
    I, data = res.first, res.second
    if group && left isa IndexedTable && !(data isa Columns)
        data = Columns(groups=data)
    end
    convert(collectiontype(left), I, data, presorted=true, copy=false)
end

function Base.join(left::Dataset, right::Dataset; how=:inner, kwargs...)
    f = how === :anti ? (x,y) -> x : concat_tup
    join(f, left, right; how=how, kwargs...)
end

"""
    groupjoin(left, right; kw...)
    groupjoin(f, left, right; kw...)

Join `left` and `right` creating groups of values with matching keys.

For keyword argument options, see [`join`](@ref).

# Examples

    l = table([1,1,1,2], [1,2,2,1], [1,2,3,4], names=[:a,:b,:c], pkey=(:a, :b))
    r = table([0,1,1,2], [1,2,2,1], [1,2,3,4], names=[:a,:b,:d], pkey=(:a, :b))

    groupjoin(l, r)
    groupjoin(l, r; how = :left)
    groupjoin(l, r; how = :outer)
    groupjoin(l, r; how = :anti)
"""
function groupjoin(left::Dataset, right::Dataset; how=:inner, kwargs...)
    f = how === :anti ? (x,y) -> x : concat_tup
    groupjoin(f, left, right; how=how, kwargs...)
end

function groupjoin(f, left::Dataset, right::Dataset; how=:inner, kwargs...)
    join(f, left, right; group=true, how=how, kwargs...)
end

for (fn, how) in [:naturaljoin =>     (:inner, false, concat_tup),
                  :leftjoin =>        (:left,  false, concat_tup),
                  :outerjoin =>       (:outer, false, concat_tup),
                  :antijoin =>        (:anti,  false, (x, y) -> x),
                  :naturalgroupjoin =>(:inner, true, concat_tup),
                  :leftgroupjoin =>   (:left,  true, concat_tup),
                  :outergroupjoin =>  (:outer, true, concat_tup)]

    how, group, f = how

    @eval function $fn(f, left::Dataset, right::Dataset; kwargs...)
        join(f, left, right; group=$group, how=$(Expr(:quote, how)), kwargs...)
    end

    @eval function $fn(left::Dataset, right::Dataset; kwargs...)
        $fn($f, left, right; kwargs...)
    end
end

## Joins

const innerjoin = naturaljoin

map(f, x::NDSparse{T,D}, y::NDSparse{S,D}) where {T,S,D} = naturaljoin(f, x, y)

# asof join

"""
    asofjoin(left::NDSparse, right::NDSparse)

Join rows from `left` with the "most recent" value from `right`.

# Example

    using Dates
    akey1 = ["A", "A", "B", "B"]
    akey2 = [Date(2017,11,11), Date(2017,11,12), Date(2017,11,11), Date(2017,11,12)]
    avals = collect(1:4)

    bkey1 = ["A", "A", "B", "B"]
    bkey2 = [Date(2017,11,12), Date(2017,11,13), Date(2017,11,10), Date(2017,11,13)]
    bvals = collect(5:8)

    a = ndsparse((akey1, akey2), avals)
    b = ndsparse((bkey1, bkey2), bvals)

    asofjoin(a, b)
"""
function asofjoin(left::NDSparse, right::NDSparse)
    flush!(left); flush!(right)
    lI, rI = left.index, right.index
    lD, rD = left.data, right.data
    ll, rr = length(lI), length(rI)

    data = similar(lD)

    i = j = 1

    while i <= ll && j <= rr
        c = rowcmp(lI, i, rI, j)
        if c < 0
            @inbounds data[i] = lD[i]
            i += 1
        elseif row_asof(lI, i, rI, j)  # all equal except last col left>=right
            j += 1
            while j <= rr && row_asof(lI, i, rI, j)
                j += 1
            end
            j -= 1
            @inbounds data[i] = rD[j]
            i += 1
        else
            j += 1
        end
    end
    data[i:ll] = lD[i:ll]

    NDSparse(copy(lI), data, presorted=true)
end

# merge - union join

function count_overlap(I::Columns{D}, J::Columns{D}) where D
    lI, lJ = length(I), length(J)
    i = j = 1
    overlap = 0
    while i <= lI && j <= lJ
        c = rowcmp(I, i, J, j)
        if c == 0
            overlap += 1
            i += 1
            j += 1
        elseif c < 0
            i += 1
        else
            j += 1
        end
    end
    return overlap
end

function promoted_similar(x::Columns, y::Columns, n)
    Columns(map((a,b)->promoted_similar(a, b, n), columns(x), columns(y)))
end

function promoted_similar(x::AbstractArray, y::AbstractArray, n)
    similar(x, promote_type(eltype(x),eltype(y)), n)
end

# assign y into x out-of-place
merge(x::NDSparse{T,D}, y::NDSparse{S,D}; agg = IndexedTables.right) where {T,S,D<:Tuple} = (flush!(x);flush!(y); _merge(x, y, agg))
# merge without flush!
function _merge(x::NDSparse{T,D}, y::NDSparse{S,D}, agg) where {T,S,D}
    I, J = x.index, y.index
    lI, lJ = length(I), length(J)
    #if isless(I[end], J[1])
    #    return NDSparse(vcat(x.index, y.index), vcat(x.data, y.data), presorted=true)
    #elseif isless(J[end], I[1])
    #    return NDSparse(vcat(y.index, x.index), vcat(y.data, x.data), presorted=true)
    #end
    if agg === nothing
        n = lI + lJ
    else
        n = lI + lJ - count_overlap(I, J)
    end

    K = promoted_similar(I, J, n)
    data = promoted_similar(x.data, y.data, n)
    _merge!(K, data, x, y, agg)
end

function _merge!(K, data, x::NDSparse, y::NDSparse, agg)
    I, J = x.index, y.index
    lI, lJ = length(I), length(J)
    n = length(K)
    i = j = k = 1
    @inbounds while k <= n
        if i <= lI && j <= lJ
            c = rowcmp(I, i, J, j)
            if c > 0
                copyrow!(K, k, J, j)
                copyrow!(data, k, y.data, j)
                j += 1
            elseif c < 0
                copyrow!(K, k, I, i)
                copyrow!(data, k, x.data, i)
                i += 1
            else
                copyrow!(K, k, I, i)
                data[k] = x.data[i]
                if isa(agg, Nothing)
                    k += 1
                    copyrow!(K, k, I, i)
                    copyrow!(data, k, y.data, j) # repeat the data
                else
                    data[k] = agg(x.data[i], y.data[j])
                end
                i += 1
                j += 1
            end
        elseif i <= lI
            # TODO: copy remaining data columnwise
            copyrow!(K, k, I, i)
            copyrow!(data, k, x.data, i)
            i += 1
        elseif j <= lJ
            copyrow!(K, k, J, j)
            copyrow!(data, k, y.data, j)
            j += 1
        else
            break
        end
        k += 1
    end
    NDSparse(K, data, presorted=true)
end


"""
    merge(a::IndexedTable, b::IndexedTable; pkey)

Merge rows of `a` with rows of `b` and remain ordered by the primary key(s).  `a` and `b` must
have the same column names.

    merge(a::NDSparse, a::NDSparse; agg)

Merge rows of `a` with rows of `b`.  To keep unique keys, the value from `b` takes priority.
A provided function `agg` will aggregate values from `a` and `b` that have the same key(s).

# Example:

    a = table((x = 1:5, y = rand(5)); pkey = :x)
    b = table((x = 6:10, y = rand(5)); pkey = :x)
    merge(a, b)

    a = ndsparse([1,3,5], [1,2,3])
    b = ndsparse([2,3,4], [4,5,6])
    merge(a, b)
    merge(a, b; agg = (x,y) -> x)
"""
function Base.merge(a::Dataset, b) end

function Base.merge(a::IndexedTable, b::IndexedTable;
                    pkey = pkeynames(a) == pkeynames(b) ? a.pkey : [])

    if colnames(a) != colnames(b)
        if Set(collect(colnames(a))) == Set(collect(colnames(b)))
            b = ColDict(b, copy=false)[(colnames(a)...,)]
        else
            throw(ArgumentError("the tables don't have the same column names. Use `select` first."))
        end
    end
    table(map(opt_vcat, columns(a), columns(b)), pkey=pkey, copy=false)
end

opt_vcat(a, b) = vcat(a, b)
opt_vcat(a::PooledArray{<:Any, <:Integer, 1},
         b::PooledArray{<:Any, <:Integer,1}) = vcat(a, b)
opt_vcat(a::AbstractArray{<:Any, 1}, b::PooledArray{<:Any, <:Integer, 1}) = vcat(is_approx_uniqs_less_than(a, length(b.pool)) ? PooledArray(a) : a, b)
opt_vcat(a::PooledArray{<:Any, <:Integer, 1}, b::AbstractArray{<:Any, 1}) = vcat(a, is_approx_uniqs_less_than(b, length(a.pool)) ? PooledArray(b) : b)
function is_approx_uniqs_less_than(itr, maxuniq)
    hset = Set{UInt64}()
    for item in itr
        (length(push!(hset, hash(item))) >= maxuniq) && (return false)
    end
    true
end

function merge(x::NDSparse, xs::NDSparse...; agg = nothing)
    as = [x, xs...]
    filter!(a->length(a)>0, as)
    length(as) == 0 && return x
    length(as) == 1 && return as[1]
    for a in as; flush!(a); end
    sort!(as, by=y->first(y.index))
    if all(i->isless(as[i-1].index[end], as[i].index[1]), 2:length(as))
        # non-overlapping
        return NDSparse(vcat(map(a->a.index, as)...),
                            vcat(map(a->a.data,  as)...),
                            presorted=true)
    end
    error("this case of `merge` is not yet implemented")
end

# merge in place
function merge!(x::NDSparse{T,D}, y::NDSparse{S,D}; agg = IndexedTables.right) where {T,S,D<:Tuple}
    flush!(x)
    flush!(y)
    _merge!(x, y, agg)
end
# merge! without flush!
function _merge!(dst::NDSparse, src::NDSparse, f)
    if length(dst.index)==0 || isless(dst.index[end], src.index[1])
        append!(dst.index, src.index)
        append!(dst.data, src.data)
    else
        # merge to a new copy
        new = _merge(dst, src, f)
        ln = length(new)
        # resize and copy data into dst
        resize!(dst.index, ln)
        copyto!(dst.index, new.index)
        resize!(dst.data, ln)
        copyto!(dst.data, new.data)
    end
    return dst
end

# broadcast join - repeat data along a dimension missing from one array

function find_corresponding(Ap, Bp)
    matches = zeros(Int, length(Ap))
    J = BitSet(1:length(Bp))
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

function match_indices(A::NDSparse, B::NDSparse)
    if isa(columns(A.index), NamedTuple) && isa(columns(B.index), NamedTuple)
        Ap = colnames(A.index)
        Bp = colnames(B.index)
    else
        Ap = typeof(A).parameters[2].parameters
        Bp = typeof(B).parameters[2].parameters
    end
    find_corresponding(Ap, Bp)
end

# broadcast over trailing dimensions, i.e. C's dimensions are a prefix
# of B's. this is an easy case since it's just an inner join plus
# sometimes repeating values from the right argument.
function _broadcast_trailing(f, B::NDSparse, C::NDSparse, B_common)
    lI, rI = B.index, C.index
    lD, rD = B.data, C.data
    ll, rr = length(lI), length(rI)
    iter = GroupJoinPerm(GroupPerm(B_common, Base.OneTo(ll)), GroupPerm(rI, Base.OneTo(rr)))
    filt = Iterators.filter(((_, ridxs),) -> !isempty(ridxs), iter)
    I = similar(lI, 0)
    function step((lidxs, ridxs),)
        @inbounds Ck = rD[first(ridxs)]
        @inbounds ((pushrow!(I, lI, i); f(lD[i], Ck)) for i in lidxs)
    end
    vals = collect_columns_flattened(step(idxs) for idxs in filt)
    NDSparse(I, vals, copy=false, presorted=true)
end

function _bcast_loop(f::Function, B::NDSparse, C::NDSparse, B_common, B_perm)
    m, n = length(B_perm), length(C)
    iperm = zeros(Int, m)
    idxperm = Int32[]
    C_perm = Base.OneTo(n)
    iter = GroupJoinPerm(GroupPerm(B_common, B_perm), GroupPerm(C.index, C_perm))
    filt = Iterators.filter(((_, ridxs),) -> !isempty(ridxs), iter)
    function step((bidxs, cidxs))
        @inbounds Ck = C.data[first(cidxs)]
        @inbounds ((pj = B_perm[j]; push!(idxperm, pj); iperm[pj] = length(idxperm); f(B.data[pj], Ck)) for j in bidxs)
    end
    vals = collect_columns_flattened(step(idxs) for idxs in filt)
    B.index[idxperm], filter!(i->i!=0, iperm), vals
end

# broadcast C over B. assumes ndims(B) >= ndims(C)
function _broadcast(f::Function, B::NDSparse, C::NDSparse; dimmap=nothing)
    flush!(B); flush!(C)
    if dimmap === nothing
        C_inds = match_indices(B, C)
    else
        C_inds = dimmap
    end
    C_dims = ntuple(identity, ndims(C))
    if C_inds[1:ndims(C)] == C_dims
        return _broadcast_trailing(f, B, C, rows(B.index, C_dims))
    end
    common = filter(i->C_inds[i] > 0, 1:ndims(B))
    C_common = C_inds[common]
    B_common_cols = Columns(getsubfields(columns(B.index), common))
    B_perm = sortperm(B_common_cols)
    if C_common == C_dims
        idx, iperm, vals = _bcast_loop(f, B, C, B_common_cols, B_perm)
        A = NDSparse(idx, vals, copy=false, presorted=true)
        if !issorted(A.index)
            fastpermute!(A.index, iperm)
            fastpermute!(A.data, iperm)
        end
    else
        # TODO
        #C_perm = sortperm(Columns(columns(C.index)[[C_common...]]))
        error("dimensions of one argument to `broadcast` must be a subset of the dimensions of the other")
    end
    return A
end

"""
    broadcast(f, A::NDSparse, B::NDSparse; dimmap::Tuple{Vararg{Int}})
    A .* B

Compute an inner join of `A` and `B` using function `f`, where the dimensions
of `B` are a subset of the dimensions of `A`. Values from `B` are repeated over
the extra dimensions.

`dimmap` optionally specifies how dimensions of `A` correspond to dimensions
of `B`. It is a tuple where `dimmap[i]==j` means the `i`th dimension of `A`
matches the `j`th dimension of `B`. Extra dimensions that do not match any
dimensions of `j` should have `dimmap[i]==0`.

If `dimmap` is not specified, it is determined automatically using index column
names and types.

# Example

    a = ndsparse(([1,1,2,2], [1,2,1,2]), [1,2,3,4])
    b = ndsparse([1,2], [1/1, 1/2])
    broadcast(*, a, b)


`dimmap` maps dimensions that should be broadcasted:

    broadcast(*, a, b, dimmap=(0,1))
"""
function broadcast(f::Function, A::NDSparse, B::NDSparse; dimmap=nothing)
    if ndims(B) > ndims(A)
        _broadcast((x,y)->f(y,x), B, A, dimmap=dimmap)
    else
        _broadcast(f, A, B, dimmap=dimmap)
    end
end

broadcast(f::Function, x::NDSparse) = NDSparse(x.index, broadcast(f, x.data), presorted=true)
broadcast(f::Function, x::NDSparse, y) = NDSparse(x.index, broadcast(f, x.data, y), presorted=true)
broadcast(f::Function, y, x::NDSparse) = NDSparse(x.index, broadcast(f, y, x.data), presorted=true)

Broadcast.broadcasted(f::Function, A::NDSparse) = broadcast(f, A)
Broadcast.broadcasted(f::Function, A::NDSparse, B::NDSparse) = broadcast(f, A, B)
Broadcast.broadcasted(f::Function, A, B::NDSparse) = broadcast(f, A, B)
Broadcast.broadcasted(f::Function, A::NDSparse, B) = broadcast(f, A, B)
