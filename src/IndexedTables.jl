module IndexedTables

using PooledArrays

import Base:
    show, eltype, length, getindex, setindex!, ndims, map, convert, keys, values,
    ==, broadcast, empty!, copy, similar, sum, merge, merge!, mapslices,
    permutedims, sort, sort!, iterate, pairs

export NDSparse, flush!, aggregate!, aggregate_vec, where, convertdim, columns, column, rows,
    update!, aggregate, reducedim_vec, dimlabels, collect_columns

const Tup = Union{Tuple,NamedTuple}
const DimName = Union{Int,Symbol}

include("utils.jl")
include("columns.jl")
include("table.jl")
include("ndsparse.jl")
include("collect.jl")

#=
# Poor man's traits

# These support `colnames` and `columns`
const TableTrait = Union{AbstractVector, IndexedTable, NDSparse}

# These support `colnames`, `columns`,
# `pkeynames`, `permcache`, `cacheperm!`
=#

const Dataset = Union{IndexedTable, NDSparse}

# no-copy convert
_convert(::Type{IndexedTable}, x::IndexedTable) = x
function _convert(::Type{NDSparse}, t::IndexedTable)
    NDSparse(rows(t, pkeynames(t)), rows(t, excludecols(t, pkeynames(t))),
             copy=false, presorted=true)
end

function _convert(::Type{IndexedTable}, x::NDSparse)
    convert(IndexedTable, x.index, x.data;
            perms=x._table.perms,
            presorted=true, copy=false)
end

ndsparse(t::IndexedTable; kwargs...) = _convert(NDSparse, t; kwargs...)
table(t::NDSparse; kwargs...) = _convert(IndexedTable, t; kwargs...)

include("sortperm.jl")
include("indexing.jl") # x[y]
include("selection.jl")
include("reduce.jl")
include("flatten.jl")
include("join.jl")
include("reshape.jl")

# TableTraits.jl integration
include("tabletraits.jl")

end # module
