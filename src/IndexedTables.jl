module IndexedTables

using PooledArrays, SparseArrays, Statistics, WeakRefStrings

using OnlineStatsBase: OnlineStat, fit!

using StructArrays: StructVector, StructArray, foreachfield, fieldarrays,
    collect_structarray, staticschema, ArrayInitializer, refine_perm!, collect_structarray,
    collect_empty_structarray, grow_to_structarray!, collect_to_structarray!, replace_storage,
    GroupPerm, GroupJoinPerm, roweq, rowcmp, fastpermute!

import Tables, TableTraits, IteratorInterfaceExtensions, TableTraitsUtils

import DataValues: DataValue, DataValueArray, isna

import Base:
    show, eltype, length, getindex, setindex!, ndims, map, convert, keys, values,
    ==, broadcast, empty!, copy, similar, sum, merge, merge!, mapslices,
    permutedims, sort, sort!, iterate, pairs, reduce, push!, size, permute!, issorted,
    sortperm, summary, resize!, vcat, append!, copyto!, view, tail,
    tuple_type_cons, tuple_type_head, tuple_type_tail, in, convert


#-----------------------------------------------------------------------# exports
export
    # macros
    @cols,
    # types
    AbstractNDSparse, All, ApplyColwise, Between, ColDict, Columns, IndexedTable,
    Keys, NDSparse, NextTable, Not,
    # functions
    aggregate!, antijoin, asofjoin, collect_columns, colnames,
    column, columns, convertdim, dimlabels, flatten, flush!, groupby, groupjoin,
    groupreduce, innerjoin, insertafter!, insertbefore!, insertcol, insertcolafter,
    insertcolbefore, leftgroupjoin, leftjoin, map_rows, naturalgroupjoin, naturaljoin,
    ncols, ndsparse, outergroupjoin, outerjoin, pkeynames, pkeys, popcol, pushcol,
    reducedim_vec, reindex, renamecol, rows, select, selectkeys, selectvalues, setcol,
    stack, summarize, table, unstack, update!, where, dropmissing, dropna

const Tup = Union{Tuple,NamedTuple}
const DimName = Union{Int,Symbol}

include("utils.jl")
include("columns.jl")
include("indexedtable.jl")
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
include("tables.jl")
include("tabletraits.jl")

end # module
