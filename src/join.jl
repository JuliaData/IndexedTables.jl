using DataValues

export groupjoin

# product-join on equal lkey and rkey starting at i, j
function joinequalblock(::Val{typ}, ::Val{grp}, f, I, data, lout, rout, lkey, rkey,
              ldata, rdata, lperm, rperm, init_group, accumulate, i,j) where {typ, grp}
end

# copy without allocating struct
@inline function _push!(::Val{part}, f::typeof(concat_tup), data,
                        lout, rout, ldata, rdata,
                        lidx, ridx, lnull, rnull) where part
    if part === :left
        pushrow!(lout, ldata, lidx)
        l = length(lout)
        resize!(rout, l)
    elseif part === :right
        pushrow!(rout, rdata, ridx)
        l = length(rout)
        resize!(lout, l)
    elseif part === :both
        pushrow!(lout, ldata, lidx)
        pushrow!(rout, rdata, ridx)
    end
end

@inline function _push!(::Val{part}, f, data,
                        lout, rout, ldata, rdata,
                        lidx, ridx, lnull, rnull) where part
    if part === :left
        push!(data, f(ldata[lidx], rnull))
    elseif part === :right
        push!(data, f(lnull, rdata[ridx]))
    elseif part === :both
        push!(data, f(ldata[lidx], rdata[ridx]))
    end
end

@inline function _append!(p::Val{part}, f, data,
                        lout, rout, ldata, rdata,
                        lidx, ridx, lnull, rnull) where part
    if part === :left
        for i in lidx
            _push!(p, f, data, lout, rout, ldata, rdata,
                   i, ridx, lnull, rnull)
        end
    elseif part === :right
        for i in ridx
            _push!(p, f, data, lout, rout, ldata, rdata,
                   lidx, i, lnull, rnull)
        end
    end
end

function _join!(::Val{typ}, ::Val{grp}, ::Val{keepkeys}, f, I, data, ks, lout, rout,
      lnull, rnull, lkey, rkey, ldata, rdata, lperm, rperm, init_group, accumulate) where {typ, grp, keepkeys}

    ll, rr = length(lkey), length(rkey)

    i = j = prevj = 1

    lnull_idx = Int[]
    rnull_idx = Int[]

    while i <= ll && j <= rr
        c = rowcmp(lkey, lperm[i], rkey, rperm[j])
        if c < 0
            if typ === :outer || typ === :left || typ === :anti
                push!(I, ks[lperm[i]])
                if grp
                    # empty group
                    push!(data, init_group())
                else
                    _push!(Val{:left}(), f, data, lout, rout,
                           ldata, rdata, lperm[i], 0, lnull, rnull)
                    push!(rnull_idx, length(data))
                end
            end
            i += 1
        elseif c==0
            # Join the elements that are equal at once
            @label nextgroup
            i1 = i
            j1 = j
            if grp && keepkeys
                # While grouping with keepkeys we want to make sure we create
                # one group for every unique key in the output index. Hence we may
                # need to join on smaller groups
                while i1 < ll && rowcmp(ks, lperm[i1], ks, lperm[i1+1]) == 0
                    i1 += 1
                end
            else
                while i1 < ll && rowcmp(lkey, lperm[i1], lkey, lperm[i1+1]) == 0
                    i1 += 1
                end
            end
            while j1 < rr && rowcmp(rkey, rperm[j1], rkey, rperm[j1+1]) == 0
                j1 += 1
            end
            if typ !== :anti
                if !grp
                    for x=i:i1
                        for y=j:j1
                            push!(I, ks[lperm[x]])
                            # optimized push! method for concat_tup
                            _push!(Val{:both}(), f, data,
                                   lout, rout, ldata, rdata,
                                   lperm[x], rperm[y], NA, NA)
                        end
                    end
                else
                    push!(I, ks[lperm[i]])
                    group = init_group()
                    for x=i:i1
                        for y=j:j1
                            group = accumulate(group, f(ldata[lperm[x]], rdata[rperm[y]]))
                        end
                    end
                    push!(data, group)
                    if keepkeys && i1+1 <= ll && rowcmp(lkey, lperm[i1], lkey, lperm[i1+1]) == 0
                        # This means that the next key on the left is equal in the lkey sense
                        # but different in the unique-key sense, so we start to make a new block again
                        i = i1 + 1
                        @goto nextgroup
                    end
                end
            end
            i = i1 + 1
            j = j1 + 1
        else
            if typ === :outer
                push!(I, rkey[rperm[j]])
                if grp
                    # empty group
                    push!(data, init_group())
                else
                    _push!(Val{:right}(), f, data, lout, rout,
                           ldata, rdata, 0, rperm[j], lnull, rnull)
                    push!(lnull_idx, length(data))
                end
            end
            j += 1
        end
    end

    # finish up
    if typ !== :inner
        if (typ === :outer || typ === :left || typ === :anti) && i <= ll
            append!(I, ks[lperm[i:ll]])
            if grp
                # empty group
                append!(data, map(x->init_group(), i:ll))
            else
                append!(rnull_idx, (1:length(i:ll)) .+ length(data))
                _append!(Val{:left}(), f, data, lout, rout,
                       ldata, rdata, lperm[i:ll], 0, lnull, rnull)
            end
        elseif typ === :outer && j <= rr
            append!(I, rkey[rperm[j:rr]])
            if grp
                # empty group
                append!(data, map(x->init_group(), j:rr))
            else
                append!(lnull_idx, (1:length(j:rr)) .+ length(data))
                _append!(Val{:right}(), f, data, lout, rout,
                       ldata, rdata, 0, rperm[j:rr], lnull, rnull)
            end
        end
    end
    lnull_idx, rnull_idx
end

nullrow(::Type{T}) where {T <: Tuple} = Tuple(fieldtype(T, i)() for i = 1:fieldcount(T))
nullrow(::Type{NamedTuple{names, T}}) where {names, T} = NamedTuple{names, T}(Tuple(fieldtype(T, i)() for i = 1:fieldcount(T)))
nullrow(t::Type{<:DataValue}) = t()

function init_join_output(typ, grp, f, ldata, rdata, left, keepkeys, lkey, rkey, init_group, accumulate)
    lnull = nothing
    rnull = nothing
    loutput = nothing
    routput = nothing

    if isa(grp, Val{false})

        left_type = eltype(ldata)
        if !isa(typ, Union{Val{:left}, Val{:inner}, Val{:anti}})
            null_left_type = map_params(x->DataValue{x}, eltype(ldata))
            lnull = nullrow(null_left_type)
        else
            null_left_type = left_type
        end

        right_type = eltype(rdata)
        if !isa(typ, Val{:inner})
            null_right_type = map_params(x->DataValue{x}, eltype(rdata))
            rnull = nullrow(null_right_type)
        else
            null_right_type = right_type
        end

        if f === concat_tup
            out_type = concat_tup_type(left_type, right_type)
            # separate left and right parts of the output
            # this is for optimizations in _push!
            loutput = similar(arrayof(left_type), 0)
            routput = similar(arrayof(right_type), 0)
            data = concat_cols(loutput, routput)
        else
            out_type = _promote_op(f, null_left_type, null_right_type)
            data = similar(arrayof(out_type), 0)
        end
    else
        left_type = eltype(ldata)
        right_type = eltype(rdata)
        if f === concat_tup
            out_type = concat_tup_type(left_type, right_type)
        else
            out_type = _promote_op(f, left_type, right_type)
        end
        if init_group === nothing
            init_group = () -> similar(arrayof(out_type), 0)
        end
        if accumulate === nothing
            accumulate = push!
        end
        group_type = _promote_op(accumulate, typeof(init_group()), out_type)
        data = similar(arrayof(group_type), 0)
    end

    if isa(typ, Val{:inner})
        guess = min(length(lkey), length(rkey))
    else
        guess = length(lkey)
    end

    if keepkeys
        ks = pkeys(left)
    else
        ks = lkey
    end

    _sizehint!(similar(ks,0), guess), _sizehint!(data, guess), ks, loutput, routput, lnull, rnull, init_group, accumulate
end

"""
`join([f, ] left, right; how, <options>)`

Join two tables (`left` and `right`). `how` specifies which join method is used (one of `:inner`, `:left`, `:outer` and `:anti`).
By default, join keys are implied to be the primary keys, but this can be changed using the `lkey` and `rkey` options. See Options section below.

The function `f` must take 2 arguments: tuples of non-key fields from both tables as input. The fields chosen for `f` can be configured using `lselect` and `rselect` options. See Options section below. If `f` is not specified, then these tuples are concatenated to form the non-indexed fields of the output.

# Inner join

Inner join is the default join (when `how` is unspecified). It looks up keys from `left` in `right` and only joins them when there is a match. This generates the "intersection" of keys from `left` and `right`.

```jldoctest join
julia> l = table([1,1,2,2], [1,2,1,2], [1,2,3,4],
                 names=[:a,:b,:c], pkey=(:a, :b))
Table with 4 rows, 3 columns:
a  b  c
───────
1  1  1
1  2  2
2  1  3
2  2  4

julia> r = table([0,1,1,3], [1,1,2,2], [1,2,3,4],
                 names=[:a,:b,:d], pkey=(:a, :b))
Table with 4 rows, 3 columns:
a  b  d
───────
0  1  1
1  1  2
1  2  3
3  2  4

julia> join(l,r) # inner join
Table with 2 rows, 4 columns:
a  b  c  d
──────────
1  1  1  2
1  2  2  3
```

# Left join

Left join looks up rows from `right` where keys match that in `left`. If there are no such rows in `right`, an NA value is used for every selected field from right.

```jldoctest join
julia> join(l,r, how=:left)
Table with 4 rows, 4 columns:
a  b  c  d
────────────
1  1  1  2
1  2  2  3
2  1  3  #NA
2  2  4  #NA
```

# Outer join

Outer (aka Union) join looks up rows from `right` where keys match that in `left`, and also rows from `left` where keys match those in `left`, if there are no matches on either side, a tuple of NA values is used. The output is guarranteed to contain the union of all keys from both tables.

```jldoctest join
julia> join(l,r, how=:outer)
Table with 6 rows, 4 columns:
a  b  c    d
──────────────
0  1  #NA  1
1  1  1    2
1  2  2    3
2  1  3    #NA
2  2  4    #NA
3  2  #NA  4
```

# Anti join

Anti join keeps rows in `left` whose keys are NOT present in `right`.

```jldoctest join
julia> join(l, r, how=:anti)
Table with 2 rows, 3 columns:
a  b  c
───────
2  1  3
2  2  4
```

# One-to-many and many-to-many matches

If the same key appears multiple times in either table (say, `m` and `n` times respectively), each row with a key from `left` is matched with each row from `right` with that key (resulting in `m×n` output rows with the same key.)

```jldoctest join
julia> l1 = table([1,2,2,3], [1,2,3,4], names=[:x,:y])
Table with 4 rows, 2 columns:
x  y
────
1  1
2  2
2  3
3  4

julia> r1 = table([2,2,3,3], [5,6,7,8], names=[:x,:z])
Table with 4 rows, 2 columns:
x  z
────
2  5
2  6
3  7
3  8

julia> join(l1,r1, lkey=:x, rkey=:x)
Table with 6 rows, 3 columns:
x  y  z
───────
2  2  5
2  2  6
2  3  5
2  3  6
3  4  7
3  4  8
```
This applies to all joins described above except anti join where rows are not matched.

# Options

- `how::Symbol` -- join method to use. Described above.
- `lkey::Selection` -- fields from `left` to match on
- `rkey::Selection` -- fields from `right` to match on
- `lselect::Selection` -- fields from `left` to use as output columns, or input to `f` if it is specified. By default, this is all fields not selected in `lkey`.
- `rselect::Selection` -- fields from `right` to use as output columns, or input to `f` if it is specified. By default, this is all fields not selected in `rkey`.

See `select` for a description of `Selection` type.

```jldoctest join
julia> join(l, r, lkey=:a, rkey=:a,
            lselect=:b, rselect=:d, how=:outer)
Table with 8 rows, 3 columns:
a  b    d
───────────
0  #NA  1
1  1    2
1  1    3
1  2    2
1  2    3
2  1    #NA
2  2    #NA
3  #NA  4
```
"""
function Base.join(f, left::Dataset, right::Dataset;
                   how=:inner, group=false,
                   lkey=pkeynames(left), rkey=pkeynames(right),
                   lselect=isa(left, NDSparse) ?
                       valuenames(left) : excludecols(left, lkey),
                   rselect=isa(right, NDSparse) ?
                       valuenames(right) : excludecols(right, rkey),
                   name = nothing,
                   keepkeys=false, # defaults to keeping the keys for only the joined columns
                   init_group=nothing,
                   accumulate=nothing,
                   cache=true)

    if !(how in [:inner, :left, :outer, :anti])
        error("Invalid how: supported join types are :inner, :left, :outer, and :anti")
    end
    lkey = lowerselection(left, lkey)
    rkey = lowerselection(right, rkey)
    lperm = sortpermby(left, lkey; cache=cache)
    rperm = sortpermby(right, rkey; cache=cache)
    if !isa(lkey, Tuple)
        lkey = (lkey,)
    end

    if !isa(rkey, Tuple)
        rkey = (rkey,)
    end

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

    lkey = rows(left, lkey)
    rkey = rows(right, rkey)

    ldata = rows(left, lselect)
    rdata = rows(right, rselect)
    if !isa(left, NDSparse) && keepkeys
        error("`keepkeys=true` only works while joining NDSparse type")
    end

    typ, grp = Val{how}(), Val{group}()
    I, data, ks, lout, rout, lnull, rnull, init_group, accumulate =
        init_join_output(typ, grp, f, ldata, rdata,
                         left, keepkeys, lkey, rkey,
                         init_group, accumulate)

    lnull_idx, rnull_idx = _join!(typ, grp, Val{keepkeys}(), f, I,
                                  data, ks, lout, rout, lnull, rnull,
                                  lkey, rkey, ldata, rdata, lperm,
                                  rperm, init_group, accumulate)

    if !isempty(lnull_idx) && lout !== nothing
        lnulls = zeros(Bool, length(lout))
        lnulls[lnull_idx] .= true
        lout = if lout isa Columns
            Columns(map(lout.columns) do col
                        if col isa DataValueArray
                            col.isna[lnull_idx] .= true
                        else
                            DataValueArray(col, lnulls)
                        end
                    end)
        else
            if lout isa DataValueArray
                lout.isna[lnull_idx] .= true
            else
                DataValueArray(lout, lnulls)
            end
        end
        data = concat_cols(lout, rout)
    end

    if !isempty(rnull_idx) && rout !== nothing
        rnulls = zeros(Bool, length(rout))
        rnulls[rnull_idx] .= true
        rout = if rout isa Columns
            Columns(map(rout.columns) do col
                        if col isa DataValueArray
                            col.isna[rnull_idx] .= true
                        else
                            DataValueArray(col, rnulls)
                        end
                    end)
        else
            if rout isa DataValueArray
                rout.isna[rnull_idx] .= true
            else
                DataValueArray(rout, rnulls)
            end
        end
        data = concat_cols(lout, rout)
    end

    if group && left isa NextTable && !(data isa Columns)
        data = Columns(groups=data)
    end
    convert(collectiontype(left), I, data, presorted=true, copy=false)
end

function Base.join(left::Dataset, right::Dataset; how=:inner, kwargs...)
    f = how === :anti ? (x,y) -> x : concat_tup
    join(f, left, right; how=how, kwargs...)
end

"""
`groupjoin([f, ] left, right; how, <options>)`

Join `left` and `right` creating groups of values with matching keys.

# Inner join

Inner join is the default join (when `how` is unspecified). It looks up keys from `left` in `right` and only joins them when there is a match. This generates the "intersection" of keys from `left` and `right`.

# One-to-many and many-to-many matches

If the same key appears multiple times in either table (say, `m` and `n` times respectively), each row with a key from `left` is matched with each row from `right` with that key. The resulting group has `m×n` output elements.

```jldoctest groupjoin
julia> l = table([1,1,1,2], [1,2,2,1], [1,2,3,4],
                 names=[:a,:b,:c], pkey=(:a, :b))
Table with 4 rows, 3 columns:
a  b  c
───────
1  1  1
1  2  2
1  2  3
2  1  4

julia> r = table([0,1,1,2], [1,2,2,1], [1,2,3,4],
                 names=[:a,:b,:d], pkey=(:a, :b))
Table with 4 rows, 3 columns:
a  b  d
───────
0  1  1
1  2  2
1  2  3
2  1  4

julia> groupjoin(l,r)
Table with 2 rows, 3 columns:
a  b  groups
──────────────────────────────────────────────────────────────────────────────────────────────────────
1  2  NamedTuples._NT_c_d{Int64,Int64}[(c = 2, d = 2), (c = 2, d = 3), (c = 3, d = 2), (c = 3, d = 3)]
2  1  NamedTuples._NT_c_d{Int64,Int64}[(c = 4, d = 4)]
```

# Left join

Left join looks up rows from `right` where keys match that in `left`. If there are no such rows in `right`, an NA value is used for every selected field from right.

```jldoctest groupjoin
julia> groupjoin(l,r, how=:left)
Table with 3 rows, 3 columns:
a  b  groups
──────────────────────────────────────────────────────────────────────────────────────────────────────
1  1  NamedTuples._NT_c_d{Int64,Int64}[]
1  2  NamedTuples._NT_c_d{Int64,Int64}[(c = 2, d = 2), (c = 2, d = 3), (c = 3, d = 2), (c = 3, d = 3)]
2  1  NamedTuples._NT_c_d{Int64,Int64}[(c = 4, d = 4)]
```

# Outer join

Outer (aka Union) join looks up rows from `right` where keys match that in `left`, and also rows from `left` where keys match those in `left`, if there are no matches on either side, a tuple of NA values is used. The output is guarranteed to contain

```jldoctest groupjoin

julia> groupjoin(l,r, how=:outer)
Table with 4 rows, 3 columns:
a  b  groups
──────────────────────────────────────────────────────────────────────────────────────────────────────
0  1  NamedTuples._NT_c_d{Int64,Int64}[]
1  1  NamedTuples._NT_c_d{Int64,Int64}[]
1  2  NamedTuples._NT_c_d{Int64,Int64}[(c = 2, d = 2), (c = 2, d = 3), (c = 3, d = 2), (c = 3, d = 3)]
2  1  NamedTuples._NT_c_d{Int64,Int64}[(c = 4, d = 4)]
```

# Options

- `how::Symbol` -- join method to use. Described above.
- `lkey::Selection` -- fields from `left` to match on
- `rkey::Selection` -- fields from `right` to match on
- `lselect::Selection` -- fields from `left` to use as input to use as output columns, or input to `f` if it is specified. By default, this is all fields not selected in `lkey`.
- `rselect::Selection` -- fields from `left` to use as input to use as output columns, or input to `f` if it is specified. By default, this is all fields not selected in `rkey`.

```jldoctest groupjoin
julia> groupjoin(l,r, lkey=:a, rkey=:a, lselect=:c, rselect=:d, how=:outer)
Table with 3 rows, 2 columns:
a  groups
───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
0  NamedTuples._NT_c_d{Int64,Int64}[]
1  NamedTuples._NT_c_d{Int64,Int64}[(c = 1, d = 2), (c = 1, d = 3), (c = 2, d = 2), (c = 2, d = 3), (c = 3, d = 2), (c = 3, d = 3)]
2  NamedTuples._NT_c_d{Int64,Int64}[(c = 4, d = 4)]
```
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

    @eval export $fn

    @eval function $fn(f, left::Dataset, right::Dataset; kwargs...)
        join(f, left, right; group=$group, how=$(Expr(:quote, how)), kwargs...)
    end

    @eval function $fn(left::Dataset, right::Dataset; kwargs...)
        $fn($f, left, right; kwargs...)
    end
end
export innerjoin, asofjoin, groupjoin

## Joins

const innerjoin = naturaljoin

map(f, x::NDSparse{T,D}, y::NDSparse{S,D}) where {T,S,D} = naturaljoin(f, x, y)

# asof join

"""
`asofjoin(left::NDSparse, right::NDSparse)`

asofjoin is most useful on two time-series.
It joins rows from `left` with the "most recent" value from `right`.

```jldoctest
julia> x = ndsparse((["ko","ko", "xrx","xrx"],
                     Date.(["2017-11-11", "2017-11-12",
                            "2017-11-11", "2017-11-12"])), [1,2,3,4]);

julia> y = ndsparse((["ko","ko", "xrx","xrx"],
                     Date.(["2017-11-12", "2017-11-13",
                            "2017-11-10", "2017-11-13"])), [5,6,7,8])

julia> asofjoin(x,y)
2-d NDSparse with 4 values (Int64):
1      2          │
──────────────────┼──
"ko"   2017-11-11 │ 1
"ko"   2017-11-12 │ 5
"xrx"  2017-11-11 │ 7
"xrx"  2017-11-12 │ 7
```

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
    Columns(map((a,b)->promoted_similar(a, b, n), x.columns, y.columns))
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
`merge(a::Table, a::Table; pkey)`

Merge rows from two datasets while keeping them ordered by primary keys (`pkey`). By default, if the tables have the same primary key columns in the same order, they will be used. Otherwise no primary key will be used. The tables must have the same column names. If they are not in the same order, the order from the first table will be used.

# Examples:

```jldoctest
julia> a = table([1,3,5], [1,2,3], names=[:x,:y], pkey=:x)
Table with 3 rows, 2 columns:
x  y
────
1  1
3  2
5  3

julia> b = table([2,3,4], [1,2,3], names=[:x,:y], pkey=:x)
Table with 3 rows, 2 columns:
x  y
────
2  1
3  2
4  3

julia> merge(a,b)
Table with 6 rows, 2 columns:
x  y
────
1  1
2  1
3  2
3  2
4  3
5  3

```

`merge(a::NDSparse, a::NDSparse; agg)`

Merge rows from two NDSparse objects. To keep unique keys, if a key is present in both inputs, the value from the second input is chosen. You can pass the `agg` keyword argument to combine the values with a custom function.

```jldoctest merge
julia> a = ndsparse([1,3,5], [1,2,3]);

julia> b = ndsparse([2,3,4], [1,2,3]);

julia> merge(a,b)
1-d NDSparse with 5 values (Int64):
1 │
──┼──
1 │ 1
2 │ 1
3 │ 2
4 │ 3
5 │ 3

julia> merge(a,b,agg=+)
1-d NDSparse with 5 values (Int64):
1 │
──┼──
1 │ 1
2 │ 1
3 │ 4
4 │ 3
5 │ 3
```
"""
function Base.merge(a::Dataset, b) end

function Base.merge(a::NextTable, b::NextTable;
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
    if isa(A.index.columns, NamedTuple) && isa(B.index.columns, NamedTuple)
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
function _broadcast_trailing!(f, A::NDSparse, B::NDSparse, C::NDSparse)
    I = A.index
    data = A.data
    lI, rI = B.index, C.index
    lD, rD = B.data, C.data
    ll, rr = length(lI), length(rI)

    i = j = 1

    while i <= ll && j <= rr
        c = rowcmp(lI, i, rI, j)
        if c == 0
            while true
                pushrow!(I, lI, i)
                push!(data, f(lD[i], rD[j]))
                i += 1
                (i <= ll && rowcmp(lI, i, rI, j)==0) || break
            end
            j += 1
        elseif c < 0
            i += 1
        else
            j += 1
        end
    end

    return A
end

function _bcast_loop!(f::Function, dA, B::NDSparse, C::NDSparse, B_common, B_perm)
    m, n = length(B_perm), length(C)
    jlo = klo = 1
    iperm = zeros(Int, m)
    cnt = 0
    idxperm = Int32[]
    @inbounds while jlo <= m && klo <= n
        pjlo = B_perm[jlo]
        x = rowcmp(B_common, pjlo, C.index, klo)
        x < 0 && (jlo += 1; continue)
        x > 0 && (klo += 1; continue)
        jhi = jlo + 1
        while jhi <= m && roweq(B_common, B_perm[jhi], pjlo)
            jhi += 1
        end
        Ck = C.data[klo]
        for ji = jlo:jhi-1
            j = B_perm[ji]
            # the output has the same indices as B, except with some missing.
            # invperm(B_perm) would put the indices we're using back into their
            # original sort order, so we build up that inverse permutation in
            # `iperm`, leaving some 0 gaps to be filtered out later.
            cnt += 1
            iperm[j] = cnt
            push!(idxperm, j)
            push!(dA, f(B.data[j], Ck))
        end
        jlo, klo = jhi, klo+1
    end
    B.index[idxperm], filter!(i->i!=0, iperm)
end

# broadcast C over B, into A. assumes A and B have same dimensions and ndims(B) >= ndims(C)
function _broadcast!(f::Function, A::NDSparse, B::NDSparse, C::NDSparse; dimmap=nothing)
    flush!(A); flush!(B); flush!(C)
    empty!(A)
    if dimmap === nothing
        C_inds = match_indices(A, C)
    else
        C_inds = dimmap
    end
    C_dims = ntuple(identity, ndims(C))
    if C_inds[1:ndims(C)] == C_dims
        return _broadcast_trailing!(f, A, B, C)
    end
    common = filter(i->C_inds[i] > 0, 1:ndims(A))
    C_common = C_inds[common]
    B_common_cols = Columns(getsubfields(B.index.columns, common))
    B_perm = sortperm(B_common_cols)
    if C_common == C_dims
        idx, iperm = _bcast_loop!(f, values(A), B, C, B_common_cols, B_perm)
        A = NDSparse(idx, values(A), copy=false, presorted=true)
        if !issorted(A.index)
            permute!(A.index, iperm)
            copyto!(A.data, A.data[iperm])
        end
    else
        # TODO
        #C_perm = sortperm(Columns(C.index.columns[[C_common...]]))
        error("dimensions of one argument to `broadcast` must be a subset of the dimensions of the other")
    end
    return A
end

"""
`broadcast(f::Function, A::NDSparse, B::NDSparse; dimmap::Tuple{Vararg{Int}})`

Compute an inner join of `A` and `B` using function `f`, where the dimensions
of `B` are a subset of the dimensions of `A`. Values from `B` are repeated over
the extra dimensions.

`dimmap` optionally specifies how dimensions of `A` correspond to dimensions
of `B`. It is a tuple where `dimmap[i]==j` means the `i`th dimension of `A`
matches the `j`th dimension of `B`. Extra dimensions that do not match any
dimensions of `j` should have `dimmap[i]==0`.

If `dimmap` is not specified, it is determined automatically using index column
names and types.

```jldoctest bcast
julia> a = ndsparse(([1,1,2,2], [1,2,1,2]), [1,2,3,4])
2-d NDSparse with 4 values (Int64):
1  2 │
─────┼──
1  1 │ 1
1  2 │ 2
2  1 │ 3
2  2 │ 4

julia> b = ndsparse([1,2], [1/1, 1/2])
1-d NDSparse with 2 values (Float64):
1 │
──┼────
1 │ 1.0
2 │ 0.5

julia> broadcast(*, a, b)
2-d NDSparse with 4 values (Float64):
1  2 │
─────┼────
1  1 │ 1.0
1  2 │ 2.0
2  1 │ 1.5
2  2 │ 2.0
```

The `.`-broadcast syntax works with NDSparse:
```jldoctest bcast
julia> a.*b
2-d NDSparse with 4 values (Float64):
1  2 │
─────┼────
1  1 │ 1.0
1  2 │ 2.0
2  1 │ 1.5
2  2 │ 2.0
```

`dimmap` maps dimensions that should be broadcasted:

```jldoctest bcast

julia> broadcast(*, a, b, dimmap=(0,1))
2-d NDSparse with 4 values (Float64):
1  2 │
─────┼────
1  1 │ 1.0
1  2 │ 1.0
2  1 │ 3.0
2  2 │ 2.0

```
"""
function broadcast(f::Function, A::NDSparse, B::NDSparse; dimmap=nothing)
    out_T = _promote_op(f, eltype(A), eltype(B))
    if ndims(B) > ndims(A)
        out = NDSparse(similar(B.index, 0), similar(arrayof(out_T), 0))
        _broadcast!((x,y)->f(y,x), out, B, A, dimmap=dimmap)
    else
        out = NDSparse(similar(A.index, 0), similar(arrayof(out_T), 0))
        _broadcast!(f, out, A, B, dimmap=dimmap)
    end
end

broadcast(f::Function, x::NDSparse, y) = NDSparse(x.index, broadcast(f, x.data, y), presorted=true)
broadcast(f::Function, y, x::NDSparse) = NDSparse(x.index, broadcast(f, y, x.data), presorted=true)

Broadcast.broadcasted(f::Function, A::NDSparse, B::NDSparse) = broadcast(f, A, B)
Broadcast.broadcasted(f::Function, A, B::NDSparse) = broadcast(f, A, B)
Broadcast.broadcasted(f::Function, A::NDSparse, B) = broadcast(f, A, B)
