import Base:
    push!, size, sort, sort!, permute!, issorted, sortperm,
    summary, resize!, vcat, append!, copyto!, view

"""
Wrapper around a (named) tuple of Vectors that acts like a Vector of (named) tuples.

# Fields:

- `columns`: a (named) tuple of Vectors. Also `columns(x)`
"""
struct Columns{D<:Union{Tup, Pair}, C<:Union{Tup, Pair}} <: AbstractVector{D}
    columns::C

    function Columns{D,C}(c) where {D<:Tup,C<:Tup}
        if !isempty(c)
            n = length(c[1])
            for i = 2:length(c)
                length(c[i]) == n || error("all columns must have same length")
            end
        end
        new{D,C}(c)
    end

    function Columns{D,C}(c::Pair) where {D<:Pair,C<:Pair{<:AbstractVector, <:AbstractVector}}
        length(c.first) == length(c.second) || error("all columns must have same length")
        new{D,C}(c)
    end
end

function Columns(cols::AbstractVector...; names::Union{Vector,Tuple{Vararg{Any}},Nothing}=nothing)
    if isa(names, Nothing) || any(x->!(x isa Symbol), names)
        Columns{eltypes(typeof(cols)),typeof(cols)}(cols)
    else
        dt = NamedTuple{(names...,), Tuple{map(eltype, cols)...}}
        ct = NamedTuple{(names...,), Tuple{map(typeof, cols)...}}
        Columns{dt,ct}(ct((cols...,)))
    end
end

function Columns(; kws...)
    Columns(values(kws)..., names=collect(keys(kws)))
end

Columns(c::Union{Tup, Pair}) = Columns{eltypes(typeof(c)),typeof(c)}(c)

# There is a StackOverflow bug in this case in Base.unaliascopy
Base.copy(c::Columns{<:Union{NamedTuple{(),Tuple{}}, Tuple{}}}) = c

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
Base.@pure colnames(t::Columns{<:Pair, <:Pair}) = colnames(t.columns.first) => colnames(t.columns.second)

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

columns(c) = error("no columns defined for $(typeof(c))")
columns(c::Columns) = c.columns

# Array-like API

eltype(::Type{Columns{D,C}}) where {D,C} = D
function length(c::Columns)
    isempty(c.columns) ? 0 : length(c.columns[1])
end
length(c::Columns{<:Pair, <:Pair}) = length(c.columns.first)
ndims(c::Columns) = 1

"""
`ncols(itr)`

Returns the number of columns in `itr`.

# Examples

    ncols([1,2,3])
    ncols(rows(([1,2,3],[4,5,6])))
    ncols(table(([1,2,3],[4,5,6])))
    ncols(table(@NT(x=[1,2,3],y=[4,5,6])))
    ncols(ndsparse(d, [7,8,9]))
"""
function ncols end
ncols(c::Columns) = fieldcount(typeof(c.columns))
ncols(c::Columns{<:Pair, <:Pair}) = ncols(c.columns.first) => ncols(c.columns.second)
ncols(c::AbstractArray) = 1

size(c::Columns) = (length(c),)
Base.IndexStyle(::Type{<:Columns}) = IndexLinear()
summary(c::Columns{D}) where {D<:Tuple} = "$(length(c))-element Columns{$D}"

empty!(c::Columns) = (foreach(empty!, c.columns); c)
empty!(c::Columns{<:Pair, <:Pair}) = (foreach(empty!, c.columns.first.columns); foreach(empty!, c.columns.second.columns); c)

function similar(c::Columns{D,C}) where {D,C}
    cols = _map(similar, c.columns)
    Columns{D,typeof(cols)}(cols)
end

function similar(c::Columns{D,C}, n::Integer) where {D,C}
    cols = _map(a->similar(a,n), c.columns)
    Columns{D,typeof(cols)}(cols)
end

function Base.similar(::Type{T}, n::Int)::T where {T<:Columns}
    T_cols = T.parameters[2]
    if T_cols <: Pair
        return Columns(similar(T_cols.parameters[1], n) => similar(T_cols.parameters[2], n))
    end
    f = T_cols <: Tuple ? tuple : T_cols∘tuple
    T(f(map(t->similar(t, n), fieldtypes(T_cols))...))
end

function convert(::Type{Columns}, x::AbstractArray{<:NTuple{N,Any}}) where N
    eltypes = (eltype(x).parameters...,)
    copyto!(Columns(map(t->Vector{t}(undef, length(x)), eltypes)), x)
end

function convert(::Type{Columns}, x::AbstractArray{<:NamedTuple{names, typs}}) where {names,typs}
    eltypes = typs.parameters
    copyto!(Columns(map(t->Vector{t}(undef, length(x)), eltypes)..., names=fieldnames(eltype(x))), x)
end


getindex(c::Columns{D}, i::Integer) where {D<:Tuple} = ith_all(i, c.columns)
getindex(c::Columns{D}, i::Integer) where {D<:NamedTuple} = D(ith_all(i, c.columns))
getindex(c::Columns{D}, i::Integer) where {D<:Pair} = getindex(c.columns.first, i) => getindex(c.columns.second, i)

getindex(c::Columns, p::AbstractVector) = Columns(_map(c->c[p], c.columns))

view(c::Columns, I) = Columns(_map(a->view(a, I), c.columns))

@inline setindex!(I::Columns, r::Union{Tup, Pair}, i::Integer) = (foreach((c,v)->(c[i]=v), I.columns, r); I)

@inline push!(I::Columns, r::Union{Tup, Pair}) = (foreach(push!, I.columns, r); I)

append!(I::Columns, J::Columns) = (foreach(append!, I.columns, J.columns); I)

copyto!(I::Columns, J::Columns) = (foreach(copyto!, I.columns, J.columns); I)

resize!(I::Columns, n::Int) = (foreach(c->resize!(c,n), I.columns); I)

_sizehint!(c::Columns, n::Integer) = (foreach(c->_sizehint!(c,n), c.columns); c)

function ==(x::Columns, y::Columns)
    nc = length(x.columns)
    length(y.columns) == nc || return false
    fieldnames(eltype(x)) == fieldnames(eltype(y)) || return false
    n = length(x)
    length(y) == n || return false
    for i in 1:nc
        x.columns[i] == y.columns[i] || return false
    end
    return true
end

==(x::Columns{<:Pair}, y::Columns) = false
==(x::Columns, y::Columns{<:Pair}) = false
==(x::Columns{<:Pair}, y::Columns{<:Pair}) = (x.columns.first == y.columns.first) && (x.columns.second == y.columns.second)

function _strip_pair(c::Columns{<:Pair})
    f, s = map(columns, c.columns)
    (f isa AbstractVector) && (f = (f,))
    (s isa AbstractVector) && (s = (s,))
    Columns(f..., s...)
end

function sortperm(c::Columns)
    cols = c.columns
    x = cols[1]
    if (eltype(x) <: AbstractString && !(x isa PooledArray)) || length(cols) > 1
        pa = PooledArray(compact_mem(x))
        p = sortperm_fast(pa)
    else
        p = sortperm_fast(x)
    end
    if length(cols) > 1
        y = cols[2]
        refine_perm!(p, cols, 1, compact_mem(x), compact_mem(y), 1, length(x))
    end
    return p
end

sortperm(c::Columns{<:Pair}) = sortperm(_strip_pair(c))

issorted(c::Columns) = issorted(1:length(c), lt=(x,y)->rowless(c, x, y))
issorted(c::Columns{<:Pair}) = issorted(_strip_pair(c))

# assuming x[p] is sorted, sort by remaining columns where x[p] is constant
function refine_perm!(p, cols, c, x, y, lo, hi)
    temp = similar(p, 0)
    order = Base.Order.By(j->(@inbounds k=y[j]; k))
    nc = length(cols)
    i = lo
    while i < hi
        i1 = i+1
        @inbounds while i1 <= hi && roweq(x, p[i1], p[i])
            i1 += 1
        end
        i1 -= 1
        if i1 > i
            sort_sub_by!(p, i, i1, y, order, temp)
            if c < nc-1
                z = cols[c+2]
                refine_perm!(p, cols, c+1, compact_mem(y), compact_mem(z), i, i1)
            end
        end
        i = i1+1
    end
end

function permute!(c::Columns, p::AbstractVector)
    for v in c.columns
        if isa(v, PooledArrays.PooledArray) || isa(v, StringArray{String})
            permute!(v, p)
        else
            copyto!(v, v[p])
        end
    end
    return c
end
permute!(c::Columns{<:Pair}, p::AbstractVector) = (permute!(c.columns.first, p); permute!(c.columns.second, p); c)
sort!(c::Columns) = permute!(c, sortperm(c))
sort(c::Columns) = c[sortperm(c)]

function Base.vcat(c::Columns, cs::Columns...)
    fns = map(fieldnames∘typeof, (map(x->x.columns, (c, cs...))))
    f1 = fns[1]
    for f2 in fns[2:end]
        if f1 != f2
            errfields = join(map(string, fns), ", ", " and ")
            throw(ArgumentError("Cannot concatenate columns with fields $errfields"))
        end
    end
    Columns(map(vcat, map(x->x.columns, (c,cs...))...))
end

function Base.vcat(c::Columns{<:Pair}, cs::Columns{<:Pair}...)
    Columns(vcat(c.columns.first, (x.columns.first for x in cs)...) =>
            vcat(c.columns.second, (x.columns.second for x in cs)...))
end

# fused indexing operations
# these can be implemented for custom vector types like PooledVector where
# you can get big speedups by doing indexing and an operation in one step.

@inline cmpelts(a, i, j) = (@inbounds x=cmp(a[i], a[j]); x)
@inline copyelt!(a, i, j) = (@inbounds a[i] = a[j])
@inline copyelt!(a, i, b, j) = (@inbounds a[i] = b[j])

@inline cmpelts(a::PooledArray, i, j) = (x=cmp(a.refs[i],a.refs[j]); x)
@inline copyelt!(a::PooledArray, i, j) = (a.refs[i] = a.refs[j])

# row operations

copyrow!(I::Columns, i, src) = foreach(c->copyelt!(c, i, src), I.columns)
copyrow!(I::Columns, i, src::Columns, j) = foreach((c1,c2)->copyelt!(c1, i, c2, j), I.columns, src.columns)
copyrow!(I::AbstractArray, i, src::AbstractArray, j) = (@inbounds I[i] = src[j])
pushrow!(to::Columns, from::Columns, i) = foreach((a,b)->push!(a, b[i]), to.columns, from.columns)
pushrow!(to::AbstractArray, from::AbstractArray, i) = push!(to, from[i])

@generated function rowless(c::Columns{D,C}, i, j) where {D,C}
    N = fieldcount(C)
    ex = :(cmpelts(getfield(c.columns,$N), i, j) < 0)
    for n in N-1:-1:1
        ex = quote
            let d = cmpelts(getfield(c.columns,$n), i, j)
                (d == 0) ? ($ex) : (d < 0)
            end
        end
    end
    ex
end

@generated function roweq(c::Columns{D,C}, i, j) where {D,C}
    N = fieldcount(C)
    ex = :(cmpelts(getfield(c.columns,1), i, j) == 0)
    for n in 2:N
        ex = :(($ex) && (cmpelts(getfield(c.columns,$n), i, j)==0))
    end
    ex
end

@inline roweq(x::AbstractVector, i, j) = x[i] == x[j]

# uses number of columns from `d`, assuming `c` has more or equal
# dimensions, for broadcast joins.
@generated function rowcmp(c::Columns, i, d::Columns{D}, j) where D
    N = fieldcount(D)
    ex = :(cmp(getfield(c.columns,$N)[i], getfield(d.columns,$N)[j]))
    for n in N-1:-1:1
        ex = quote
            let k = cmp(getfield(c.columns,$n)[i], getfield(d.columns,$n)[j])
                (k == 0) ? ($ex) : k
            end
        end
    end
    ex
end

@inline function rowcmp(c::AbstractVector, i, d::AbstractVector, j)
    cmp(c[i], d[j])
end

# test that the row on the right is "as of" the row on the left, i.e.
# all columns are equal except left >= right in last column.
# Could be generalized to some number of trailing columns, but I don't
# know whether that has applications.
@generated function row_asof(c::Columns{D,C}, i, d::Columns{D,C}, j) where {D,C}
    N = length(C.parameters)
    if N == 1
        ex = :(!isless(getfield(c.columns,1)[i], getfield(d.columns,1)[j]))
    else
        ex = :(isequal(getfield(c.columns,1)[i], getfield(d.columns,1)[j]))
    end
    for n in 2:N
        if N == n
            ex = :(($ex) && !isless(getfield(c.columns,$n)[i], getfield(d.columns,$n)[j]))
        else
            ex = :(($ex) && isequal(getfield(c.columns,$n)[i], getfield(d.columns,$n)[j]))
        end
    end
    ex
end

# map

"""
`map_rows(f, c...)`

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

const SpecialSelector = Union{Not, All, Keys, Between, Function, Regex}

hascolumns(t, s) = true
hascolumns(t, s::Symbol) = s in colnames(t)
hascolumns(t, s::Int) = s in 1:length(columns(t))
hascolumns(t, s::Tuple) = all(hascolumns(t, x) for x in s)
hascolumns(t, s::Not) = hascolumns(t, s.cols)
hascolumns(t, s::Between) = hascolumns(t, s.first) && hascolumns(t, s.last)
hascolumns(t, s::All) = all(hascolumns(t, x) for x in s.cols)

lowerselection(t, s)                     = s
lowerselection(t, s::Union{Int, Symbol}) = colindex(t, s)
lowerselection(t, s::Tuple)              = map(x -> lowerselection(t, x), s)
lowerselection(t, s::Not)                = excludecols(t, lowerselection(t, s.cols))
lowerselection(t, s::Keys)               = lowerselection(t, IndexedTables.pkeynames(t))
lowerselection(t, s::Between)            = Tuple(colindex(t, s.first):colindex(t, s.last))
lowerselection(t, s::Function)           = colindex(t, Tuple(filter(s, collect(colnames(t)))))
lowerselection(t, s::Regex)              = lowerselection(t, x -> occursin(s, string(x)))

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
    getfield(c.columns, x)
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

`itr` can be [`NDSparse`](@ref), [`Columns`](@ref), `AbstractVector`, or their distributed counterparts.

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

function Base.getindex(d::ColDict{<:Columns})
    Columns(d.columns...; names=d.names)
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
@inline _apply(f::Tup, y::Tup, x::Tup) = map(_apply, f, y, x)
@inline _apply(f, y, x) = f(y, x)
@inline _apply(f::Tup, x::Tup) = map(_apply, f, x)
@inline _apply(f, x) = f(x)

@inline init_first(f, x) = x
@inline init_first(f::OnlineStat, x) = (g=copy(f); fit!(g, x); g)
@inline init_first(f::Tup, x::Tup) = map(init_first, f, x)

# Initialize type of output, functions to apply, input and output vectors

function reduced_type(f, x, isvec, key = nothing)
    if key !== nothing
        _promote_op(f, eltype(key), typeof(x))
    elseif isvec
        _promote_op(f, typeof(x))
    else
        _promote_op((a,b)->_apply(f, init_first(f, a), b),
                    eltype(x), eltype(x))
    end
end

function init_inputs(f, x, gettype, isvec) # normal functions
    f, x, gettype(f, x, isvec)
end

nicename(f::Function) = typeof(f).name.mt.name
nicename(f) = Symbol(last(split(string(f), ".")))
nicename(o::OnlineStat) = Symbol(typeof(o).name.name)

function mapped_type(f, x, isvec)
    _promote_op(f, eltype(x))
end

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

function init_inputs(f::Tup, input, gettype, isvec)
    if isa(f, NamedTuple)
        return init_inputs((map(Pair, fieldnames(typeof(f)), f)...,), input, gettype, isvec)
    end
    fs, selectors = init_funcs(f, isvec)

    xs = map(s->s === nothing ? input : rows(input, s), selectors)

    output_eltypes = map((f,x) -> gettype(f, x, isvec), fs, xs)

    ns = fieldnames(typeof(fs))
    NT = namedtuple(ns...)

    # functions, input, output_eltype
    NT((fs...,)), rows(NT((xs...,))), NT{Tuple{output_eltypes...}}
end

### utils

compact_mem(x::Columns) = Columns(map(compact_mem, columns(x)))
