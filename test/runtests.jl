using Test, IndexedTables, OnlineStats, WeakRefStrings, Tables, Random, Dates, 
    PooledArrays, SparseArrays, WeakRefStrings, LinearAlgebra, Statistics,
    TableTraits, IteratorInterfaceExtensions, Serialization

using IndexedTables: excludecols, sortpermby, primaryperm, best_perm_estimate, hascolumns,
    collect_columns_flattened

if VERSION < v"1.0-"
    select = IndexedTables.select
end

include("test_tables.jl")
include("test_missing.jl")
include("test_join.jl")
include("test_core.jl")
include("test_utils.jl")
include("test_tabletraits.jl")
include("test_collect.jl")