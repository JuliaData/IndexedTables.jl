# to get rid of eventually
const Columns = StructVector

# IndexedTable-like API

"""
    colnames(itr)

Returns the names of the "columns" in `itr`.

# Examples:

    colnames(1:3)
    colnames(Columns([1,2,3], [3,4,5]))
    colnames(table([1,2,3], [3,4,5]))
    colnames(Columns(x=[1,2,3], y=[3,4,5]))
    colnames(table([1,2,3], [3,4,5], names=[:x,:y]))
    colnames(ndsparse(Columns(x=[1,2,3]), Columns(y=[3,4,5])))
    colnames(ndsparse(Columns(x=[1,2,3]), [3,4,5]))
    colnames(ndsparse(Columns(x=[1,2,3]), [3,4,5]))
    colnames(ndsparse(Columns([1,2,3], [4,5,6]), Columns(x=[6,7,8])))
    colnames(ndsparse(Columns(x=[1,2,3]), Columns([3,4,5],[6,7,8])))

"""
function colnames end

Base.@pure colnames(t::AbstractVector) = (1,)
columns(v::AbstractVector) = v

Base.@pure colnames(t::Columns) = fieldnames(eltype(t))
Base.@pure colnames(t::Columns{<:Pair}) = colnames(t.first) => colnames(t.second)

"""
    columns(itr, select::Selection = All())

Select one or more columns from an iterable of rows as a tuple of vectors.

`select` specifies which columns to select. Refer to the [`select`](@ref) function for the
available selection options and syntax.

`itr` can be `NDSparse`, `Columns`, `AbstractVector`, or their distributed counterparts.

# Examples

    t = table(1:2, 3:4; names = [:x, :y])

    columns(t)
    columns(t, :x)
    columns(t, (:x,))
    columns(t, (:y, :x => -))
"""
function columns end

columns(c::Columns) = fieldarrays(c)
columns(c::Columns{<:Tuple}) = Tuple(fieldarrays(c))
columns(c::Columns{<:Pair}) = c.first => c.second

"""
    ncols(itr)

Returns the number of columns in `itr`.

# Examples

    ncols([1,2,3]) == 1
    ncols(rows(([1,2,3],[4,5,6]))) == 2
"""
function ncols end
ncols(c::Columns{T, C}) where {T, C} = fieldcount(C)
ncols(c::Columns{<:Pair}) = ncols(c.first) => ncols(c.second)
ncols(c::AbstractArray) = 1

summary(c::Columns{D}) where {D<:Tuple} = "$(length(c))-element Columns{$D}"

_sizehint!(c::Columns, n::Integer) = (foreachfield(x->_sizehint!(x,n), c); c)

function _strip_pair(c::Columns{<:Pair})
    f, s = map(columns, fieldarrays(c))
    (f isa AbstractVector) && (f = (f,))
    (s isa AbstractVector) && (s = (s,))
    Columns((f..., s...))
end

# fused indexing operations
# these can be implemented for custom vector types like PooledVector where
# you can get big speedups by doing indexing and an operation in one step.

@inline copyelt!(a, i, j) = (@inbounds a[i] = a[j])
@inline copyelt!(a, i, b, j) = (@inbounds a[i] = b[j])
@inline copyelt!(a::PooledArray, i, j) = (a.refs[i] = a.refs[j])

# row operations

copyrow!(I::Columns, i, src) = foreachfield(c->copyelt!(c, i, src), I)
copyrow!(I::Columns, i, src::Columns, j) = foreachfield((c1,c2)->copyelt!(c1, i, c2, j), I, src)
copyrow!(I::AbstractArray, i, src::AbstractArray, j) = (@inbounds I[i] = src[j])
pushrow!(to::Columns, from::Columns, i) = foreachfield((a,b)->push!(a, b[i]), to, from)
pushrow!(to::AbstractArray, from::AbstractArray, i) = push!(to, from[i])

# test that the row on the right is "as of" the row on the left, i.e.
# all columns are equal except left >= right in last column.
# Could be generalized to some number of trailing columns, but I don't
# know whether that has applications.
@generated function row_asof(c::Columns{D,C}, i, d::Columns{D,C}, j) where {D,C}
    N = length(C.parameters)
    if N == 1
        ex = :(!isless(getfield(fieldarrays(c),1)[i], getfield(fieldarrays(d),1)[j]))
    else
        ex = :(isequal(getfield(fieldarrays(c),1)[i], getfield(fieldarrays(d),1)[j]))
    end
    for n in 2:N
        if N == n
            ex = :(($ex) && !isless(getfield(fieldarrays(c),$n)[i], getfield(fieldarrays(d),$n)[j]))
        else
            ex = :(($ex) && isequal(getfield(fieldarrays(c),$n)[i], getfield(fieldarrays(d),$n)[j]))
        end
    end
    ex
end

# map

"""
    map_rows(f, c...)

Transform collection `c` by applying `f` to each element. For multiple collection arguments, apply `f`
elementwise. Collect output as `Columns` if `f` returns
`Tuples` or `NamedTuples` with constant fields, as `Array` otherwise.

# Examples

    map_rows(i -> (exp = exp(i), log = log(i)), 1:5)
"""
function map_rows(f, iters...)
    collect_columns(f(i...) for i in zip(iters...))
end

# 1-arg case
map_rows(f, iter) = collect_columns(f(i) for i in iter)

## Special selectors to simplify column selector

"""
    All(cols::Union{Symbol, Int}...)

Select the union of the selections in `cols`. If `cols == ()`, select all columns.

# Examples

    t = table([1,1,2,2], [1,2,1,2], [1,2,3,4], [0, 0, 0, 0], names=[:a,:b,:c,:d])
    select(t, All(:a, (:b, :c)))
    select(t, All())
"""
struct All{T}
    cols::T
end

All(args...) = All(args)

"""
    Not(cols::Union{Symbol, Int}...)

Select the complementary of the selection in `cols`. `Not` can accept several arguments,
in which case it returns the complementary of the union of the selections.

# Examples

    t = table([1,1,2,2], [1,2,1,2], [1,2,3,4], names=[:a,:b,:c], pkey = (:a, :b))
    select(t, Not(:a))
    select(t, Not(:a, (:a, :b)))
"""
struct Not{T}
    cols::T
end

Not(args...) = Not(All(args))

"""
    Keys()

Select the primary keys.

# Examples

    t = table([1,1,2,2], [1,2,1,2], [1,2,3,4], names=[:a,:b,:c], pkey = (:a, :b))
    select(t, Keys())
"""
struct Keys; end

"""
    Between(first, last)

Select the columns between `first` and `last`.

# Examples

    t = table([1,1,2,2], [1,2,1,2], 1:4, 'a':'d', names=[:a,:b,:c,:d])
    select(t, Between(:b, :d))
"""
struct Between{T1 <: Union{Int, Symbol}, T2 <: Union{Int, Symbol}}
    first::T1
    last::T2
end

const SpecialSelector = Union{Not, All, Keys, Between, Function, Regex, Type}

hascolumns(t, s) = true
hascolumns(t, s::Symbol) = s in colnames(t)
hascolumns(t, s::Int) = s in 1:length(columns(t))
hascolumns(t, s::Tuple) = all(hascolumns(t, x) for x in s)
hascolumns(t, s::Not) = hascolumns(t, s.cols)
hascolumns(t, s::Between) = hascolumns(t, s.first) && hascolumns(t, s.last)
hascolumns(t, s::All) = all(hascolumns(t, x) for x in s.cols)
hascolumns(t, s::Type) = any(x -> eltype(x) <: s, columns(t))

lowerselection(t, s)                     = s
lowerselection(t, s::Union{Int, Symbol}) = colindex(t, s)
lowerselection(t, s::Tuple)              = map(x -> lowerselection(t, x), s)
lowerselection(t, s::Not)                = excludecols(t, lowerselection(t, s.cols))
lowerselection(t, s::Keys)               = lowerselection(t, IndexedTables.pkeynames(t))
lowerselection(t, s::Between)            = Tuple(colindex(t, s.first):colindex(t, s.last))
lowerselection(t, s::Function)           = colindex(t, Tuple(filter(s, collect(colnames(t)))))
lowerselection(t, s::Regex)              = lowerselection(t, x -> occursin(s, string(x)))
lowerselection(t, s::Type)               = Tuple(findall(x -> eltype(x) <: s, columns(t)))

function lowerselection(t, s::All)
    s.cols == () && return lowerselection(t, valuenames(t))
    ls = (isa(i, Tuple) ? i : (i,) for i in lowerselection(t, s.cols))
    ls |> Iterators.flatten |> union |> Tuple
end

### Iteration API

# For `columns(t, names)` and `rows(t, ...)` to work, `t`
# needs to support `colnames` and `columns(t)`

Base.@pure function colindex(t, col::Tuple)
    fns = colnames(t)
    map(x -> _colindex(fns, x), col)
end

Base.@pure function colindex(t, col)
    _colindex(colnames(t), col)
end

function colindex(t, col::SpecialSelector)
    colindex(t, lowerselection(t, col))
end

function _colindex(fnames::Union{Tuple, AbstractArray}, col, default=nothing)
    if isa(col, Int) && 1 <= col <= length(fnames)
        return col
    elseif isa(col, Symbol)
        idx = something(findfirst(isequal(col), fnames), 0)
        idx > 0 && return idx
    elseif isa(col, Pair{<:Any, <:AbstractArray})
        return 0
    elseif isa(col, Tuple)
        return 0
    elseif isa(col, Pair{Symbol, <:Pair}) # recursive pairs
        return _colindex(fnames, col[2])
    elseif isa(col, Pair{<:Any, <:Any})
        return _colindex(fnames, col[1])
    elseif isa(col, AbstractArray)
        return 0
    end
    default !== nothing ? default : error("column $col not found.")
end

# const ColPicker = Union{Int, Symbol, Pair{Symbol=>Function}, Pair{Symbol=>AbstractVector}, AbstractVector}
column(c, x) = columns(c)[colindex(c, x)]

# optimized method
@inline function column(c::Columns, x::Union{Int, Symbol})
    getfield(fieldarrays(c), x)
end

column(t, a::AbstractArray) = a
column(t, a::Pair{Symbol, <:AbstractArray}) = column(t, a[2])
column(t, a::Pair{Symbol, <:Pair}) = rows(t, a[2]) # renaming a selection
column(t, a::Pair{<:Any, <:Any}) = map(a[2], rows(t, a[1]))
column(t, s::SpecialSelector) = rows(t, lowerselection(t, s))

function columns(c, sel::Union{Tuple, SpecialSelector})
    which = lowerselection(c, sel)
    cnames = colnames(c, which)
    if all(x->isa(x, Symbol), cnames)
        tuplewrap = namedtuple(cnames...)∘tuple
    else
        tuplewrap = tuple
    end
    tuplewrap((rows(c, w) for w in which)...)
end

"""
`columns(itr, which)`

Returns a vector or a tuple of vectors from the iterator.

"""
columns(t, which) = column(t, which)

function colnames(c, cols::Union{Tuple, AbstractArray})
    map(x->colname(c, x), cols)
end

colnames(c, cols::SpecialSelector) = colnames(c, lowerselection(c, cols))

function colname(c, col)
    if isa(col, Union{Int, Symbol})
        col == 0 && return 0
        i = colindex(c, col)
        return colnames(c)[i]
    elseif isa(col, Pair{<:Any, <:Any})
        return col[1]
    elseif isa(col, Tuple)
        #ns = map(x->colname(c, x), col)
        return 0
    elseif isa(col, SpecialSelector)
        return 0
    elseif isa(col, AbstractVector)
        return 0
    end
    error("column named $col not found")
end

"""
    rows(itr, select = All())

Select one or more fields from an iterable of rows as a vector of their values.  Refer to
the [`select`](@ref) function for selection options and syntax.

`itr` can be [`NDSparse`](@ref), `StructArrays.StructVector`, `AbstractVector`, or their distributed counterparts.

# Examples

    t = table([1,2],[3,4], names=[:x,:y])
    rows(t)
    rows(t, :x)
    rows(t, (:x,))
    rows(t, (:y, :x => -))
"""
function rows end

rows(x::AbstractVector) = x
rows(cols::Tup) = Columns(cols)

rows(t, which...) = rows(columns(t, which...))

_cols_tuple(xs::Columns) = columns(xs)
_cols_tuple(xs::AbstractArray) = (xs,)
concat_cols(xs, ys) = rows(concat_tup(_cols_tuple(xs), _cols_tuple(ys)))

## Mutable Columns Dictionary

mutable struct ColDict{T}
    pkey::Vector{Int}
    src::T
    names::Vector
    columns::Vector
    copy::Union{Nothing, Bool}
end

"""
    d = ColDict(t)

Create a mutable dictionary of columns in `t`.

To get the immutable iterator of the same type as `t`
call `d[]`
"""
function ColDict(t; copy=nothing)
    cnames = colnames(t)
    if cnames isa AbstractArray
        cnames = Base.copy(cnames)
    end
    ColDict(Int[], t, convert(Array{Any}, collect(cnames)), Any[columns(t)...], copy)
end

Base.keys(d::ColDict) = d.names
Base.values(d::ColDict) = d.columns

function Base.getindex(d::ColDict{<:Columns})
    Columns(Tuple(d.columns); names=d.names)
end

Base.getindex(d::ColDict, key) = rows(d[], key)
Base.getindex(d::ColDict, key::AbstractArray) = key

function Base.setindex!(d::ColDict, x, key::Union{Symbol, Int})
    k = _colindex(d.names, key, 0)
    col = d[x]
    if k == 0
        push!(d.names, key)
        push!(d.columns, col)
    elseif k in d.pkey
        # primary key column has been modified.
        # copy the table as this results in a shuffle
        if d.copy === nothing
            d.copy = true
        end
        d.columns[k] = col
    else
        d.columns[k] = col
    end
end

set!(d::ColDict, key::Union{Symbol, Int}, x) = setindex!(d, x, key)

function Base.haskey(d::ColDict, key)
    _colindex(d.names, key, 0) != 0
end

function Base.insert!(d::ColDict, index, key, col)
    if haskey(d, key)
        error("Key $key already exists. Use dict[key] = col instead of inserting.")
    else
        insert!(d.names, index, key)
        insert!(d.columns, index, rows(d.src, col))
        for (i, pk) in enumerate(d.pkey)
            if pk >= index
                d.pkey[i] += 1 # moved right
            end
        end
    end
end

function insertafter!(d::ColDict, i, key, col)
    k = _colindex(d.names, i, 0)
    if k == 0
        error("$i not found. Cannot insert column after $i")
    end
    insert!(d, k+1, key, col)
end

function insertbefore!(d::ColDict, i, key, col)
    k = _colindex(d.names, i, 0)
    if k == 0
        error("$i not found. Cannot insert column after $i")
    end
    insert!(d, k, key, col)
end

function Base.pop!(d::ColDict, key::Union{Symbol, Int}=length(d.names))
    k = _colindex(d.names, key, 0)
    local col
    if k == 0
        error("Column $key not found")
    else
        col = d.columns[k]
        deleteat!(d.names, k)
        deleteat!(d.columns, k)
        idx = [pk[1] for pk in enumerate(d.pkey) if pk[2] == k]
        deleteat!(d.pkey, idx)
        for i in 1:length(d.pkey)
            if d.pkey[i] > k
                d.pkey[i] -= 1
            end
        end
        if !isempty(idx) && d.copy === nothing
            # set copy to true
            d.copy = true
        end
    end
    col
end

function rename!(d::ColDict, col::Union{Symbol, Int}, newname)
    k = _colindex(d.names, col, 0)
    if k == 0
        error("$col not found. Cannot rename it.")
    end
    d.names[k] = newname
end

Base.push!(d::ColDict, key::AbstractString, x) = push!(d, Symbol(key), x)
function Base.push!(d::ColDict, key::Union{Symbol, Int}, x)
    push!(d.names, key)
    push!(d.columns, rows(d.src, x))
end

for s in [:(Base.pop!), :(Base.push!), :(rename!), :(set!)]
    if s == :(Base.pop!)
        typ = :(Union{Symbol, Int})
    else
        typ = :Pair
        @eval $s(t::ColDict, x::Pair) = $s(t, x.first, x.second)
    end
    @eval begin
        function $s(t::ColDict, args)
            for i in args
                $s(t, i)
            end
        end
        $s(t::ColDict, args::Vararg{$typ}) = $s(t, args)
    end
end

function _cols(expr)
    if expr.head == :call
        dict = :(dict = ColDict($(expr.args[2])))
        expr.args[2] = :dict
        quote
            let $dict
                $expr
                dict[]
            end
        end |> esc
    else
        error("This form of @cols is not implemented. Use `@cols f(t,args...)` where `t` is the collection.")
    end
end

macro cols(expr)
    _cols(expr)
end

# Modifying a columns

"""
    setcol(t::Table, col::Union{Symbol, Int}, x::Selection)

Sets a `x` as the column identified by `col`. Returns a new table.

    setcol(t::Table, map::Pair{}...)

Set many columns at a time.

# Examples:

    t = table([1,2], [3,4], names=[:x, :y])

    # change second column to [5,6]
    setcol(t, 2 => [5,6])
    setcol(t, :y , :y => x -> x + 2)

    # add [5,6] as column :z
    setcol(t, :z => 5:6)
    setcol(t, :z, :y => x -> x + 2)

    # replacing the primary key results in a re-sorted copy
    t = table([0.01, 0.05], [1,2], [3,4], names=[:t, :x, :y], pkey=:t)
    t2 = setcol(t, :t, [0.1,0.05])
"""
setcol(t, args...) = @cols set!(t, args...)

"""
    pushcol(t, name, x)

Push a column `x` to the end of the table. `name` is the name for the new column. Returns a new table.

    pushcol(t, map::Pair...)

Push many columns at a time.

# Example

    t = table([0.01, 0.05], [2,1], [3,4], names=[:t, :x, :y], pkey=:t)
    pushcol(t, :z, [1//2, 3//4])
    pushcol(t, :z => [1//2, 3//4])
"""
pushcol(t, args...) = @cols push!(t, args...)

"""
    popcol(t, cols...)

Remove the column(s) `cols` from the table. Returns a new table.

# Example

    t = table([0.01, 0.05], [2,1], [3,4], names=[:t, :x, :y], pkey=:t)
    popcol(t, :x)
"""
popcol(t, args...) = @cols pop!(t, args...)

"""
    insertcol(t, position::Integer, name, x)

Insert a column `x` named `name` at `position`. Returns a new table.

# Example

    t = table([0.01, 0.05], [2,1], [3,4], names=[:t, :x, :y], pkey=:t)
    insertcol(t, 2, :w, [0,1])
"""
insertcol(t, i::Integer, name, x) = @cols insert!(t, i, name, x)

"""
    insertcolafter(t, after, name, col)

Insert a column `col` named `name` after `after`. Returns a new table.

# Example

    t = table([0.01, 0.05], [2,1], [3,4], names=[:t, :x, :y], pkey=:t)
    insertcolafter(t, :t, :w, [0,1])
"""
insertcolafter(t, after, name, x) = @cols insertafter!(t, after, name, x)

"""
    insertcolbefore(t, before, name, col)

Insert a column `col` named `name` before `before`. Returns a new table.

# Example

    t = table([0.01, 0.05], [2,1], [3,4], names=[:t, :x, :y], pkey=:t)
    insertcolbefore(t, :x, :w, [0,1])
"""
insertcolbefore(t, before, name, x) = @cols insertbefore!(t, before, name, x)

"""
    renamecol(t, col, newname)

Set `newname` as the new name for column `col` in `t`. Returns a new table.

    renamecol(t, map::Pair...)

Rename multiple columns at a time.

# Example

    t = table([0.01, 0.05], [2,1], names=[:t, :x])
    renamecol(t, :t, :time)
"""
renamecol(t, args...) = @cols rename!(t, args...)

## Utilities for mapping and reduction with many functions / OnlineStats

@inline _apply(f::OnlineStat, g, x) = (fit!(g, x); g)
@inline _apply(f::Tup, y::Tup, x::Tup) = _apply(astuple(f), astuple(y), astuple(x))
@inline _apply(f::Tuple, y::Tuple, x::Tuple) = map(_apply, f, y, x)
@inline _apply(f::NamedTuple, y::NamedTuple, x::NamedTuple) = map(_apply, f, y, x)
@inline _apply(f, y, x) = f(y, x)
@inline _apply(f::Tup, x::Tup) = _apply(astuple(f), astuple(x))
@inline _apply(f::NamedTuple, x::NamedTuple) = map(_apply, f, x)
@inline _apply(f::Tuple, x::Tuple) = map(_apply, f, x)
@inline _apply(f, x) = f(x)

@inline init_first(f, x) = x
@inline init_first(f::OnlineStat, x) = (g=copy(f); fit!(g, x); g)
@inline init_first(f::Tup, x::Tup) = map(init_first, f, x)

# Initialize functions to apply and input vectors

function init_inputs(f, x, isvec) # normal functions
    f, x
end

nicename(f::Function) = typeof(f).name.mt.name
nicename(f) = Symbol(last(split(string(f), ".")))
nicename(o::OnlineStat) = Symbol(typeof(o).name.name)

init_funcs(f, isvec) = init_funcs((f,), isvec)

function init_funcs(f::Tup, isvec)
    if isa(f, NamedTuple)
        return init_funcs((map(Pair, fieldnames(typeof(f)), f)...,), isvec)
    end

    funcmap = map(f) do g
        if isa(g, Pair)
            name = g[1]
            if isa(g[2], Pair)
                sel, fn = g[2]
            else
                sel = nothing
                fn = g[2]
            end
            (name, sel, fn)
        else
            (nicename(g), nothing, g)
        end
    end

    ns = map(x->x[1], funcmap)
    ss = map(x->x[2], funcmap)
    fs = map(map(x->x[3], funcmap)) do f
        f
    end

    NamedTuple{(ns...,)}((fs...,)), ss
end

function init_inputs(f::Tup, input, isvec)
    if isa(f, NamedTuple)
        return init_inputs((map(Pair, fieldnames(typeof(f)), f)...,), input, isvec)
    end
    fs, selectors = init_funcs(f, isvec)

    xs = map(s->s === nothing ? input : rows(input, s), selectors)

    ns = fieldnames(typeof(fs))
    NT = namedtuple(ns...)

    # functions and input
    NT((fs...,)), rows(NT((xs...,)))
end

# utils
compact_mem(v::Columns) = replace_storage(compact_mem, v)
