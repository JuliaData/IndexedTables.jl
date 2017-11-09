import Base: setindex!, reduce, select
import DataValues: dropna
export NextTable, table, colnames, pkeynames, columns, pkeys, reindex, dropna

"""
A permutation

# Fields:

- `columns`: The columns being indexed as a vector of integers (column numbers)
- `perm`: the permutation - an array or iterator which has the sorted permutation
"""
struct Perm{X}
    columns::Vector{Int}
    perm::X
end

abstract type AbstractIndexedTable end

"""
A table.
"""
struct NextTable{C<:Columns} <: AbstractIndexedTable
    # `Columns` object which iterates to give an array of rows
    columns::C
    # columns that are primary keys (Vector{Int})
    pkey::Vector{Int}
    # Cache permutations by various subsets of columns
    perms::Vector{Perm}
    # store what percent of the data in each column is unique
    cardinality::Vector{Nullable{Float64}}

    columns_buffer::C
end

"""
`table(cols::AbstractVector...; names, pkey, presorted, copy, chunks)`

Create a table with columns given by `cols`.
```jldoctest
julia> a = table([1,2,3], [4,5,6])
Table with 3 rows, 2 columns:
1  2
────
1  4
2  5
3  6
```

`names` specify names for columns. If specified, the table will be an iterator of named tuples.

```jldoctest
julia> b = table([1,2,3], [4,5,6], names=[:x, :y])
Table with 3 rows, 2 columns:
x  y
────
1  4
2  5
3  6

```

`table(cols::Union{Tuple, NamedTuple}; pkey, presorted, copy, chunks)`

```jldoctest
julia> table(([1,2,3], [4,5,6])) == a
true

julia> table(@NT(x=[1,2,3], y=[4,5,6])) == b
true
```

Convert a struct of columns to a table of structs.

`table(cols::Columns; pkey, presorted, copy, chunks)`

Construct a table from a vector of tuples. See [`rows`](@ref) for constructing `Columns` object.

```jldoctest
julia> table(Columns([1,2,3], [4,5,6])) == a
true

julia> table(Columns(x=[1,2,3], y=[4,5,6])) == b
true
```

`table(t::Union{Table, NDSparse}; pkey=pkeynames(t), presorted=true, copy, chunks)`

Copy a Table or NDSparse to create a new table. The same primary keys as the input are used.

```jldoctest
julia> b == table(b)
true
```


# Arguments:

- `pkey`: select columns to act as the primary key. By default, no columns are used as primary key.
- `presorted`: is the data pre-sorted by primary key columns? If so, skip sorting. `false` by default. Irrelevant if `chunks` is specified.
- `copy`: creates a copy of the input vectors if `true`. `true` by default. Irrelavant if `chunks` is specified.
- `chunks`: distribute the table into `chunks` (Integer) chunks (a safe bet is nworkers()). Table is not distributed by default. See [Distributed](@distributed) docs.

# Examples:

Specifying `pkey` will cause the table to be sorted by the columns named in pkey:

```jldoctest
julia> b = table([2,3,1], [4,5,6], names=[:x, :y], pkey=:x)
Table with 3 rows, 2 columns:
x  y
────
1  6
2  4
3  5

julia> b = table([2,1,2,1],[2,3,1,3],[4,5,6,7], names=[:x, :y, :z], pkey=(:x,:y))
Table with 4 rows, 3 columns:
x  y  z
───────
1  3  5
1  3  7
2  1  6
2  2  4
```
Note that the keys do not have to be unique.

`chunks` attribute allows you to create a distributed table. Note this argument needs the JuliaDB package to be loaded.

```jldoctest
julia> t = table([2,3,1,4], [4,5,6,7], names=[:x, :y], pkey=:x, chunks=2)
Distributed Table with 4 rows in 2 chunks:
x  y
────
1  6
2  4
3  5
4  7
```

A distributed table will be constructed if one of the arrays passed into `table` constructor is a distributed
array. A distributed Array can be constructed using `distribute`:

```jldoctest

julia> x = distribute([1,2,3,4], 2);

julia> t = table(x, [5,6,7,8], names=[:x,:y])
Distributed Table with 4 rows in 2 chunks:
x  y
────
1  5
2  6
3  7
4  8

julia> table(columns(t)..., [9,10,11,12], names=[:x,:y,:z])
Distributed Table with 4 rows in 2 chunks:
x  y  z
────────
1  5  9
2  6  10
3  7  11
4  8  12

```

Distribution is done to match the first distributed column from left to right. Specify `chunks` to override this.
"""
function table end

function table(::Val{:serial}, cols::Tup;
               pkey=Int[],
               chunks=nothing, # unused here
               perms=Perm[],
               presorted=false,
               copy=true,
               cardinality=fill(Nullable{Float64}(), length(cols)))

    cs = rows(cols)

    if isa(pkey, Union{Int, Symbol})
        pkey = [pkey]
    elseif isa(pkey, Tuple)
        pkey = [pkey...]
    end

    if !presorted && !isempty(pkey)
        pkeys = rows(cs, (pkey...))
        if !issorted(pkeys)
            perm = sortperm(pkeys)
            if copy
                cs = cs[perm]
            else
                cs = permute!(cs, perm)
            end
        elseif copy
            cs = Base.copy(cs)
        end
    elseif copy
        cs = Base.copy(cs)
    end

    intpkey = map(k->colindex(cs, k), pkey)

    NextTable{typeof(cs)}(cs,
           intpkey,
           perms,
           cardinality,
           similar(cs, 0))
end

function table{impl}(::Val{impl}, cols; kwargs...)
    if impl == :distributed && isa(cols, Tup)
        error("""You requested to create a distributed table.
                 Distributed table is implemented by JuliaDB.
                 run `using JuliaDB` and try again.""")
    else
        error("unknown table implementation invoked")
    end
end

# detect if a distributed table has to be constructed.
_impl(impl::Val) = impl
_impl(impl::Val, x::AbstractArray, z...) = _impl(impl, z...)
_impl(x::AbstractArray...) = _impl(Val{:serial}(), x...)

function table(cs::Tup; chunks=nothing, kwargs...)
    if chunks !== nothing
        impl = Val{:distributed}()
    else
        impl = _impl(astuple(cs)...)
    end
    table(impl, cs; chunks=chunks, kwargs...)
end

table(cs::Columns; kwargs...) = table(columns(cs); kwargs...)

function table(cols::AbstractArray...; names=nothing, kwargs...)
    if isa(names, AbstractArray) && all(x->isa(x, Symbol), names)
        cs = namedtuple(names...)(cols...)
    else
        cs = cols
    end
    table(cs; kwargs...)
end

# Easy constructor to create a derivative table
function table(t::NextTable;
               columns=t.columns,
               pkey=t.pkey,
               perms=t.perms,
               cardinality=t.cardinality,
               presorted=false,
               copy=true)

    table(columns,
          pkey=pkey,
          perms=perms,
          cardinality=cardinality,
          presorted=presorted,
          copy=copy)
end

Base.@pure colnames(t::AbstractIndexedTable) = fieldnames(eltype(t))
columns(t::NextTable) = columns(t.columns)

Base.eltype(::Type{NextTable{C}}) where {C} = eltype(C)
Base.eltype(t::NextTable) = eltype(typeof(t))
Base.copy(t::NextTable) = NextTable(t)
Base.:(==)(a::NextTable, b::NextTable) = rows(a) == rows(b)

Base.getindex(t::NextTable, i::Integer) = getindex(t.columns, i)

Base.length(t::NextTable) = length(t.columns)
Base.start(t::NextTable) = start(t.columns)
Base.next(t::NextTable, i) = next(t.columns, i)
Base.done(t::NextTable, i) = done(t.columns, i)
function getindex(t::NextTable, idxs::AbstractVector{<:Integer})
    if issorted(idxs)
       #perms = map(t.perms) do p
       #    # TODO: make the ranks continuous
       #    Perm(p.columns, p.perm[idxs])
       #end
        perms = Perm[]
        table(t, columns=t.columns[idxs], perms=perms, copy=false)
    else
        # this is for gracefully allowing this later
        throw(ArgumentError("`getindex` called with unsorted index. This is not allowed at this time."))
    end
end

function Base.getindex(d::ColDict{<:AbstractIndexedTable}, key::Tuple)
    t = d[]
    idx = [colindex(t, k) for k in key]
    pkey = Int[]
    for (i, pk) in enumerate(t.pkey)
        j = findfirst(idx, pk)
        if j > 0
            push!(pkey, j)
        end
    end
    table(d.src, columns=columns(t, key), pkey=pkey)
end

ColDict(t::AbstractIndexedTable) = ColDict(copy(t.pkey), t,
                                copy(colnames(t)), Any[columns(t)...])

function Base.getindex(d::ColDict{<:AbstractIndexedTable})
    table(d.columns...; names=d.names, pkey=d.pkey)
end

subtable(t::NextTable, r) = t[r]

function primaryperm(t::NextTable)
    Perm(t.pkey, Base.OneTo(length(t)))
end

permcache(t::NextTable) = [primaryperm(t), t.perms;]
cacheperm!(t::NextTable, p) = push!(t.perms, p)

"""
`pkeynames(t::Table)`

Names of the primary key columns in `t`.

# Example

```jldoctest

julia> t = table([1,2], [3,4]);

julia> pkeynames(t)
()

julia> t = table([1,2], [3,4], pkey=1);

julia> pkeynames(t)
(1,)

julia> t = table([2,1],[1,3],[4,5], names=[:x,:y,:z], pkey=(1,2));

julia> pkeys(t)
2-element IndexedTables.Columns{NamedTuples._NT_x_y{Int64,Int64},NamedTuples._NT_x_y{Array{Int64,1},Array{Int64,1}}}:
 (x = 1, y = 3)
 (x = 2, y = 1)

```
"""
function pkeynames(t::AbstractIndexedTable)
    if eltype(t) <: NamedTuple
        (colnames(t)[t.pkey]...)
    else
        (t.pkey...)
    end
end

# for a table, selecting the "value" means selecting all fields
valuenames(t::AbstractIndexedTable) = (colnames(t)...)

"""
    pkeys(itr::Table)

Primary keys of the table. If Table doesn't have any designated
primary key columns (constructed without `pkey` argument) then
a default key of tuples `(1,):(n,)` is generated.

# Example

```jldoctest

julia> a = table(["a","b"], [3,4]) # no pkey
Table with 2 rows, 2 columns:
1    2
──────
"a"  3
"b"  4

julia> pkeys(a)
2-element Columns{Tuple{Int64}}:
 (1,)
 (2,)

julia> a = table(["a","b"], [3,4], pkey=1)
Table with 2 rows, 2 columns:
1    2
──────
"a"  3
"b"  4

julia> pkeys(a)
2-element Columns{Tuple{String}}:
 ("a",)
 ("b",)
```

"""
function pkeys(t::NextTable)
    if isempty(t.pkey)
        Columns(Base.OneTo(length(t)))
    else
        rows(t, pkeynames(t))
    end
end

Base.values(t::NextTable) = rows(t)

"""
    excludecols(itr, cols)

Names of all columns in `itr` except `cols`. `itr` can be any of
`Table`, `NDSparse`, `Columns`, or `AbstractVector`

```jldoctest
julia> t = table([2,1],[1,3],[4,5], names=[:x,:y,:z], pkey=(1,2))
Table with 2 rows, 3 columns:
x  y  z
───────
1  3  5
2  1  4

julia> excludecols(t, (:x,))
(:y, :z)

julia> excludecols(t, (2,))
(:x, :z)

julia> excludecols(t, pkeynames(t))
(:z,)

julia> excludecols([1,2,3], (1,))
()

```
"""
function excludecols(t, cols)
    if !isa(cols, Tuple)
        return excludecols(t, (cols,))
    end
    ns = colnames(t)
    mask = ones(Bool, length(ns))
    for c in cols
        i = colindex(t, c)
        if i !== 0
            mask[i] = false
        end
    end
    (ns[mask]...)
end

"""
    convert(NextTable, pkeys, vals; kwargs...)

Construct a table with `pkeys` as primary keys and `vals` as corresponding non-indexed items.
keyword arguments will be forwarded to [`table`](@ref) constructor.

# Example

```jldoctest
julia> convert(NextTable, Columns(x=[1,2],y=[3,4]), Columns(z=[1,2]), presorted=true)
Table with 2 rows, 3 columns:
x  y  z
───────
1  3  1
2  4  2
```
"""
function convert(::Type{NextTable}, key, val; kwargs...)
    cs = concat_cols(key, val)
    table(cs, pkey=[1:ncols(key);]; kwargs...)
end

# showing

import Base.Markdown.with_output_format

function showtable(io::IO, t; header=nothing, cnames=colnames(t), divider=nothing, cstyle=[], full=false, ellipsis=:middle)
    height, width = displaysize(io) 
    showrows = height-5 - (header !== nothing)
    n = length(t)
    header !== nothing && println(io, header)
    if full
        rows = [1:n;]
        showrows = n
    else
        if ellipsis == :middle
            lastfew = div(showrows, 2) - 1
            firstfew = showrows - lastfew - 1
            rows = n > showrows ? [1:firstfew; (n-lastfew+1):n] : [1:n;]
        elseif ellipsis == :end
            lst = n == showrows ?
                showrows : showrows-1 # make space for ellipse
            rows = [1:min(length(t), showrows);]
        else
            error("ellipsis must be either :middle or :end")
        end
    end
    nc = length(columns(t))
    reprs  = [ sprint(io->showcompact(io,columns(t)[j][i])) for i in rows, j in 1:nc ]
    strcnames = map(string, cnames)
    widths  = [ max(strwidth(get(strcnames, c, "")), isempty(reprs) ? 0 : maximum(map(strwidth, reprs[:,c]))) for c in 1:nc ]
    if sum(widths) + 2*nc > width
        return showmeta(io, t, cnames)
    end
    for c in 1:nc
        nm = get(strcnames, c, "")
        style = get(cstyle, c, nothing)
        txt = c==nc ? nm : rpad(nm, widths[c]+(c==divider ? 1 : 2), " ")
        if style == nothing
            print(io, txt)
        else
            with_output_format(style, print, io, txt)
        end
        if c == divider
            print(io, "│")
            length(cnames) > divider && print(io, " ")
        end
    end
    println(io)
    if divider !== nothing
        print(io, "─"^(sum(widths[1:divider])+2*divider-1), "┼", "─"^(sum(widths[divider+1:end])+2*(nc-divider)-1))
    else
        print(io, "─"^(sum(widths)+2*nc-2))
    end
    for r in 1:size(reprs,1)
        println(io)
        for c in 1:nc
            print(io, c==nc ? reprs[r,c] : rpad(reprs[r,c], widths[c]+(c==divider ? 1 : 2), " "))
            if c == divider
                print(io, "│ ")
            end
        end
        if n > showrows && ((ellipsis == :middle && r == firstfew) || (ellipsis == :end && r == size(reprs, 1)))
            if divider === nothing
                println(io)
                print(io, "⋮")
            else
                println(io)
                print(io, " "^(sum(widths[1:divider]) + 2*divider-1), "⋮")
            end
        end
    end
end

function showmeta(io, t, cnames)
    nc = length(columns(t))
    println(io, "Columns:")
    metat = Columns(([1:nc;], [Text(string(get(cnames, i, "<noname>"))) for i in 1:nc],
                       eltype.([columns(t)...])))
    showtable(io, metat, cnames=["#", "colname", "type"], cstyle=fill(:bold, nc), full=true)
end

function show(io::IO, t::NextTable{T}) where {T}
    header = "Table with $(length(t)) rows, $(length(columns(t))) columns:"
    cstyle = Dict([i=>:bold for i in t.pkey])
    showtable(io, t, header=header, cstyle=cstyle)
end

function Base.merge(a::NextTable, b::NextTable)
    @assert colnames(a) == colnames(b)
    @assert a.pkey == b.pkey
    table(map(vcat, columns(a), columns(b)), pkey=a.pkey, copy=false)
end