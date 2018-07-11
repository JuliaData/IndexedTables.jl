using IndexedTables
using OnlineStats
using Test
using WeakRefStrings

@testset "IndexedTables" begin

include("test_core.jl")
include("test_utils.jl")
#include("test_tabletraits.jl")
include("test_collect.jl")

end
