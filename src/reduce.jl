"""
    reduce(f, t::IndexedTable; select::Selection)

Apply reducer function `f` pair-wise to the selection `select` in `t`.  The reducer `f` 
can be:

1. A function
1. An OnlineStat
1. A (named) tuple of functions and/or OnlineStats
1. A (named) tuple of (selector => function) or (selector => OnlineStat) pairs

# Examples

    t = table(1:5, 6:10, names = [:t, :x])

    reduce(+, t, select = :t)
    reduce((a, b) -> (t = a.t + b.t, x = a.x + b.x), t)

    using OnlineStats
    reduce(Mean(), t, select = :t)
    reduce((Mean(), Variance()), t, select = :t)

    y = reduce((min, max), t, select=:x)
    reduce((sum = +, prod = *), t, select=:x)

    # combining reduction and selection
    reduce((xsum = :x => +, negtsum = (:t => -) => +), t)
"""
function reduce(f, t::IndexedTable; select=valuenames(t), kws...)
    if haskey(kws, :init)
        return _reduce_select_init(f, t, select, kws.data.init)
    end
    _reduce_select(f, t, select)
end

function _reduce_select(f, t::Dataset, select)
    fs, input, T = init_inputs(f, rows(t, select), reduced_type, false)
    acc = init_first(fs, input[1])
    _reduce(fs, input, acc, 2)
end

function _reduce_select_init(f, t::Dataset, select, v0)
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

addname(v, name) = v
addname(v::Tup, name::Type{<:NamedTuple}) = v
addname(v, name::Type{<:NamedTuple}) = name((v,))

struct GroupReduce{F, S, T, P, N}
    f::F
    key::S
    data::T
    perm::P
    name::N
    n::Int

    GroupReduce(f::F, key::S, data::T, perm::P; name::N = nothing) where{F, S, T, P, N} =
        new{F, S, T, P, N}(f, key, data, perm, name, length(key))
end

Base.IteratorSize(::Type{<:GroupReduce}) = Base.SizeUnknown()

function Base.iterate(iter::GroupReduce, i1=1)
    i1 > iter.n && return nothing
    f, key, data, perm, n, name = iter.f, iter.key, iter.data, iter.perm, iter.n, iter.name
    val = init_first(f, data[perm[i1]])
    i = i1+1
    while i <= n && roweq(key, perm[i], perm[i1])
        val = _apply(f, val, data[perm[i]])
        i += 1
    end
    (key[perm[i1]] => addname(val, name)), i
end

"""
    groupreduce(f, t, by = pkeynames(t); select)

Calculate a [`reduce`](@ref) operation `f` over table `t` on groups defined by the values 
in selection `by`.  The result is put in a table keyed by the unique `by` values.

# Examples

    t = table([1,1,1,2,2,2], 1:6, names=[:x, :y])
    groupreduce(+,        t, :x; select = :y)
    groupreduce((sum=+,), t, :x; select = :y)  # change output column name to :sum

    t2 = table([1,1,1,2,2,2], [1,1,2,2,3,3], 1:6, names = [:x, :y, :z])
    groupreduce(+, t2, (:x, :y), select = :z)

    # different reducers for different columns
    groupreduce((sumy = :y => +, sumz = :z => +), t2, :x)  
"""
function groupreduce(f, t::Dataset, by=pkeynames(t);
                     select = t isa AbstractIndexedTable ? Not(by) : valuenames(t),
                     cache=false)

    if f isa ApplyColwise
        if !(f.functions isa Union{Function, Type})
            error("Only functions are supported in ApplyColwise for groupreduce")
        end
        return groupby(grp->colwise_group_fast(f.functions, grp), t, by; select=select)
    end

    isa(f, Pair) && (f = (f,))

    data = rows(t, select)

    by = lowerselection(t, by)

    if !isa(by, Tuple)
        by=(by,)
    end
    key  = rows(t, by)
    perm = sortpermby(t, by, cache=cache)

    fs, input, T = init_inputs(f, data, reduced_type, false)

    name = isa(t, IndexedTable) ? namedtuple(nicename(f)) : nothing
    iter = GroupReduce(fs, key, input, perm, name=name)
    convert(collectiontype(t), collect_columns(iter),
            presorted=true, copy=false)
end

colwise_group_fast(f, grp::Union{Columns, Dataset}) = map(c->reduce(f, c), columns(grp))
colwise_group_fast(f, grp::AbstractVector) = reduce(f, grp)

## GroupBy

_apply_with_key(f::Tup, data::Tup, process_data) = _apply(f, map(process_data, data))
_apply_with_key(f::Tup, data, process_data) = _apply_with_key(f, columns(data), process_data)
_apply_with_key(f, data, process_data) = _apply(f, process_data(data))

_apply_with_key(f::Tup, key, data::Tup, process_data) = _apply(f, map(t->key, data), map(process_data, data))
_apply_with_key(f::Tup, key, data, process_data) = _apply_with_key(f, key, columns(data), process_data)
_apply_with_key(f, key, data, process_data) = _apply(f, key, process_data(data))

struct GroupBy
    f
    key
    data
    perm
    usekey::Bool
    name
    n::Int

    GroupBy(f, key, data, perm; usekey = false, name = nothing) =
        new(f, key, data, perm, usekey, name, length(key))
end

Base.IteratorSize(::Type{<:GroupBy}) = Base.SizeUnknown()

function Base.iterate(iter::GroupBy, i1=1)
    i1 > iter.n && return nothing
    f, key, data, perm, usekey, n, name = iter.f, iter.key, iter.data, iter.perm, iter.usekey, iter.n, iter.name
    i = i1+1
    while i <= n && roweq(key, perm[i], perm[i1])
        i += 1
    end
    process_data = t -> view(t, perm[i1:(i-1)])
    val = usekey ? _apply_with_key(f, key[perm[i1]], data, process_data) :
                   _apply_with_key(f, data, process_data)
    (key[perm[i1]] => addname(val, name)), i
end

collectiontype(::Type{<:NDSparse}) = NDSparse
collectiontype(::Type{<:IndexedTable}) = IndexedTable
collectiontype(t::Dataset) = collectiontype(typeof(t))

"""
    groupby(f, t, by = pkeynames(t); select, flatten=false)

Apply `f` to the `select`-ed columns (see [`select`](@ref)) in groups defined by the 
unique values of `by`. 

If `f` returns a vector, split it into multiple columns with `flatten = true`.

# Examples

    using Statistics

    t=table([1,1,1,2,2,2], [1,1,2,2,1,1], [1,2,3,4,5,6], names=[:x,:y,:z])

    groupby(mean, t, :x, select=:z)
    groupby(identity, t, (:x, :y), select=:z)
    groupby(mean, t, (:x, :y), select=:z)

    groupby((mean, std, var), t, :y, select=:z)
    groupby((q25=z->quantile(z, 0.25), q50=median, q75=z->quantile(z, 0.75)), t, :y, select=:z)

    # apply different aggregation functions to different columns
    groupby((ymean = :y => mean, zmean = :z => mean), t, :x)
"""
function groupby end

function groupby(f, t::Dataset, by=pkeynames(t);
            select = t isa AbstractIndexedTable ? Not(by) : valuenames(t),
            flatten=false, usekey = false)

    isa(f, Pair) && (f = (f,))
    data = rows(t, select)
    f = init_func(f, data)
    by = lowerselection(t, by)
    if !(by isa Tuple)
        by = (by,)
    end

    key = by == () ? fill((), length(t)) : rows(t, by)

    fs, input, S = init_inputs(f, data, reduced_type, true)

    if by == ()
        res = usekey ? _apply_with_key(fs, (), input, identity) : _apply_with_key(fs, input, identity)
        res_tup = addname(res, namedtuple(nicename(f)))
        return flatten ? res_tup[end] : res_tup
    end

    perm = sortpermby(t, by)
    # Note: we're not using S here, we'll let _groupby figure it out
    name = isa(t, IndexedTable) ? namedtuple(nicename(f)) : nothing
    iter = GroupBy(fs, key, input, perm, usekey = usekey, name = name)

    t = convert(collectiontype(t), collect_columns(iter), presorted=true, copy=false)
    t isa IndexedTable && flatten ?
        IndexedTables.flatten(t, length(columns(t))) : t
end

struct ApplyColwise{T}
    functions::T
    names
    stack::Bool
    variable::Symbol
end

ApplyColwise(f; stack = false, variable = :variable) = ApplyColwise(f, [nicename(f)], stack, variable)
ApplyColwise(t::Tuple; stack = false, variable = :variable) = ApplyColwise(t, [map(nicename,t)...], stack, variable)
ApplyColwise(t::NamedTuple; stack = false, variable = :variable) = ApplyColwise(Tuple(values(t)), keys(t), stack, variable)

init_func(f, t) = f
init_func(ac::ApplyColwise{<:Tuple}, t::AbstractVector) =
    Tuple(Symbol(n) => f for (f, n) in zip(ac.functions, ac.names))
function init_func(ac::ApplyColwise{<:Tuple}, t::Columns)
    if ac.stack
        dd -> Columns(collect(colnames(t)), ([f(x) for x in columns(dd)] for f in ac.functions)...; names = vcat(ac.variable, ac.names))
    else
        Tuple(Symbol(s, :_, n) => s => f for s in colnames(t), (f, n) in zip(ac.functions, ac.names))
    end
end

init_func(ac::ApplyColwise, t::Columns) =
    ac.stack ? dd -> Columns(collect(colnames(t)), [ac.functions(x) for x in columns(dd)]; names = vcat(ac.variable, ac.names)) :
        Tuple(s => s => ac.functions for s in colnames(t))
init_func(ac::ApplyColwise, t::AbstractVector) = ac.functions

"""
    summarize(f, t, by = pkeynames(t); select = Not(by), stack = false, variable = :variable)

Apply summary functions column-wise to a table. Return a `NamedTuple` in the non-grouped case
and a table in the grouped case. Use `stack=true` to stack results of the same summary function 
for different columns.

# Examples

    using Statistics

    t = table([1, 2, 3], [1, 1, 1], names = [:x, :y])

    summarize((mean, std), t)
    summarize((m = mean, s = std), t)
    summarize(mean, t; stack=true)
    summarize((mean, std), t; select = :y)
"""
function summarize(f, t, by = pkeynames(t); select = t isa AbstractIndexedTable ? excludecols(t, by) : valuenames(t), stack = false, variable = :variable)
    flatten = stack && !(select isa Union{Int, Symbol})
    s = groupby(ApplyColwise(f, stack = stack, variable = variable), t, by, select = select, flatten = flatten)
    s isa Columns ? table(s, copy = false, presorted = true) : s
end



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
    reduce(f, x::NDSparse; dims)

Drop the `dims` dimension(s) and aggregate values with `f`.

    x = ndsparse((x=[1,1,1,2,2,2],
                  y=[1,2,2,1,2,2],
                  z=[1,1,2,1,1,2]), [1,2,3,4,5,6])
                  
    reduce(+, x; dims=1)
    reduce(+, x; dims=(1,3))
"""
function Base.reduce(f, x::NDSparse; kws...)
    if haskey(kws, :dims)
        if haskey(kws, :select) || haskey(kws, :init)
            throw(ArgumentError("select and init keyword arguments cannot be used with dims"))
        end
        dims = kws.data.dims
        if dims isa Symbol
            dims = [dims]
        end
        keep = setdiff([1:ndims(x);], map(d->fieldindex(x.index.columns,d), dims))
        if isempty(keep)
            throw(ArgumentError("to remove all dimensions, use `reduce(f, A)`"))
        end
        return groupreduce(f, x, (keep...,))
    else
        select = get(kws, :select, valuenames(x))
        if haskey(kws, :init)
            return _reduce_select_init(f, x, select, kws.data.init)
        end
        return _reduce_select(f, x, select)
    end
end

"""
`reducedim_vec(f::Function, arr::NDSparse, dims)`

Like `reduce`, except uses a function mapping a vector of values to a scalar instead
of a 2-argument scalar function.
"""
function reducedim_vec(f, x::NDSparse, dims; with=valuenames(x))
    keep = setdiff([1:ndims(x);], map(d->fieldindex(x.index.columns,d), dims))
    if isempty(keep)
        throw(ArgumentError("to remove all dimensions, use `reduce(f, A)`"))
    end
    idxs, d = collect_columns(GroupBy(f, keys(x, (keep...,)), rows(x, with), sortpermby(x, (keep...,)))).columns
    NDSparse(idxs, d, presorted=true, copy=false)
end

reducedim_vec(f, x::NDSparse, dims::Symbol) = reducedim_vec(f, x, [dims])
