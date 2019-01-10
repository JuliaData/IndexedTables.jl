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
A tabular data structure that extends [`Columns`](@ref).  Create an `IndexedTable` with the 
[`table`](@ref) function.
"""
struct IndexedTable{C<:Columns} <: AbstractIndexedTable
    # `Columns` object which iterates to give an array of rows
    columns::C
    # columns that are primary keys (Vector{Int})
    pkey::Vector{Int}
    # Cache permutations by various subsets of columns
    perms::Vector{Perm}
    # store what percent of the data in each column is unique
    cardinality::Vector{Union{Float64,Missing}}

    columns_buffer::Any
end

Base.@deprecate_binding NextTable IndexedTable

"""
    table(cols; kw...)

Create a table from a (named) tuple of AbstractVectors.

    table(cols::AbstractVector...; names::Vector{Symbol}, kw...)

Create a table from the provided `cols`, optionally with `names`.

    table(cols::Columns; kw...)

Construct a table from a vector of tuples. See [`rows`](@ref) and [`Columns`](@ref).

    table(t::Union{IndexedTable, NDSparse}; kw...)

Copy a Table or NDSparse to create a new table. The same primary keys as the input are used.

    table(x; kw...)

Create an `IndexedTable` from any object `x` that follows the `Tables.jl` interface.


# Keyword Argument Options:

- `pkey`: select columns to sort by and be the primary key.
- `presorted = false`: is the data pre-sorted by primary key columns? 
- `copy = true`: creates a copy of the input vectors if `true`. Irrelevant if `chunks` is specified.
- `chunks::Integer`: distribute the table.  Options are:
    - `Int` -- (number of chunks) a safe bet is `nworkers()` after `using Distributed`.
    - `Vector{Int}` -- Number of elements in each of the `length(chunks)` chunks.

# Examples:

    table(rand(10), rand(10), names = [:x, :y], pkey = :x)

    table(rand(Bool, 20), rand(20), rand(20), pkey = [1,2])

    table((x = 1:10, y = randn(10)))

    table([(1,2), (3,4)])
"""
function table end

function table(::Val{:serial}, cols::Tup;
               pkey=Int[],
               chunks=nothing, # unused here
               perms=Perm[],
               presorted=false,
               copy=true,
               cardinality=fill(missing, length(cols)))

    cs = rows(cols)

    if isa(pkey, Union{Int, Symbol})
        pkey = [pkey]
    elseif isa(pkey, Tuple)
        pkey = [pkey...]
    end

    if !presorted && !isempty(pkey)
        pkeys = rows(cs, (pkey...,))
        if !issorted(pkeys)
            perm = sortperm(pkeys)
            if copy
                cs = cs[perm]
            else
                cs = permute!(cs, perm)
            end
        elseif copy
            cs = copyto!(similar(cs), cs)
        end
    elseif copy
        cs = copyto!(similar(cs), cs)
    end

    intpkey = map(k->colindex(cs, k), pkey)

    IndexedTable{typeof(cs)}(cs,
           intpkey,
           perms,
           cardinality,
           similar(cs, 0))
end

function table(::Val{impl}, cols; kwargs...) where impl
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

# table methods go through here
function table(cs::Tup; chunks=nothing, kwargs...)
    impl = chunks !== nothing ? Val(:distributed) : _impl(astuple(cs)...)
    table(impl, cs; chunks=chunks, kwargs...)
end

table(cs::Columns; kwargs...) = table(columns(cs); kwargs...)
table(c::Columns{<:Pair}; kwargs...) = convert(IndexedTable, columns(c).first, columns(c).second; kwargs...)

function table(cols::AbstractArray...; names=nothing, kwargs...)
    if isa(names, AbstractArray) && all(x->isa(x, Symbol), names)
        cs = namedtuple(names...)(cols)
    else
        cs = cols
    end
    table(cs; kwargs...)
end

# Easy constructor to create a derivative table
function table(t::IndexedTable;
               columns=t.columns,
               chunks=nothing,
               pkey=t.pkey,
               perms=t.perms,
               cardinality=t.cardinality,
               presorted=false,
               copy=true)

    table(columns,
          pkey=pkey,
          perms=perms,
          chunks=chunks,
          cardinality=cardinality,
          presorted=presorted,
          copy=copy)
end

Base.@pure colnames(t::AbstractIndexedTable) = fieldnames(eltype(t))
columns(t::IndexedTable) = columns(t.columns)
# throw a better error message when a custom array
# of different size is used
function column(t::IndexedTable, a::AbstractArray)
    if length(t) != length(a)
        throw(ArgumentError(
                "vector provided must have the same length as table"
             )
        )
    end
    column(rows(t), a)
end

Base.eltype(::Type{IndexedTable{C}}) where {C} = eltype(C)
Base.eltype(t::IndexedTable) = eltype(typeof(t))
Base.copy(t::IndexedTable) = table(t, copy=true)
function Base.empty!(t::IndexedTable)
    empty!(t.perms)
    empty!(rows(t))
    t
end
Base.:(==)(a::IndexedTable, b::IndexedTable) = rows(a) == rows(b)
Base.isequal(a::IndexedTable, b::IndexedTable) = isequal(rows(a), rows(b))

Base.getindex(t::IndexedTable, i::Integer) = getindex(t.columns, i)
Base.getindex(t::IndexedTable, i::Colon) = copy(t)
Base.lastindex(t::IndexedTable) = length(t)

function Base.view(t::IndexedTable, I)
    t.pkey == Int64[] || eltype(I) == Bool || issorted(I) ||
        throw(ArgumentError("`view` called with unsorted index."))
    table(
        view(t.columns, I),
        pkey = t.pkey,
        copy = false,
        presorted = true)
end

Base.length(t::IndexedTable) = length(t.columns)
Base.iterate(t::IndexedTable, i) = iterate(t.columns, i)
Base.iterate(t::IndexedTable) = iterate(t.columns)
function getindex(t::IndexedTable, idxs::AbstractVector{<:Integer})
    if t.pkey == Int64[] || eltype(idxs) == Bool || issorted(idxs)
       #perms = map(t.perms) do p
       #    # TODO: make the ranks continuous
       #    Perm(p.columns, p.perm[idxs])
       #end
        perms = Perm[]
        table(t, columns=t.columns[idxs], perms=perms, copy=false, presorted=true)
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
        j = something(findfirst(isequal(pk), idx), 0)
        if j > 0
            push!(pkey, j)
        end
    end
    table(d.src, columns=columns(t, key), pkey=pkey)
end

function Base.getindex(d::ColDict{<:AbstractIndexedTable}, key::SpecialSelector)
    getindex(d, lowerselection(d[], key))
end

function ColDict(t::AbstractIndexedTable; copy=nothing)
    ColDict(Base.copy(t.pkey), t,
            convert(Array{Any}, Base.copy(collect(colnames(t)))),
            Any[columns(t)...], copy)
end

function Base.getindex(d::ColDict{<:AbstractIndexedTable})
    table(d.columns...;
          names=d.names,
          copy=d.copy === nothing ? false : d.copy,
          pkey=d.pkey)
end

function subtable(t::Union{Columns, IndexedTable}, idxs; presorted=true)
    table(t, columns=rows(t)[idxs], perms=t.perms, copy=false, presorted=presorted)
end

function primaryperm(t::IndexedTable)
    Perm(t.pkey, Base.OneTo(length(t)))
end

permcache(t::IndexedTable) = vcat(primaryperm(t), t.perms)
cacheperm!(t::IndexedTable, p) = push!(t.perms, p)

"""
    pkeynames(t::Table)

Names of the primary key columns in `t`.

# Examples

    t = table([1,2], [3,4]);
    pkeynames(t)

    t = table([1,2], [3,4], pkey=1);
    pkeynames(t)

    t = table([2,1],[1,3],[4,5], names=[:x,:y,:z], pkey=(1,2));
    pkeynames(t)
"""
function pkeynames(t::AbstractIndexedTable)
    if eltype(t) <: NamedTuple
        (colnames(t)[t.pkey]...,)
    else
        (t.pkey...,)
    end
end

# for a table, selecting the "value" means selecting all fields
valuenames(t::AbstractIndexedTable) = (colnames(t)...,)

"""
    pkeys(itr::IndexedTable)

Primary keys of the table. If Table doesn't have any designated
primary key columns (constructed without `pkey` argument) then
a default key of tuples `(1,):(n,)` is generated.

# Example

    a = table(["a","b"], [3,4]) # no pkey
    pkeys(a)

    a = table(["a","b"], [3,4], pkey=1)
    pkeys(a)
"""
function pkeys(t::IndexedTable)
    if isempty(t.pkey)
        Columns((Base.OneTo(length(t)),))
    else
        rows(t, pkeynames(t))
    end
end

Base.values(t::IndexedTable) = rows(t)

"""
    sort(t    ; select, kw...)
    sort(t, by; select, kw...)

Sort rows by `by`. All of `Base.sort` keyword arguments can be used.

# Examples

    t=table([1,1,1,2,2,2], [1,1,2,2,1,1], [1,2,3,4,5,6],
    sort(t, :z; select = (:y, :z), rev = true)
"""
sort(t::IndexedTable, by...; select = valuenames(t), kwargs...) =
    table(rows(t, select)[sortperm(rows(t, by...); kwargs...)], copy = false)

"""
    sort!(t    ; kw...)
    sort!(t, by; kw...)

Sort rows of `t` by `by` in place. All of `Base.sort` keyword arguments can be used.

# Examples

    t = table([1,1,1,2,2,2], [1,1,2,2,1,1], [1,2,3,4,5,6], names=[:x,:y,:z]);
    sort!(t, :z, rev = true)
    t
"""
function sort!(t::IndexedTable, by...; kwargs...)
    isempty(t.pkey) || error("Tables with primary keys can't be sorted in place")
    permute!(rows(t), sortperm(rows(t, by...); kwargs...))
    t
end

"""
    excludecols(itr, cols) -> Tuple of Int

Names of all columns in `itr` except `cols`. `itr` can be any of
`Table`, `NDSparse`, `Columns`, or `AbstractVector`

# Examples

    using IndexedTables: excludecols

    t = table([2,1],[1,3],[4,5], names=[:x,:y,:z], pkey=(1,2))

    excludecols(t, (:x,))
    excludecols(t, (2,))
    excludecols(t, pkeynames(t))
    excludecols([1,2,3], (1,))
"""
excludecols(t, cols) = excludecols(t, (cols,))
excludecols(t, cols::SpecialSelector) = excludecols(t, lowerselection(t, cols))
function excludecols(t, cols::Tuple) 
    Tuple(setdiff(1:length(colnames(t)), map(x -> colindex(t, x), cols)))
end

"""
    convert(IndexedTable, pkeys, vals; kwargs...)

Construct a table with `pkeys` as primary keys and `vals` as corresponding non-indexed items.
keyword arguments will be forwarded to [`table`](@ref) constructor.

# Example
    convert(IndexedTable, Columns(x=[1,2],y=[3,4]), Columns(z=[1,2]), presorted=true)
"""
function convert(::Type{IndexedTable}, key, val; pkey = (), kwargs...)
    cs = concat_cols(key, val)
    table(cs; pkey=Tuple(1:ncols(key)), kwargs...)
end

convert(T::Type{IndexedTable}, c::Columns{<:Pair}; kwargs...) = convert(T, c.first, c.second; kwargs...)
# showing

global show_compact_when_wide = true
function set_show_compact!(flag=true)
    global show_compact_when_wide
    show_compact_when_wide = flag
end

function showtable(io::IO, t; header=nothing, cnames=colnames(t), divider=nothing, cstyle=[], full=false, ellipsis=:middle, compact=show_compact_when_wide)
    cnames = collect(cnames)
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

    reprs  = [ sprint(io->show(IOContext(io, :compact => true), columns(t)[j][i])) for i in rows, j in 1:nc ]
    strcnames = map(string, cnames)
    widths  = [ max(textwidth(get(strcnames, c, "")), isempty(reprs) ? 0 : maximum(map(textwidth, reprs[:,c]))) for c in 1:nc ]
    if compact && !isempty(widths) && sum(widths) + 2*nc > width
        return showmeta(io, t, cnames)
    end
    for c in 1:nc
        nm = get(strcnames, c, "")
        style = get(cstyle, c, nothing)
        txt = c==nc && divider!=nc ? nm : rpad(nm, widths[c]+(c==divider ? 1 : 2), " ")
        if style == nothing
            print(io, txt)
        else
            Base.with_output_color(print, style, io, txt)
        end
        if c == divider
            print(io, "│")
            length(cnames) > divider && print(io, " ")
        end
    end
    println(io)
    if divider !== nothing
        print(io, "─"^(sum(widths[1:divider])+2*divider-1), "┼")
        if !isempty(widths[divider+1:end])
            print(io, "─"^(sum(widths[divider+1:end])+2*(nc-divider)-1))
        end
    else
        if !isempty(widths)
            print(io, "─"^(sum(widths)+2*nc-2))
        end
    end
    for r in 1:size(reprs,1)
        println(io)
        for c in 1:nc
            print(io, c==nc && nc!=divider ? reprs[r,c] : rpad(reprs[r,c], widths[c]+(c==divider ? 1 : 2), " "))
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
                     [map(eltype, columns(t))...]))
    showtable(io, metat, cnames=["#", "colname", "type"], cstyle=fill(:bold, nc), full=true, compact=false)
end

function subscriptprint(x::Integer)
    s = string(x)
    cs = Char[]
    lookup = ["₀₁₂₃₄₅₆₇₈₉"...]
    join([lookup[parse(Int, c)+1] for c in s],"")
end

function show(io::IO, t::IndexedTable{T}) where {T}
    header = "Table with $(length(t)) rows, $(length(columns(t))) columns:"
    cstyle = Dict([i=>:bold for i in t.pkey])
    cnames = string.(colnames(t))
    for (i, k) in enumerate(t.pkey)
        cstyle[k] = :bold
        #cnames[k] = cnames[k] * "$(subscriptprint(i))"
    end
    showtable(io, t, header=header, cnames=cnames, cstyle=cstyle)
end
