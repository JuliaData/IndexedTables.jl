using OnlineStats
export groupreduce, groupby, aggregate, aggregate_vec, summarize

"""
`reduce(f, t::Table; select::Selection)`

Reduce `t` by applying `f` pair-wise on values or structs
selected by `select`.

`f` can be:

1. A function
2. An OnlineStat
3. A tuple of functions and/or OnlineStats
4. A named tuple of functions and/or OnlineStats
5. A named tuple of (selector => function or OnlineStat) pairs

```jldoctest reduce
julia> t = table([0.1, 0.5, 0.75], [0,1,2], names=[:t, :x])
Table with 3 rows, 2 columns:
t     x
───────
0.1   0
0.5   1
0.75  2
```

When `f` is a function, it reduces the selection as usual:

```jldoctest reduce
julia> reduce(+, t, select=:t)
1.35
```

If `select` is omitted, the rows themselves are passed to reduce as tuples.

```jldoctest reduce
julia> reduce((a, b) -> @NT(t=a.t+b.t, x=a.x+b.x), t)
(t = 1.35, x = 3)
```

If `f` is an OnlineStat object from the [OnlineStats](https://github.com/joshday/OnlineStats.jl) package, the statistic is computed on the selection.

```jldoctest reduce
julia> using OnlineStats

julia> reduce(Mean(), t, select=:t)
▦ Series{0,Tuple{Mean},EqualWeight}
┣━━ EqualWeight(nobs = 3)
┗━━━┓
    ┗━━ Mean(0.45)
```

# Reducing with multiple functions

Often one needs many aggregate values from a table. This is when `f` can be passed as a tuple of functions:

```jldoctest reduce
julia> y = reduce((min, max), t, select=:x)
(min = 0, max = 2)

julia> y.max
2

julia> y.min
0
```

Note that the return value of invoking reduce with a tuple of functions
will be a named tuple which has the function names as the keys. In the example, we reduced using `min` and `max` functions to obtain the minimum and maximum values in column `x`.

If you want to give a different name to the fields in the output, use a named tuple as `f` instead:

```jldoctest reduce
julia> y = reduce(@NT(sum=+, prod=*), t, select=:x)
(sum = 3, prod = 0)
```

You can also compute many OnlineStats by passing tuple or named tuple of OnlineStat objects as the reducer.

```jldoctest reduce
julia> y = reduce((Mean(), Variance()), t, select=:t)
(Mean = ▦ Series{0,Tuple{Mean},EqualWeight}
┣━━ EqualWeight(nobs = 3)
┗━━━┓
    ┗━━ Mean(0.45), Variance = ▦ Series{0,Tuple{Variance},EqualWeight}
┣━━ EqualWeight(nobs = 3)
┗━━━┓
    ┗━━ Variance(0.1075))

julia> y.Mean
▦ Series{0,Tuple{Mean},EqualWeight}
┣━━ EqualWeight(nobs = 3)
┗━━━┓
    ┗━━ Mean(0.45)

julia> y.Variance
▦ Series{0,Tuple{Variance},EqualWeight}
┣━━ EqualWeight(nobs = 3)
┗━━━┓
    ┗━━ Variance(0.1075)
```

# Combining reduction and selection

In the above section where we computed many reduced values at once, we have been using the same selection for all reducers, that specified by `select`. It's possible to select different inputs for different reducers by using a named tuple of `slector => function` pairs:

```jldoctest reduce
julia> reduce(@NT(xsum=:x=>+, negtsum=(:t=>-)=>+), t)
(xsum = 3, negtsum = -1.35)

```

See [`Selection`](@ref) for more on what selectors can be specified. Here since each output can select its own input, `select` keyword is unsually unnecessary. If specified, the slections in the reducer tuple will be done over the result of selecting with the `select` argument.

"""
function reduce(f, t::Dataset; select=valuenames(t))
    fs, input, T = init_inputs(f, rows(t, select), reduced_type, false)
    acc = init_first(fs, input[1])
    _reduce(fs, input, acc, 2)
end

function reduce(f, t::Dataset, v0; select=valuenames(t))
    fs, input, T = init_inputs(f, rows(t, select), reduced_type, false)
    _reduce(fs, input, v0, 1)
end

function _reduce(fs, input, acc, start)
    @inbounds @simd for i=start:length(input)
        acc = _apply(fs, acc, input[i])
    end
    acc
end

## groupreduce

function groupreduce_to!(f, key, data, dest_key, dest_data, perm, i1=1)
    n = length(key)
    while i1 <= n
        val = init_first(f, data[perm[i1]])
        i = i1+1
        while i <= n && roweq(key, perm[i], perm[i1])
            val = _apply(f, val, data[perm[i]])
            i += 1
        end
        if dest_data === nothing
            if val isa Tup
                col = convert(Columns, [val])
            else
                col = [val]
            end
            push!(dest_key, key[perm[i1]])
            return groupreduce_to!(f, key, data, dest_key, col, perm, i)
        else
            push!(dest_key, key[perm[i1]])
            push!(dest_data, val)
        end
        i1 = i
    end
    dest_key, dest_data
end

"""
`groupreduce(f, t[, by::Selection]; select::Selection)`

Group rows by `by`, and apply `f` to reduce each group. `f` can be a function, OnlineStat or a struct of these as described in [`reduce`](@ref). Recommended: see documentation for [`reduce`](@ref) first. The result of reducing each group is put in a table keyed by unique `by` values, the names of the output columns are the same as the names of the fields of the reduced tuples.

# Examples

```jldoctest groupreduce
julia> t=table([1,1,1,2,2,2], [1,1,2,2,1,1], [1,2,3,4,5,6],
               names=[:x,:y,:z]);

julia> groupreduce(+, t, :x, select=:z)
Table with 2 rows, 2 columns:
x  +
─────
1  6
2  15

julia> groupreduce(+, t, (:x, :y), select=:z)
Table with 4 rows, 3 columns:
x  y  +
────────
1  1  3
1  2  3
2  1  11
2  2  4

julia> groupreduce((+, min, max), t, (:x, :y), select=:z)
Table with 4 rows, 5 columns:
x  y  +   min  max
──────────────────
1  1  3   1    2
1  2  3   3    3
2  1  11  5    6
2  2  4   4    4
```

If `f` is a single function or a tuple of functions, the output columns will be named the same as the functions themselves. To change the name, pass a named tuple:

```jldoctest groupreduce
julia> groupreduce(@NT(zsum=+, zmin=min, zmax=max), t, (:x, :y), select=:z)
Table with 4 rows, 5 columns:
x  y  zsum  zmin  zmax
──────────────────────
1  1  3     1     2
1  2  3     3     3
2  1  11    5     6
2  2  4     4     4
```

Finally, it's possible to select different inputs for different reducers by using a named tuple of `slector => function` pairs:

```jldoctest groupreduce
julia> groupreduce(@NT(xsum=:x=>+, negysum=(:y=>-)=>+), t, :x)
Table with 2 rows, 3 columns:
x  xsum  negysum
────────────────
1  3     -4
2  6     -4

```

"""
function groupreduce(f, t::Dataset, by=pkeynames(t);
                     select = t isa AbstractIndexedTable ? Not(by) : valuenames(t))

    data = rows(t, select)
    if typeof(t)<:NextTable &&
        !isa(f, Tup) &&
        !(reduced_type(f, data, false) <: Tup)
        # Name the result after the function
        return groupreduce((f,), t, by, select=select)
    end
    by = lowerselection(t, by)
    if !isa(by, Tuple)
        by=(by,)
    end
    key  = rows(t, by)
    perm = sortpermby(t, by)

    dest_key = similar(key, 0)

    fs, input, T = init_inputs(f, data, reduced_type, false)

    dest_key, dest_data = groupreduce_to!(fs, key, input,
                                          dest_key, nothing, perm)

    convert(collectiontype(t), dest_key, dest_data,
            presorted=true, copy=false)
end

## GroupBy

_apply_with_key(f::Tup, data::Tup, process_data) = _apply(f, map(process_data, data))
_apply_with_key(f::Tup, data, process_data) = _apply_with_key(f, columns(data), process_data)
_apply_with_key(f, data, process_data) = _apply(f, process_data(data))

_apply_with_key(f::Tup, key, data::Tup, process_data) = _apply(f, map(t->key, data), map(process_data, data))
_apply_with_key(f::Tup, key, data, process_data) = _apply_with_key(f, key, columns(data), process_data)
_apply_with_key(f, key, data, process_data) = _apply(f, key, process_data(data))

function _groupby(f, key, data, perm, dest_key=similar(key,0),
                  dest_data=nothing, i1=1; usekey = false)
    n = length(key)
    while i1 <= n
        i = i1+1
        while i <= n && roweq(key, perm[i], perm[i1])
            i += 1
        end
        process_data = t -> view(t, perm[i1:(i-1)])
        val = usekey ? _apply_with_key(f, key[perm[i1]], data, process_data) :
                       _apply_with_key(f, data, process_data)

        push!(dest_key, key[perm[i1]])
        if dest_data === nothing
            newdata = [val]
            if isa(val, Tup)
                newdata = convert(Columns, newdata)
            end
            return _groupby(f, key, data, perm, dest_key, newdata, i; usekey = usekey)
        else
            push!(dest_data, val)
        end
        i1 = i
    end
    (dest_key, dest_data===nothing ? Union{}[] : dest_data)
end

collectiontype(::Type{<:NDSparse}) = NDSparse
collectiontype(::Type{<:NextTable}) = NextTable
collectiontype(t::Dataset) = collectiontype(typeof(t))

"""
`groupby(f, t[, by::Selection]; select::Selection, flatten)`

Group rows by `by`, and apply `f` to each group. `f` can be a function or a tuple of functions. The result of `f` on each group is put in a table keyed by unique `by` values. `flatten` will flatten the result and can be used when `f` returns a vector instead of a single scalar value.

# Examples

```jldoctest groupby
julia> t=table([1,1,1,2,2,2], [1,1,2,2,1,1], [1,2,3,4,5,6],
               names=[:x,:y,:z]);

julia> groupby(mean, t, :x, select=:z)
Table with 2 rows, 2 columns:
x  mean
───────
1  2.0
2  5.0

julia> groupby(identity, t, (:x, :y), select=:z)
Table with 4 rows, 3 columns:
x  y  identity
──────────────
1  1  [1, 2]
1  2  [3]
2  1  [5, 6]
2  2  [4]

julia> groupby(mean, t, (:x, :y), select=:z)
Table with 4 rows, 3 columns:
x  y  mean
──────────
1  1  1.5
1  2  3.0
2  1  5.5
2  2  4.0
```

multiple aggregates can be computed by passing a tuple of functions:

```jldoctest groupby
julia> groupby((mean, std, var), t, :y, select=:z)
Table with 2 rows, 4 columns:
y  mean  std       var
──────────────────────────
1  3.5   2.38048   5.66667
2  3.5   0.707107  0.5

julia> groupby(@NT(q25=z->quantile(z, 0.25), q50=median,
                   q75=z->quantile(z, 0.75)), t, :y, select=:z)
Table with 2 rows, 4 columns:
y  q25   q50  q75
──────────────────
1  1.75  3.5  5.25
2  3.25  3.5  3.75
```

Finally, it's possible to select different inputs for different functions by using a named tuple of `slector => function` pairs:

```jldoctest groupby
julia> groupby(@NT(xmean=:z=>mean, ystd=(:y=>-)=>std), t, :x)
Table with 2 rows, 3 columns:
x  xmean  ystd
─────────────────
1  2.0    0.57735
2  5.0    0.57735
```

By default, the result of groupby when `f` returns a vector or iterator of values will not be expanded. Pass the `flatten` option as `true` to flatten the grouped column:

```jldoctest
julia> t = table([1,1,2,2], [3,4,5,6], names=[:x,:y])

julia> groupby((:normy => x->Iterators.repeated(mean(x), length(x)),),
                t, :x, select=:y, flatten=true)
Table with 4 rows, 2 columns:
x  normy
────────
1  3.5
1  3.5
2  5.5
2  5.5
```

The keyword option `usekey = true` allows to use information from the indexing column. `f` will need to accept two
arguments, the first being the key (as a `Tuple` or `NamedTuple`) the second the data (as `Columns`).

```jldoctest
julia> t = table([1,1,2,2], [3,4,5,6], names=[:x,:y])

julia> groupby((:x_plus_mean_y => (key, d) -> key.x + mean(d),),
                              t, :x, select=:y, usekey = true)
Table with 2 rows, 2 columns:
x  x_plus_mean_y
────────────────
1  4.5
2  7.5
```

"""
function groupby end

function groupby(f, t::Dataset, by=pkeynames(t);
            select = t isa AbstractIndexedTable ? Not(by) : valuenames(t),
            flatten=false, usekey = false)

    data = rows(t, select)
    f = init_func(f, data)
    by = lowerselection(t, by)
    if !(by isa Tuple)
        by = (by,)
    end

    key = by == () ? fill((), length(t)) : rows(t, by)
    # we want to try and keep the column names
    if typeof(t)<:NextTable &&
        !isa(f, Tup) &&
        !(reduced_type(f, data, true, usekey ? key : nothing) <: Tup)
        # Name the result after the function
        return groupby((f,), t, by, select=select, flatten=flatten, usekey = usekey)
    end

    fs, input, S = init_inputs(f, data, reduced_type, true)

    by == () && return usekey ? _apply_with_key(fs, (), input, identity) : _apply_with_key(fs, input, identity)

    perm = sortpermby(t, by)
    # Note: we're not using S here, we'll let _groupby figure it out
    dest_key, dest_data = _groupby(fs, key, input, perm; usekey = usekey)

    t = convert(collectiontype(t), dest_key, dest_data, presorted=true, copy=false)
    t isa NextTable && flatten ?
        IndexedTables.flatten(t, length(columns(t))) : t
end

struct ApplyColwise{T}
    functions::T
    names::Vector{Symbol}
end

ApplyColwise(f) = ApplyColwise(f, Symbol[])
ApplyColwise(t::Tuple) = ApplyColwise(t, [map(Symbol,t)...])
ApplyColwise(t::NamedTuple) = ApplyColwise(Tuple(values(t)), keys(t))

init_func(f, t) = f
init_func(ac::ApplyColwise{<:Tuple}, t::AbstractVector) =
    Tuple(Symbol(n) => f for (f, n) in zip(ac.functions, ac.names))
init_func(ac::ApplyColwise{<:Tuple}, t::Columns) =
    Tuple(Symbol(s, :_, n) => s => f for s in colnames(t), (f, n) in zip(ac.functions, ac.names))
init_func(ac::ApplyColwise, t::Columns) =
    Tuple(s => s => ac.functions for s in colnames(t))
init_func(ac::ApplyColwise, t::AbstractVector) = ac.functions

"""
`summarize(f, t, by = pkeynames(t); select = excludecols(t, by))`

Apply summary functions column-wise to a table. Return a `NamedTuple` in the non-grouped case
and a table in the grouped case.

# Examples

```jldoctest colwise
julia> t = table([1, 2, 3], [1, 1, 1], names = [:x, :y]);

julia> summarize((mean, std), t)
(x_mean = 2.0, y_mean = 1.0, x_std = 1.0, y_std = 0.0)

julia> s = table(["a","a","b","b"], [1,3,5,7], [2,2,2,2], names = [:x, :y, :z], pkey = :x);

julia> summarize(mean, s)
Table with 2 rows, 3 columns:
x    y    z
─────────────
"a"  2.0  2.0
"b"  6.0  2.0
```

Use a `NamedTuple` to have different names for the summary functions:

```jldoctest colwise
julia> summarize(@NT(m = mean, s = std), t)
(x_m = 2.0, y_m = 1.0, x_s = 1.0, y_s = 0.0)
```

Use `select` to only summarize some columns:

```jldoctest colwise
julia> summarize(@NT(m = mean, s = std), t, select = :x)
(m = 2.0, s = 1.0)
```

"""
function summarize(f, t, by = pkeynames(t); select = t isa AbstractIndexedTable ? excludecols(t, by) : valuenames(t))
    groupby(ApplyColwise(f), t, by, select = select)
end


Base.@deprecate aggregate(f, t;
                          by=pkeynames(t),
                          with=valuenames(t)) groupreduce(f, t, by; select=with)


Base.@deprecate aggregate_vec(
    fs::Function, x;
    names=nothing,
    by=pkeynames(x),
    with=valuenames(x)) groupby(names === nothing ? fs : (names => fs,), x; select=with)

Base.@deprecate aggregate_vec(
    fs::AbstractVector, x;
    names=nothing,
    by=pkeynames(x),
    with=valuenames(x)) groupby(names === nothing ? (fs...) : (map(=>, names, fs)...,), x; select=with)

Base.@deprecate aggregate_vec(t; funs...) groupby(namedtuple(first.(funs)...)(last.(funs)...), t)


"""
`convertdim(x::NDSparse, d::DimName, xlate; agg::Function, vecagg::Function, name)`

Apply function or dictionary `xlate` to each index in the specified dimension.
If the mapping is many-to-one, `agg` or `vecagg` is used to aggregate the results.
If `agg` is passed, it is used as a 2-argument reduction function over the data.
If `vecagg` is passed, it is used as a vector-to-scalar function to aggregate
the data.
`name` optionally specifies a new name for the translated dimension.
"""
function convertdim(x::NDSparse, d::DimName, xlat; agg=nothing, vecagg=nothing, name=nothing, select=valuenames(x))
    ks = setcol(pkeys(x), d, d=>xlat)
    if name !== nothing
        ks = renamecol(ks, d, name)
    end

    if vecagg !== nothing
        y = convert(NDSparse, ks, rows(x, select))
        return groupby(vecagg, y)
    end

    if agg !== nothing
        return convert(NDSparse, ks, rows(x, select), agg=agg)
    end
    convert(NDSparse, ks, rows(x, select))
end

convertdim(x::NDSparse, d::Int, xlat::Dict; agg=nothing, vecagg=nothing, name=nothing, select=valuenames(x)) = convertdim(x, d, i->xlat[i], agg=agg, vecagg=vecagg, name=name, select=select)

convertdim(x::NDSparse, d::Int, xlat, agg) = convertdim(x, d, xlat, agg=agg)

sum(x::NDSparse) = sum(x.data)

"""
`reducedim(f, x::NDSparse, dims)`

Drop `dims` dimension(s) and aggregate with `f`.

```jldoctest
julia> x = ndsparse(@NT(x=[1,1,1,2,2,2],
                        y=[1,2,2,1,2,2],
                        z=[1,1,2,1,1,2]), [1,2,3,4,5,6])
3-d NDSparse with 6 values (Int64):
x  y  z │
────────┼──
1  1  1 │ 1
1  2  1 │ 2
1  2  2 │ 3
2  1  1 │ 4
2  2  1 │ 5
2  2  2 │ 6

julia> reducedim(+, x, 1)
2-d NDSparse with 3 values (Int64):
y  z │
─────┼──
1  1 │ 5
2  1 │ 7
2  2 │ 9

julia> reducedim(+, x, (1,3))
1-d NDSparse with 2 values (Int64):
y │
──┼───
1 │ 5
2 │ 16

```
"""
function reducedim(f, x::NDSparse, dims)
    keep = setdiff([1:ndims(x);], map(d->fieldindex(x.index.columns,d), dims))
    if isempty(keep)
        throw(ArgumentError("to remove all dimensions, use `reduce(f, A)`"))
    end
    groupreduce(f, x, (keep...))
end

reducedim(f, x::NDSparse, dims::Symbol) = reducedim(f, x, [dims])

"""
`reducedim_vec(f::Function, arr::NDSparse, dims)`

Like `reducedim`, except uses a function mapping a vector of values to a scalar instead
of a 2-argument scalar function.
"""
function reducedim_vec(f, x::NDSparse, dims; with=valuenames(x))
    keep = setdiff([1:ndims(x);], map(d->fieldindex(x.index.columns,d), dims))
    if isempty(keep)
        throw(ArgumentError("to remove all dimensions, use `reduce(f, A)`"))
    end
    idxs, d = _groupby(f, keys(x, (keep...)), rows(x, with), sortpermby(x, (keep...)))
    NDSparse(idxs, d, presorted=true, copy=false)
end

reducedim_vec(f, x::NDSparse, dims::Symbol) = reducedim_vec(f, x, [dims])
