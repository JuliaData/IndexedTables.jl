"""
    select(t::Table, which::Selection)

Select all or a subset of columns, or a single column from the table.

`Selection` is a type union of many types that can select from a table. It can be:

1. `Integer` -- returns the column at this position.
2. `Symbol` -- returns the column with this name.
3. `Pair{Selection => Function}` -- selects and maps a function over the selection, returns the result.
4. `AbstractArray` -- returns the array itself. This must be the same length as the table.
5. `Tuple` of `Selection` -- returns a table containing a column for every selector in the tuple. The tuple may also contain the type `Pair{Symbol, Selection}`, which the selection a name. The most useful form of this when introducing a new column.
6. `Regex` -- returns the columns with names that match the regular expression.
7. `Type` -- returns columns with elements of the given type.

# Examples:

    t = table(1:10, randn(10), rand(Bool, 10); names = [:x, :y, :z])

    # select the :x vector
    select(t, 1)
    select(t, :x)

    # map a function to the :y vector
    select(t, 2 => abs)
    select(t, :y => x -> x > 0 ? x : -x)

    # select the table of :x and :z
    select(t, (:x, :z))
    select(t, r"(x|z)")

    # map a function to the table of :x and :y
    select(t, (:x, :y) => row -> row[1] + row[2])
    select(t, (1, :y) => row -> row.x + row.y)
"""
function select(t::AbstractIndexedTable, which)
    ColDict(t)[which]
end

# optimization
@inline function select(t::IndexedTable, which::Union{Symbol, Int})
    getfield(columns(t), which)
end

"""
    selectkeys(x::NDSparse, sel)

Return an `NDSparse` with a subset of keys.
"""
function selectkeys(x::NDSparse, which; kwargs...)
    ndsparse(rows(keys(x), which), values(x); kwargs...)
end

"""
    selectvalues(x::NDSparse, sel)

Return an `NDSparse` with a subset of values
"""
function selectvalues(x::NDSparse, which; presorted=true, copy=false, kwargs...)
    ndsparse(keys(x), rows(values(x), which); presorted=presorted, copy=copy, kwargs...)
end

"""
    reindex(t::IndexedTable, by)
    reindex(t::IndexedTable, by, select)

Reindex table `t` with new primary key `by`, optionally keeping a subset of columns via
`select`.  For [`NDSparse`](@ref), use [`selectkeys`](@ref).

# Example

    t = table([2,1],[1,3],[4,5], names=[:x,:y,:z], pkey=(1,2))

    t2 = reindex(t, (:y, :z))

    pkeynames(t2)
"""
function reindex end

function reindex(T::Type, t, by, select; kwargs...)
    if isa(by, SpecialSelector)
        return reindex(T, t, lowerselection(t, by), select; kwargs...)
    end
    if !isa(by, Tuple)
        return reindex(T, t, (by,), select; kwargs...)
    end
    if T <: IndexedTable && !isa(select, Tuple) && !isa(select, SpecialSelector)
        return reindex(T, t, by, (select,); kwargs...)
    end
    perm = sortpermby(t, by)
    if isa(perm, Base.OneTo)
        convert(T, rows(t, by), rows(t, select); presorted=true, copy=false, kwargs...)
    else
        convert(T, rows(t, by)[perm], rows(t, select)[perm]; presorted=true, copy=false, kwargs...)
    end
end

function reindex(t::IndexedTable, by=pkeynames(t), select=excludecols(t, by); kwargs...)
    reindex(collectiontype(t), t, by, select; kwargs...)
end

function reindex(t::NDSparse, by=pkeynames(t), select=valuenames(t); kwargs...)
    reindex(collectiontype(t), t, by, select; kwargs...)
end

canonname(t, x::Symbol) = x
canonname(t, x::Int) = colnames(t)[colindex(t, x)]

"""
    map(f, t::IndexedTable; select)

Apply `f` to every item in `t` selected by `select` (see also the [`select`](@ref) function).  
Returns a new table if `f` returns a tuple or named tuple.  If not, returns a vector.

# Examples

    t = table([1,2], [3,4], names=[:x, :y])

    polar = map(p -> (r = hypot(p.x, p.y), θ = atan(p.y, p.x)), t)

    back2t = map(p -> (x = p.r * cos(p.θ), y = p.r * sin(p.θ)), polar)
"""
function map(f, t::AbstractIndexedTable; select=nothing) end

function map(f, t::Dataset; select=nothing, copy=false, kwargs...)
    if isa(f, Tup) && select === nothing
        select = colnames(t)
    elseif select === nothing
        select = valuenames(t)
    end

    x = map_rows(f, rows(t, select))
    isa(x, Columns) ? table(x; copy=false, kwargs...) : x
end


missing_indxs(v::Vector) = findall(!_ismissing, v)

function missing_indxs(t::StructArray)
    indxs = collect(1:length(t))
    for vec in getfield(t, :fieldarrays)
        filter!(i -> !_ismissing(vec[i]), indxs)
    end
    indxs
end

"""
    dropmissing(t        )
    dropmissing(t, select)

Drop rows of table `t` which contain missing values (either `Missing` or `DataValue`), 
optionally only using the columns in `select`.  Column types will be converted to 
non-missing types.  For example:

- `Vector{Union{Int, Missing}}` -> `Vector{Int}`
- `DataValueArray{Int}` -> Vector{Int}

# Example

    t = table([0.1,0.5,missing,0.7], [2,missing,4,5], [missing,6,missing,7], names=[:t,:x,:y])
    dropmissing(t)
    dropmissing(t, (:t, :x))
"""
function dropmissing(t::IndexedTable, sel = All())
    selection = lowerselection(t, sel)
    indxs = missing_indxs(rows(t, selection))
    t2 = subtable(t, indxs)
    d = ColDict(t2)
    for s in selection
        T = eltype(d[s])
        d[s] = convert(Vector{missingtype2type(T)}, d[s])
    end
    
    table(d[], copy=false, perms=t.perms, presorted=true)
end

dropmissing(t::NDSparse, sel=All()) = ndsparse(dropmissing(table(t), sel))

Base.@deprecate_binding dropna dropmissing

"""
    convertmissing(tbl, missingtype)

Convert the missing value representation in `tbl` to be of type `missingtype`.

# Example

    using IndexedTables, DataValues
    t = table([1,2,missing], [1,missing,3])
    IndexedTables.convertmissing(t, DataValue)
"""
function convertmissing(t::IndexedTable, ::Type{Missing}) 
    d = ColDict(t)
    for (k, v) in pairs(d)
        T = eltype(v)
        if T <: DataValue
            indxs = findall(!isna, v)
            y = Vector{Union{Missing, missingtype2type(T)}}(missing, length(v))
            y[indxs] = get.(v[indxs])
            d[k] = y
        end
    end
    subtable(d[], 1:length(t))
end
function convertmissing(t::IndexedTable, ::Type{DataValue}) 
    d = ColDict(t)
    for (k, v) in pairs(d)
        T = eltype(v)
        if Missing <: T 
            indxs = findall(!ismissing, v)
            y = DataValueArray(Vector{Base.nonmissingtype(T)}(undef, length(v)), trues(length(v)))
            y[indxs] = v[indxs]
            d[k] = y
        end
    end
    subtable(d[], 1:length(t))
end
convertmissing(t::NDSparse, Typ) = ndsparse(convertmissing(table(t), Typ))


"""
    filter(f, t::Union{IndexedTable, NDSparse}; select)

Iterate over `t` and Return the rows for which `f(row)` returns true.  `select` determines 
the rows that are given as arguments to `f` (see [`select`](@ref)).

`f` can also be a tuple of `column => function` pairs.  Returned rows will be those for
which all conditions are true.


# Example

    # filter iterates over ROWS of a IndexedTable
    t = table(rand(100), rand(100), rand(100), names = [:x, :y, :z])
    filter(r -> r.x + r.y + r.z < 1, t)

    # filter iterates over VALUES of an NDSparse
    x = ndsparse(1:100, randn(100))
    filter(val -> val > 0, x)
"""
function Base.filter(fn, t::Dataset; select=valuenames(t))
    x = rows(t, select)
    indxs = findall(fn, x)
    subtable(t, indxs, presorted=true)
end

function Base.filter(pred::Tuple, t::Dataset; select=nothing)
    indxs = [1:length(t);]
    x = select === nothing ? t : rows(t, select)
    for p in pred
        if isa(p, Pair)
            c, f = p
            filt_by_col!(f, rows(x, c), indxs)
        else
            filt_by_col!(p, x, indxs)
        end
    end
    subtable(t, indxs, presorted=true)
end

filt_by_col!(f, col, indxs) = filter!(i->f(col[i]), indxs)

function Base.filter(pred::Pair, t::Dataset; select=nothing)
    filter((pred,), t, select=select)
end

# We discard names of fields in a named tuple. keeps it consistent
# with map and reduce, we don't select using those
function Base.filter(pred::NamedTuple, t::Dataset; select=nothing)
    filter(astuple(pred), t, select=select)
end
